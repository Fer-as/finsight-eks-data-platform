"""Least-privilege PostgreSQL roles (scripts/bootstrap_roles.py) against a disposable server.

Each test run creates its own database and uniquely named roles as the test superuser, then drops
them, so it never changes the shared finsight_test database or other roles.
"""

import importlib.util
import os
import secrets
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient
from finsight_api.main import app
from finsight_pipelines.etl import run
from finsight_pipelines.settings import load_config
from finsight_pipelines.synthetic import generate
from psycopg import errors, sql

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        os.environ.get("FINSIGHT_INTEGRATION") != "1",
        reason="Set FINSIGHT_INTEGRATION=1 with isolated PostgreSQL",
    ),
]
ROOT = Path(__file__).resolve().parents[2]


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


roles = load("bootstrap_roles", "scripts/bootstrap_roles.py")
migration = load("migration", "scripts/migrate.py")


def connect(dbname: str, user: str, password: str, **kwargs) -> psycopg.Connection:
    return psycopg.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=dbname,
        user=user,
        password=password,
        connect_timeout=5,
        **kwargs,
    )


@pytest.fixture
def cluster():
    """An isolated database plus writer and reader roles, bootstrapped by the test superuser."""
    if os.environ.get("PGDATABASE") != "finsight_test":
        pytest.fail("Integration tests require PGDATABASE=finsight_test")
    suffix = secrets.token_hex(4)
    db = f"finsight_roles_{suffix}"
    names = {"db": db, "writer": f"fr_writer_{suffix}", "reader": f"fr_reader_{suffix}"}
    passwords = {"writer": secrets.token_urlsafe(24), "reader": secrets.token_urlsafe(24)}
    with psycopg.connect(autocommit=True) as admin:
        admin.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(db)))
    try:
        with psycopg.connect(dbname=db) as admin:
            roles.bootstrap(
                admin, names["writer"], passwords["writer"], names["reader"], passwords["reader"]
            )
        with connect(db, names["writer"], passwords["writer"], autocommit=True) as writer:
            migration.migrate(writer, ROOT / "warehouse/migrations")
        yield {**names, "passwords": passwords}
    finally:
        with psycopg.connect(autocommit=True) as admin:
            admin.execute(
                sql.SQL("DROP DATABASE IF EXISTS {} WITH (FORCE)").format(sql.Identifier(db))
            )
            for role in (names["reader"], names["writer"], f"fr_other_{suffix}"):
                admin.execute(sql.SQL("DROP ROLE IF EXISTS {}").format(sql.Identifier(role)))


def as_reader(cluster, **kwargs):
    return connect(cluster["db"], cluster["reader"], cluster["passwords"]["reader"], **kwargs)


def as_writer(cluster, **kwargs):
    return connect(cluster["db"], cluster["writer"], cluster["passwords"]["writer"], **kwargs)


def denied(connection_factory, statement: str, error=errors.InsufficientPrivilege):
    """Run one statement in its own read-write transaction and expect it to be refused."""
    with connection_factory() as connection:
        with pytest.raises(error):
            with connection.transaction():
                connection.execute("SET TRANSACTION READ WRITE")
                connection.execute(statement)


def test_roles_have_no_elevated_attributes_and_scram_passwords(cluster):
    with psycopg.connect(dbname=cluster["db"]) as admin:
        rows = admin.execute(
            """SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls,
                      rolinherit, left(rolpassword, 14)
                 FROM pg_authid WHERE rolname IN (%s, %s)""",
            (cluster["writer"], cluster["reader"]),
        ).fetchall()
        owner = admin.execute(
            "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = %s", (cluster["db"],)
        ).fetchone()[0]
    assert len(rows) == 2
    for name, *flags, inherit, password in rows:
        assert flags == [False] * 5, name
        assert inherit is False
        assert password == "SCRAM-SHA-256$"
    assert owner == cluster["writer"]


def test_writer_loads_data_and_the_api_serves_it_as_the_reader(cluster, tmp_path, monkeypatch):
    config = {**load_config(), "transactions": 200}
    generate(tmp_path / "raw", config)
    monkeypatch.setenv("PGDATABASE", cluster["db"])
    monkeypatch.setenv("PGUSER", cluster["writer"])
    monkeypatch.setenv("PGPASSWORD", cluster["passwords"]["writer"])
    run(tmp_path / "raw", tmp_path, config)

    monkeypatch.setenv("PGUSER", cluster["reader"])
    monkeypatch.setenv("PGPASSWORD", cluster["passwords"]["reader"])
    client = TestClient(app)
    assert client.get("/api/health/ready").status_code == 200
    dashboard = client.get("/api/dashboard", params={"start": "2025-01-01", "end": "2026-01-01"})
    assert dashboard.status_code == 200
    body = dashboard.json()
    assert body["has_data"] is True and float(body["summary"]["revenue"]) > 0
    assert body["latest_pipeline"] is not None
    window = {"start": "2025-01-01", "end": "2026-01-01"}
    assert client.get("/api/transactions", params={**window, "limit": 5}).status_code == 200
    assert client.get("/api/departments").status_code == 200


def test_reader_sessions_are_read_only_by_default(cluster):
    with as_reader(cluster) as reader:
        assert reader.execute("SELECT count(*) FROM curated.departments").fetchone()[0] == 0
        assert reader.execute("SHOW default_transaction_read_only").fetchone()[0] == "on"
        with pytest.raises(errors.ReadOnlySqlTransaction):
            reader.execute("INSERT INTO curated.departments VALUES ('x', 'x')")


@pytest.mark.parametrize(
    "statement",
    [
        "INSERT INTO curated.departments VALUES ('x', 'x')",
        "UPDATE curated.departments SET name = 'x'",
        "DELETE FROM curated.departments",
        "TRUNCATE curated.transactions",
        "INSERT INTO ops.pipeline_runs(status, source_sha256) VALUES ('running', 'x')",
        "UPDATE ops.pipeline_runs SET status = 'x'",
        "SELECT * FROM public.schema_migrations",
    ],
)
def test_reader_cannot_write_even_in_a_read_write_transaction(cluster, statement):
    denied(lambda: as_reader(cluster), statement)


@pytest.mark.parametrize(
    "statement",
    [
        "CREATE TABLE curated.injected (id int)",
        "CREATE TABLE public.injected (id int)",
        "CREATE TEMP TABLE injected (id int)",
        "CREATE SCHEMA injected",
        "ALTER TABLE curated.departments ADD COLUMN injected int",
        "DROP TABLE curated.departments",
        "CREATE INDEX injected ON curated.entries (amount_pence)",
        "CREATE FUNCTION public.injected() RETURNS int LANGUAGE sql AS 'SELECT 1'",
    ],
)
def test_reader_cannot_run_ddl(cluster, statement):
    denied(lambda: as_reader(cluster), statement)


@pytest.mark.parametrize(
    "statement",
    [
        "CREATE ROLE injected",
        "ALTER ROLE CURRENT_USER SUPERUSER",
        "ALTER ROLE CURRENT_USER CREATEROLE",
        "ALTER ROLE CURRENT_USER CREATEDB",
        "ALTER ROLE CURRENT_USER BYPASSRLS",
        "COPY curated.departments TO PROGRAM 'id'",
        "SELECT pg_read_file('/etc/passwd')",
    ],
)
def test_reader_cannot_escalate_privileges(cluster, statement):
    denied(lambda: as_reader(cluster), statement)


def test_reader_cannot_assume_or_grant_the_writer_role(cluster):
    writer = f'"{cluster["writer"]}"'  # a plain lowercase identifier, checked by bootstrap
    denied(lambda: as_reader(cluster), f"SET ROLE {writer}")
    denied(lambda: as_reader(cluster), f"GRANT {writer} TO CURRENT_USER")
    with as_reader(cluster, autocommit=True) as reader:
        # Without the grant option PostgreSQL only warns; the privilege must still be absent.
        reader.execute("SET default_transaction_read_only = off")
        reader.execute("GRANT INSERT ON curated.departments TO CURRENT_USER")
        assert not reader.execute(
            "SELECT has_table_privilege(current_user, 'curated.departments', 'INSERT')"
        ).fetchone()[0]


def test_writer_can_write_but_cannot_create_roles_or_become_superuser(cluster):
    with as_writer(cluster) as writer:
        writer.execute("INSERT INTO curated.departments VALUES ('d1', 'Department')")
        writer.execute("TRUNCATE curated.transactions")
        writer.execute("CREATE TABLE curated.later (id int)")
        writer.commit()
    denied(lambda: as_writer(cluster), "CREATE ROLE injected")
    denied(lambda: as_writer(cluster), "ALTER ROLE CURRENT_USER SUPERUSER")
    # Default privileges: a table the writer creates later is readable by the reader.
    with as_reader(cluster) as reader:
        assert reader.execute("SELECT count(*) FROM curated.later").fetchone()[0] == 0
        assert reader.execute("SELECT count(*) FROM curated.departments").fetchone()[0] == 1


def test_other_roles_cannot_connect(cluster):
    other = cluster["writer"].replace("fr_writer_", "fr_other_")
    password = secrets.token_urlsafe(24)
    with psycopg.connect(autocommit=True) as admin:
        admin.execute(
            sql.SQL("CREATE ROLE {} LOGIN PASSWORD {}").format(
                sql.Identifier(other), sql.Literal(roles.scram_verifier(password))
            )
        )
    with pytest.raises(psycopg.OperationalError, match="permission denied for database"):
        connect(cluster["db"], other, password).close()


def test_bootstrap_is_idempotent_and_rotates_passwords(cluster):
    old = cluster["passwords"]["reader"]
    new = secrets.token_urlsafe(24)
    writer, writer_password = cluster["writer"], cluster["passwords"]["writer"]
    with psycopg.connect(dbname=cluster["db"]) as admin:
        roles.bootstrap(admin, writer, writer_password, cluster["reader"], new)
        roles.bootstrap(admin, writer, writer_password, cluster["reader"], new)
    with pytest.raises(psycopg.OperationalError, match="password authentication failed"):
        connect(cluster["db"], cluster["reader"], old).close()
    with connect(cluster["db"], cluster["reader"], new) as reader:
        assert reader.execute("SELECT count(*) FROM curated.departments").fetchone()[0] == 0


@pytest.mark.parametrize(
    "writer, writer_password, reader, reader_password",
    [
        ("Bad-Name", "x" * 16, "fr_reader", "y" * 16),
        ("fr_writer", "short", "fr_reader", "y" * 16),
        ("fr_same", "x" * 16, "fr_same", "y" * 16),
    ],
)
def test_bootstrap_rejects_unsafe_input(cluster, writer, writer_password, reader, reader_password):
    with psycopg.connect(dbname=cluster["db"]) as admin, pytest.raises(ValueError):
        roles.bootstrap(admin, writer, writer_password, reader, reader_password)

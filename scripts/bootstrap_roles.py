"""Create or update FinSight's least-privilege PostgreSQL roles. Run as the bootstrap administrator.

Roles:
- administrator: the bootstrap superuser (POSTGRES_USER). Used only for this script and maintenance.
- writer (default finsight_app): owns the database and the curated and ops schemas; runs migrations
  and the ETL. No superuser, role, database, replication or RLS-bypass rights.
- reader (default finsight_api): the API. CONNECT, USAGE and SELECT on curated and ops only;
  sessions default to read-only.

Connection settings come from the standard PG* variables (the administrator). Role passwords come
from FINSIGHT_WRITER_PASSWORD and FINSIGHT_READER_PASSWORD. They are sent as SCRAM-SHA-256
verifiers computed here, so the plain text never reaches the server or its logs, and nothing is
printed. Re-running is safe and rotates the passwords to the values provided.
"""

import base64
import hashlib
import hmac
import os
import re
import secrets

import psycopg
from psycopg import sql

SCHEMAS = ("curated", "ops")
NAME = re.compile(r"^[a-z_][a-z0-9_]{0,62}$")
MIN_PASSWORD = 16
ITERATIONS = 4096
ROLE_ATTRIBUTES = sql.SQL(
    "LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT"
)


def scram_verifier(password: str, salt: bytes | None = None) -> str:
    """The SCRAM-SHA-256 verifier PostgreSQL stores (RFC 5802/7677), computed client-side."""
    salt = salt or secrets.token_bytes(16)
    salted = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, ITERATIONS)
    client_key = hmac.new(salted, b"Client Key", "sha256").digest()
    stored_key = hashlib.sha256(client_key).digest()
    server_key = hmac.new(salted, b"Server Key", "sha256").digest()
    b64 = base64.b64encode
    return (
        f"SCRAM-SHA-256${ITERATIONS}:{b64(salt).decode()}"
        f"${b64(stored_key).decode()}:{b64(server_key).decode()}"
    )


def _check(name: str, password: str, label: str) -> None:
    if not NAME.match(name):
        raise ValueError(f"{label} role name is not a plain lowercase identifier")
    if len(password) < MIN_PASSWORD or not password.isascii():
        raise ValueError(f"{label} password must be at least {MIN_PASSWORD} ASCII characters")


def _upsert_role(cursor, name: str, password: str) -> None:
    exists = cursor.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (name,)).fetchone()
    verb = sql.SQL("ALTER ROLE") if exists else sql.SQL("CREATE ROLE")
    cursor.execute(
        sql.SQL("{} {} {} PASSWORD {}").format(
            verb, sql.Identifier(name), ROLE_ATTRIBUTES, sql.Literal(scram_verifier(password))
        )
    )


def bootstrap(
    connection: psycopg.Connection,
    writer: str,
    writer_password: str,
    reader: str,
    reader_password: str,
) -> None:
    """Idempotently apply the role model to the connected database, in one transaction."""
    _check(writer, writer_password, "writer")
    _check(reader, reader_password, "reader")
    if writer == reader:
        raise ValueError("writer and reader must be different roles")
    database = connection.info.dbname
    w, r, db = sql.Identifier(writer), sql.Identifier(reader), sql.Identifier(database)
    with connection.transaction(), connection.cursor() as cursor:
        cursor.execute("SELECT pg_advisory_xact_lock(731000)")
        _upsert_role(cursor, writer, writer_password)
        _upsert_role(cursor, reader, reader_password)
        cursor.execute(sql.SQL("ALTER ROLE {} SET default_transaction_read_only = on").format(r))

        # The writer owns the database (and so CREATE on it and on the public schema); PUBLIC
        # keeps nothing, so other roles cannot connect, create temporary tables or create objects.
        cursor.execute(sql.SQL("ALTER DATABASE {} OWNER TO {}").format(db, w))
        cursor.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(db))
        cursor.execute(sql.SQL("REVOKE CREATE ON SCHEMA public FROM PUBLIC"))
        cursor.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(db, r))

        for name in SCHEMAS:
            s = sql.Identifier(name)
            cursor.execute(sql.SQL("CREATE SCHEMA IF NOT EXISTS {} AUTHORIZATION {}").format(s, w))
            cursor.execute(sql.SQL("ALTER SCHEMA {} OWNER TO {}").format(s, w))
            cursor.execute(sql.SQL("REVOKE ALL ON SCHEMA {} FROM PUBLIC").format(s))
            cursor.execute(sql.SQL("GRANT USAGE ON SCHEMA {} TO {}").format(s, r))
        # Objects created before this model (an existing database) move to the writer.
        owned = cursor.execute(
            """SELECT n.nspname, c.relname
                 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE c.relkind IN ('r', 'p')
                  AND (n.nspname = ANY(%s)
                       OR (n.nspname = 'public' AND c.relname = 'schema_migrations'))
                  AND pg_get_userbyid(c.relowner) <> %s""",
            (list(SCHEMAS), writer),
        ).fetchall()
        for schema, table in owned:
            cursor.execute(
                sql.SQL("ALTER TABLE {}.{} OWNER TO {}").format(
                    sql.Identifier(schema), sql.Identifier(table), w
                )
            )
        for name in SCHEMAS:
            s = sql.Identifier(name)
            cursor.execute(sql.SQL("GRANT SELECT ON ALL TABLES IN SCHEMA {} TO {}").format(s, r))
            cursor.execute(
                sql.SQL(
                    "ALTER DEFAULT PRIVILEGES FOR ROLE {} IN SCHEMA {} GRANT SELECT ON TABLES TO {}"
                ).format(w, s, r)
            )


def main() -> None:
    writer = os.environ.get("FINSIGHT_WRITER_ROLE", "finsight_app")
    reader = os.environ.get("FINSIGHT_READER_ROLE", "finsight_api")
    try:
        writer_password = os.environ["FINSIGHT_WRITER_PASSWORD"]
        reader_password = os.environ["FINSIGHT_READER_PASSWORD"]
    except KeyError as missing:
        raise SystemExit(f"{missing.args[0]} is not set") from None
    with psycopg.connect(connect_timeout=5) as connection:
        bootstrap(connection, writer, writer_password, reader, reader_password)
    print(f"Roles ready: writer {writer}, reader {reader} (passwords not shown).")


if __name__ == "__main__":
    main()

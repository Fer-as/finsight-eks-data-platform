"""Apply ordered SQL migrations atomically; reject edits to applied migrations."""

import hashlib
from pathlib import Path

import psycopg


def migrate(connection, directory: Path) -> None:
    with connection.transaction():
        connection.execute("SELECT pg_advisory_xact_lock(731001)")
        connection.execute("""CREATE TABLE IF NOT EXISTS public.schema_migrations (
            name text PRIMARY KEY, sha256 text NOT NULL,
            applied_at timestamptz NOT NULL DEFAULT now())""")
        for path in sorted(directory.glob("*.sql")):
            content = path.read_text(encoding="utf-8")
            digest = hashlib.sha256(content.encode()).hexdigest()
            existing = connection.execute(
                "SELECT sha256 FROM public.schema_migrations WHERE name = %s", (path.name,)
            ).fetchone()
            if existing:
                if existing[0] != digest:
                    raise ValueError(f"Applied migration changed: {path.name}")
                continue
            connection.execute(content)
            connection.execute(
                "INSERT INTO public.schema_migrations(name, sha256) VALUES (%s, %s)",
                (path.name, digest),
            )
            print(f"Applied {path.name}")


if __name__ == "__main__":
    with psycopg.connect(connect_timeout=5) as connection:
        migrate(connection, Path(__file__).resolve().parents[1] / "warehouse/migrations")

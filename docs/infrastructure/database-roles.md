# PostgreSQL roles

FinSight uses three PostgreSQL roles, each with only the rights its component needs.
[`scripts/bootstrap_roles.py`](../../scripts/bootstrap_roles.py) creates them, and the integration
tests in [`tests/integration/test_database_roles.py`](../../tests/integration/test_database_roles.py)
check them against a real PostgreSQL 17 server.

| Role | Used by | Can | Cannot |
|---|---|---|---|
| Administrator (`POSTGRES_USER`, default `finsight`) | `scripts/bootstrap_roles.py` and maintenance only | Everything (bootstrap superuser) | Not used by any application component |
| Writer (`finsight_app`) | Migrations, data generation and the ETL | Owns the database and the `curated` and `ops` schemas: creates tables, loads and truncates data | Create roles or databases, act as a superuser, replicate, bypass row-level security |
| Reader (`finsight_api`) | The API | Connect; `SELECT` on `curated` and `ops` tables, including tables the writer creates later | Write, truncate, run DDL, create temporary tables, read `schema_migrations`, change roles or grants, run server programs or read server files |

Further restrictions:
- `PUBLIC` has no `CONNECT` or `TEMPORARY` right on the database, and no `CREATE` on the `public`
  schema. Any other role is refused at connection.
- The reader's sessions default to read-only (`default_transaction_read_only = on`). This adds to its
  privileges rather than replacing them: the tests turn read-write on and confirm the writes are
  still refused.

## Passwords

- The bootstrap reads the writer and reader passwords from `FINSIGHT_WRITER_PASSWORD` and
  `FINSIGHT_READER_PASSWORD`. They must be at least 16 ASCII characters.
- It sends each password to the server as a SCRAM-SHA-256 verifier computed on the client, so the
  plain text never reaches the server or its logs. It prints nothing secret.
- Re-running it is safe, and rotates each password to the value provided.
- On an existing database, it moves the ownership of the existing FinSight tables to the writer.

## Where it runs

- **Docker Compose (local).** A one-shot `roles` service runs the bootstrap as the administrator after
  PostgreSQL is healthy. `migrate`, `generate` and `etl` connect as the writer, and the API as the
  reader. The local-only passwords are in `.env.example`.
- **CI.** The integration tests run in the Application pipeline's Python job against its PostgreSQL
  service. Each run creates a separate database and uniquely named roles, and drops them afterwards.
- **Kubernetes: not yet.** The FinSight chart still gives the init Job and the API the single
  `finsight-database` Secret. Moving them to the writer and reader needs
  `scripts/new-cluster-secrets.ps1` to create the extra credentials. That script is being changed
  separately, so this is a follow-up change. The recorded EKS deployment (16–20 October 2026) used
  the single role.

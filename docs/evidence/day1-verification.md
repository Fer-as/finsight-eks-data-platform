# Day 1 verification — 13 October 2026

Branch: `feat/day1-platform-foundation`. Local Docker Desktop Linux engine on Windows.
No AWS provisioning, cloud deployment, GitHub push or merge was performed.

## Executed checks

| Check | Actual result |
|---|---|
| Docker Compose configuration validation | Passed |
| `docker compose up --build -d --wait frontend` | Passed; PostgreSQL, API and frontend healthy |
| Migrations, synthetic generator and ETL startup jobs | Each exited 0 |
| Container Python unit + real PostgreSQL integration tests | **37 passed, 0 skipped, 0 failed** |
| Ruff checks and formatting in Python test container | Passed |
| Container React/Vitest tests | **6 passed, 0 failed** |
| Prettier frontend format check | Passed |
| Vite production build | Passed; 31 modules transformed |
| `scripts/verify.ps1` | Exit 0; tests/build and HTTP smoke checks passed |
| API readiness and frontend HTTP response | Passed |
| API analytics through Vite `/api` proxy | Passed; populated GBP report |
| Full-size ETL rerun and before/after summary comparison | Passed; unchanged totals, 10,000 transactions |
| Browser visual inspection / screenshot | Not executed: no connected browser available |

Host Python testing also passed 33 unit tests, with the four PostgreSQL integration
tests explicitly skipped there. All four subsequently ran successfully in Compose.

One non-failing dependency warning remains: Starlette's TestClient reports that its
httpx integration is deprecated. The pinned httpx version passed every test; no warning
filter was added. Image installation also emitted npm package-install-script and update
notices; both frontend startup and the production build succeeded.

## Dataset reconciliation

| Table | Source | Accepted | Rejected | Duplicates |
|---|---:|---:|---:|---:|
| departments | 3 | 3 | 0 | 0 |
| entries | 288 | 288 | 0 | 0 |
| budgets | 36 | 36 | 0 | 0 |
| transactions | 10,000 | 10,000 | 0 | 0 |

Source/config SHA-256:
`a8cf0e2496b918bf98b5cb61e2e2b0bc0b7ba3e818794a3ee83ba6f91c213ba4`

Verified annual report (2025, all departments):

| Measure | Observed result |
|---|---:|
| Revenue | £3,501,600.00 |
| Expenses | £2,392,450.00 |
| Operating profit | £1,109,150.00 |
| Profit margin | 31.68% |
| Expense budget | £2,400,000.00 |
| Favourable budget variance | £7,550.00 |
| Budget utilisation | 99.69% |
| Banking transaction volume (separate from revenue) | £51,374,221.39 |
| Transactions flagged for review | 2,628 |
| High indicators | 104 |

Tests exercise invalid records, timezone handling, exact pence, duplicate policy,
Parquet reconciliation, empty sources, atomic rollback, migration reruns, failed-run
audit status, filtering, pagination, API errors and UI loading/error/empty states.

## Issues found and resolved during implementation

- Docker engine was initially stopped; starting the existing Docker Desktop resolved it.
- Host Python was absent; a repository-local Python 3.12 runtime/venv enabled unit checks.
- Host sandbox prevented pytest's default temporary directory and Vite parent-directory
  resolution. Repository-local pytest temp storage and authorised execution resolved these.
- A UI test initially observed the loading state instead of waiting for the empty state;
  fixed the asynchronous assertion.
- An invalid empty CSS import caused the first build failure; removed it and verified
  the subsequent container build passed.

## Reproduce

Run the PowerShell commands in the repository README. `scripts/verify.ps1` returns a
non-zero exit if any test, build or smoke check fails. No EKS/HTTPS deployment evidence
is claimed by these local results. The detailed 135-point assessment rubric is still pending.

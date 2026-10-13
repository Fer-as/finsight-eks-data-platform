# EKS assessment tracker

Available points: **135**, as supplied by the project owner. Detailed rubric pending.
No category names, point allocations or earned points have been inferred below.

| Official category | Exact requirement | Available points | Planned artifact | Verification / evidence | Status |
|---|---|---|---|---|---|
| 1 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 2 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 3 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 4 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 5 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 6 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 7 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 8 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |
| 9 — awaiting rubric | TBD | TBD | TBD | TBD | Unmapped |

## Known deliverables to map when the rubric arrives

| Deliverable | Current state | Evidence to collect later |
|---|---|---|
| Reusable configurable Terraform / AWS EKS | Deferred | Module inputs, plan, deployed resources |
| NGINX ingress | Deferred; implementation support decision required | Controller health, routing |
| CertManager / Let's Encrypt | Deferred | Certificate Ready, HTTPS validation |
| ExternalDNS / Route 53 | Deferred | Controller reconciliation and DNS resolution |
| Two CI/CD pipelines, Checkov, Trivy and ECR | Deferred | Successful runs, scans, immutable image digests |
| ArgoCD | Deferred | Synced/Healthy application, change reconciliation |
| Prometheus / Grafana | Deferred | Targets, metrics and dashboards |
| Original AWS architecture documentation | Deferred | draw.io source, official AWS icons and boundaries |
| GitHub project board | Not created; no GitHub changes in Day 1 | Linked issues, acceptance checks and board |
| Public HTTPS at eks.<domain> or eks.labs.<domain> | Deferred | URL, DNS, certificate and app smoke test |
| Genuine ETL and ELT | ETL implemented; ELT reserved for Day 5 | Parquet/load reconciliation; dbt tests and lineage |

Day 1 evidence belongs in `docs/evidence/day1-verification.md`. Passing local tests is
not evidence of a successful EKS deployment. Update official rows only after receiving
the rubric; check category allocations sum to 135 before claiming coverage.

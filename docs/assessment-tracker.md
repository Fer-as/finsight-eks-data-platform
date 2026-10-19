# EKS assessment tracker

**135 available points** under the official rubric (G01-G09). No points are claimed or
awarded here. The criteria, evidence and verification for each category live in the
[master acceptance checklist](reviewer-acceptance-checklist.md); this tracker is the summary
and must agree with it.

Current status, 19 October 2026. Task board (public): https://github.com/users/Fer-as/projects/2

| ID | Official category | Points | Status | Evidence so far | Main gaps |
|---|---|---:|---|---|---|
| G01 | Board / Tickets | 10 | In progress | [Board](https://github.com/users/Fer-as/projects/2) (public) with 31 issues; retrospective #3; PRs #33 and #35 closed linked issues; board statuses being reconciled; [board snapshot](screenshots/board/github-project-board-current.png) of 17 October 2026 | Card statuses to reconcile; dated start and middle snapshots were not captured (G01.5) |
| G02 | Terraform for AWS Infrastructure | 15 | In progress | Modules validated; all three roots applied with S3 state and native locking; platform applied 16 October 2026 from a reviewed saved plan (68 resources); cluster, node group and five add-ons ACTIVE, two `m7i-flex.large` nodes Ready in two AZs ([evidence](screenshots/README.md#g02-terraform-and-eks)) | Line-by-line comparison of IAM policy statements with the documented scope (G02.3); network, nodes and security groups verified 18 October 2026 ([evidence](screenshots/eks/2026-10-18-network-iam-security-verification.md)) |
| G03 | NGINX Ingress Controller | 10 | Verified | F5 NGINX 5.6.3 (chart 2.7.3) via Argo CD behind an internet-facing NLB; `/` and `/api` routing, 301 redirect and 404 verified live | Assessor acceptance of F5 NGINX (R6.4, a reviewer item) |
| G04 | CertManager and ExternalDNS | 20 | In progress | cert-manager v1.21.2: staging then production certificate, Ready and trusted; ExternalDNS 1.23.0 manages the A, AAAA and TXT records; HTTPS live at eks.feras-dev.co.uk | Forced renewal (G04.3); record update and removal (G04.5) |
| G05 | Monitoring Setup | 15 | Verified | kube-prometheus-stack 91.8.2 via Argo CD; targets UP including the API and NGINX; default Grafana login rejected; live node, namespace, pod and service dashboards on 19 October 2026 after the Grafana memory fix (PR #57) | None recorded |
| G06 | Pipeline 1: Terraform | 10 | In progress | PR checks and OIDC plans (runs 38892240555, 38896532913); protected apply of a reviewed, encrypted saved plan (run 38901260888) | A deliberate failing run (G06.6) |
| G07 | Pipeline 2: Security, Docker and Kubernetes | 30 | In progress | Run 38761479287: tests, Checkov, matrix build, Trivy gate, OIDC ECR publish and GitOps PR #46; deployed digests match ECR | Failing-test and Trivy-blocked runs (G07.8) |
| G08 | ArgoCD GitOps | 15 | Verified | Eight Applications Synced and Healthy; automated sync from merges; self-heal demonstrated; initial admin Secret removed | None recorded |
| G09 | Architecture Design | 10 | In progress | Editable draw.io source (3 pages) and PNG exports; status banner updated 17 October 2026; embedded in the README | Assessor review |
| | **Total** | **135** | | | |

Additional project requirements:

| Requirement | Status / evidence still needed |
|---|---|
| Original financial application using synthetic data | Implemented and verified locally (F1-F3); running on EKS since 16 October 2026 |
| Genuine ETL and ELT | ETL runs as the in-cluster init Job loading PostgreSQL; ETL to S3 (F4) and ELT/dbt (F5) not started |
| HTTPS at eks.<domain> or eks.labs.<domain> | Live at https://eks.feras-dev.co.uk with a Let's Encrypt production certificate (G04.6) |
| EKS 1.36 STANDARD and managed add-ons | Applied 16 October 2026; five add-ons ACTIVE |
| Two private workers | Two `m7i-flex.large` nodes Ready, one in each of eu-west-2a and eu-west-2b (G02.7) |
| Secure retained storage/state | State, access-log and data buckets applied and verified 14 October 2026; bootstrap state migrated to S3 |
| Final demo video (R3.1-R3.3) | Not complete; no video is published in the repository |
| $50 budget awareness | Costs re-estimated for `m7i-flex.large`; budget alert is account-wide and not a cap; teardown pending (R12) |

Evidence: [evidence index](screenshots/README.md), [master checklist](reviewer-acceptance-checklist.md),
[Day 1](evidence/day1-verification.md),
[Day 2 local validation](evidence/day2-terraform-validation.md),
[Day 2 AWS bootstrap and foundation](evidence/day2-aws-bootstrap-foundation.md),
[Day 2 architecture](architecture/day2-aws.md),
[deployment readiness](infrastructure/deployment-readiness.md),
[infrastructure README](../infra/terraform/README.md).

Never mark a deployment, CI run, security scan or category complete based solely on planned
configuration.

## History: tracker as of 13 October 2026

Kept unchanged for the record; superseded by the table above. Category names here predate the
official rubric, and the add-on row is out of date.

| Category | Available points | Planned artifacts / evidence | Current status |
|---|---:|---|---|
| Board and tickets | 10 | GitHub project board, scoped issues, acceptance criteria, linked PRs | Not created; no GitHub changes authorized |
| Terraform infrastructure | 15 | Reusable modules, central config, secure remote state, reviewed plans and deployed verification | Local validation and nine tests pass; Checkov 130 passed / 0 failed / 15 documented exceptions; AWS verification pending |
| NGINX Ingress Controller | 10 | Maintained F5 NGINX chart, controller health, application routing | Planned; **assessor acceptance pending**; retired community ingress-nginx must not be deployed |
| CertManager and ExternalDNS | 20 | Certificate Ready, Let's Encrypt HTTPS, scoped Route 53 reconciliation/ownership | Deferred; existing zone referenced read-only in Terraform; no DNS records/controllers created |
| Monitoring | 15 | Prometheus targets, Grafana dashboards, operational evidence | Configuration implemented and validated locally; live evidence pending |
| Terraform CI/CD pipeline | 10 | Concise workflow, formatting/validation/security scans, protected OIDC plan and reviewed deployment process | Plan-only OIDC role implemented locally; workflow and apply-role design deferred |
| Application, security and Docker CI/CD pipeline | 30 | Tests, Checkov/Trivy results, image builds/digests, ECR publication and deployment evidence | Day 1 local application/tests exist; retained ECR and publisher role implemented locally; pipeline deferred |
| ArgoCD GitOps | 15 | Application/repository configuration, Synced/Healthy state, reconciliation evidence | Configuration implemented and validated locally; live evidence pending |
| Architecture documentation | 10 | Original draw.io source with official AWS icons/boundaries; architecture, costs and teardown docs | Original draw.io source and exported PNGs created; review pending |
| **Total available** | **135** | | **No scoring claim** |

Additional project requirements:

| Requirement | Status / evidence still needed |
|---|---|
| Original financial application using synthetic data | Day 1 implemented; see local evidence |
| Genuine ETL and ELT | ETL implemented locally; separate ELT/dbt path reserved for Day 5 |
| HTTPS at eks.<domain> or eks.labs.<domain> | Planned hostname only; DNS, certificate and public application test pending |
| EKS 1.36 STANDARD and managed add-ons | Terraform implemented; two regional add-on pins deliberately unset pending authorized compatibility checks |
| Two private m7i.large workers | Configurable in Terraform; actual readiness/AZ placement must be observed after deployment |
| Secure retained storage/state | Encryption/versioning/public block/retention and separate S3 access-log destination implemented; bootstrap/migration and delivery verification not performed |
| $50 budget awareness | Estimated costs and teardown runbook documented; alert is not a spending cap |

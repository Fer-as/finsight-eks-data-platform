# EKS assessment tracker

**135 available points** under the official rubric (G01-G09). No points are claimed or
awarded here. The criteria, evidence and verification for each category live in the
[master acceptance checklist](reviewer-acceptance-checklist.md); this tracker is the summary
and must agree with it.

Current status, 20 October 2026. Task board (public): https://github.com/users/Fer-as/projects/2

The EKS platform ran from 16 to 20 October 2026 and was torn down on 20 October 2026
([teardown record](evidence/2026-10-20-platform-teardown.md)). Runtime evidence below is from that recorded deployment.

| ID | Official category | Points | Status | Evidence so far | Main gaps |
|---|---|---:|---|---|---|
| G01 | Board / Tickets | 10 | In progress | [Board](https://github.com/users/Fer-as/projects/2) (public) with 31 issues; retrospective #3; PRs #33 and #35 closed linked issues; statuses reconciled 17 October 2026; 4 of 5 criteria verified, with board snapshots of [17 October](screenshots/board/github-project-board-current.png) (before reconciliation) and [20 October 2026](screenshots/board/github-project-board-2026-10-20.png) (after) | Dated start and middle snapshots were not captured (G01.5) |
| G02 | Terraform for AWS Infrastructure | 15 | Verified | Modules validated; all three roots applied with S3 state and native locking; platform applied 16 October 2026 from a reviewed saved plan (68 resources); cluster, node group and five add-ons ACTIVE, two `m7i-flex.large` nodes Ready in two AZs ([evidence](screenshots/README.md#g02-terraform-and-eks)) | None. IAM statements, boundary and trust reviewed 20 October 2026 ([IAM review](screenshots/eks/2026-10-20-iam-policy-review.md)); network, nodes and security groups verified 18 October 2026 ([evidence](screenshots/eks/2026-10-18-network-iam-security-verification.md)) |
| G03 | NGINX Ingress Controller | 10 | Verified | F5 NGINX 5.6.3 (chart 2.7.3) via Argo CD behind an internet-facing NLB; `/` and `/api` routing, 301 redirect and 404 verified on the live deployment, 16–18 October 2026 | Assessor acceptance of F5 NGINX (R6.4, a reviewer item) |
| G04 | CertManager and ExternalDNS | 20 | In progress | cert-manager v1.21.2: staging then production certificate, Ready and trusted; ExternalDNS 1.23.0 created the A, AAAA and TXT records; HTTPS served at `eks.feras-dev.co.uk` during the recorded deployment, 16–20 October 2026 | Forced renewal (G04.3); record update and removal (G04.5) |
| G05 | Monitoring Setup | 15 | Verified | kube-prometheus-stack 91.8.2 via Argo CD; targets UP including the API and NGINX; default Grafana login rejected; live node, namespace, pod and service dashboards on 19 October 2026 after the Grafana memory fix (PR #57) | None recorded |
| G06 | Pipeline 1: Terraform | 10 | Verified | PR checks and OIDC plans (runs 38892240555, 38896532913); protected apply of a reviewed, encrypted saved plan (run 38901260888); deliberate formatting failure, plan skipped (run 39387242933, [evidence](screenshots/cicd/2026-10-20-deliberate-failing-runs.md)) | None |
| G07 | Pipeline 2: Security, Docker and Kubernetes | 30 | Verified | Run 38761479287: tests, Checkov, matrix build, Trivy gate, OIDC ECR publish and GitOps PR #46; deployed digests match ECR; failing-test and Trivy-blocked runs skipped publishing (39387572606, 39387251772, [evidence](screenshots/cicd/2026-10-20-deliberate-failing-runs.md)) | None |
| G08 | ArgoCD GitOps | 15 | Verified | Eight Applications Synced and Healthy; automated sync from merges; self-heal demonstrated; initial admin Secret removed | None recorded |
| G09 | Architecture Design | 10 | Verified | Editable draw.io source (3 pages) and PNG exports, verified 19 October 2026 ([diagram verification](screenshots/architecture/2026-10-19-diagram-verification.md)); embedded in the README | Cosmetic: two overlapping labels on page 3 |
| | **Total** | **135** | | | |

Additional project requirements:

| Requirement | Status / evidence still needed |
|---|---|
| Original financial application using synthetic data | Implemented and verified locally (F1-F3); ran on EKS from 16 to 20 October 2026 |
| Genuine ETL and ELT | ETL ran as the in-cluster init Job loading PostgreSQL (16–20 October 2026); ETL to S3 (F4) and ELT/dbt (F5) not started |
| HTTPS at eks.<domain> or eks.labs.<domain> | Served at `eks.feras-dev.co.uk` with a Let's Encrypt production certificate during the recorded deployment, 16–20 October 2026 (G04.6); the hostname's records were removed at teardown |
| EKS 1.36 STANDARD and managed add-ons | Applied 16 October 2026 with five add-ons ACTIVE; removed with the platform on 20 October 2026 |
| Two private workers | Two `m7i-flex.large` nodes Ready, one in each of eu-west-2a and eu-west-2b, on 16 October 2026 (G02.7); removed on 20 October 2026 |
| Secure retained storage/state | State, access-log and data buckets applied and verified 14 October 2026; bootstrap state migrated to S3; all three buckets, the state versions and the ECR repositories confirmed present after the 20 October 2026 teardown (R9.6, [evidence](evidence/2026-10-20-platform-teardown.md)) |
| Final demo video (R3.1-R3.3) | Not complete; no video is published in the repository |
| $50 budget awareness | Costs re-estimated for `m7i-flex.large`; budget alert is account-wide and not a cap; platform torn down 20 October 2026 ([evidence](evidence/2026-10-20-platform-teardown.md)); actual cost awaits billing data (R12.4) |

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

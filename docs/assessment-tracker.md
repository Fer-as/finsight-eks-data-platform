# EKS assessment tracker

**135 available points** under the official rubric (G01-G09). No points are claimed or
awarded here. The criteria, evidence and verification for each category live in the
[master acceptance checklist](reviewer-acceptance-checklist.md); this tracker is the summary
and must agree with it.

Current status, 14 October 2026. Task board (public): https://github.com/users/Fer-as/projects/2

| ID | Official category | Points | Status | Evidence so far | Main gaps |
|---|---|---:|---|---|---|
| G01 | Board / Tickets | 10 | In progress | [Board](https://github.com/users/Fer-as/projects/2) (public) with 31 issues; retrospective #3 closed after verification; PRs [#33](https://github.com/Fer-as/finsight-eks-data-platform/pull/33) and [#35](https://github.com/Fer-as/finsight-eks-data-platform/pull/35) merged and closed #5 and #6 | Dated screenshots; continued use |
| G02 | Terraform for AWS Infrastructure | 15 | In progress | Modules validated (3/3 roots, 32/32 tests); bootstrap and foundation applied with S3 state and native locking; DNS roles merged (#6); security groups defined and tested (#7, PR [#36](https://github.com/Fer-as/finsight-eks-data-platform/pull/36); runtime check in #30); load balancer controller role defined and tested locally (#34); Checkov 181 passed / 0 failed / 16 documented exceptions (includes test fixtures) | Platform (VPC, EKS, nodes) not applied; CI apply role (#8) |
| G03 | NGINX Ingress Controller | 10 | Not started | F5 NGINX chosen (assessor acceptance pending); retired community ingress-nginx and Traefik not used | Install, Ingress routing, tests |
| G04 | CertManager and ExternalDNS | 20 | In progress | Public hosted zone exists; ExternalDNS and cert-manager Pod Identity roles in Terraform (not applied, #6) | Controllers, issuers, IAM, HTTPS, renewal and DNS lifecycle tests |
| G05 | Monitoring Setup | 15 | Not started | None | Prometheus, Grafana, ingress and application metrics |
| G06 | Pipeline 1: Terraform | 10 | In progress | Local validation/scan scripts; plan-only OIDC role applied and verified; apply role, scoped apply policies and mandatory workload boundary coded and tested locally (#8, Option A; not applied) | Foundation apply, GitHub environments, workflow, failure handling, run evidence |
| G07 | Pipeline 2: Security, Docker and Kubernetes | 30 | In progress | Local tests (37 Python, 6 frontend); ECR repositories and image role applied | Workflow, production frontend and ETL images, Trivy, ECR push, GitOps deploy, failing-run evidence |
| G08 | ArgoCD GitOps | 15 | Not started | None | Argo CD, applications, sync and drift evidence |
| G09 | Architecture Design | 10 | Not started | Mermaid diagrams only | Original draw.io diagram and export |
| | **Total** | **135** | | | |

Additional project requirements:

| Requirement | Status / evidence still needed |
|---|---|
| Original financial application using synthetic data | Day 1 implemented and verified locally (checklist F1-F3) |
| Genuine ETL and ELT | ETL verified locally; ELT/dbt not started (F5) |
| HTTPS at eks.<domain> or eks.labs.<domain> | Hostname configured; DNS, certificate and HTTPS test pending (G04.6) |
| EKS 1.36 STANDARD and managed add-ons | All five add-on pins set to the verified London defaults (14 October 2026); platform not applied |
| Two private m7i.large workers | In Terraform; readiness and AZ placement to be observed after deployment (G02.7) |
| Secure retained storage/state | State, access-log and data buckets applied and verified 14 October 2026; bootstrap state migrated to S3 |
| $50 budget awareness | Costs re-estimated; budget alert is account-wide and not a cap; teardown runbook documented |

Evidence: [master checklist](reviewer-acceptance-checklist.md),
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
| Monitoring | 15 | Prometheus targets, Grafana dashboards, operational evidence | Deferred |
| Terraform CI/CD pipeline | 10 | Concise workflow, formatting/validation/security scans, protected OIDC plan and reviewed deployment process | Plan-only OIDC role implemented locally; workflow and apply-role design deferred |
| Application, security and Docker CI/CD pipeline | 30 | Tests, Checkov/Trivy results, image builds/digests, ECR publication and deployment evidence | Day 1 local application/tests exist; retained ECR and publisher role implemented locally; pipeline deferred |
| ArgoCD GitOps | 15 | Application/repository configuration, Synced/Healthy state, reconciliation evidence | Deferred |
| Architecture documentation | 10 | Original draw.io source with official AWS icons/boundaries; architecture, costs and teardown docs | Day 1/2 Markdown/Mermaid docs exist; original draw.io and deployed evidence pending |
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

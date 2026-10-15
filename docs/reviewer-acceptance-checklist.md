# FinSight master acceptance checklist

This is FinSight's single acceptance checklist. It combines three sources:

1. The official EKS assignment and its 135-point evaluation rubric (authoritative; parts 1-3).
2. The reviewer-quality criteria R1-R13, derived from a review of another student's EKS
   project (part 4). They are kept with their original IDs, statuses and evidence fields.
   The review transcript is not stored in this repository; R1-R13 follow the project owner's
   summary of it, dated 14 October 2026.
3. FinSight's own application and data-engineering goals (part 5), plus the existing
   [assessment tracker](assessment-tracker.md), architecture and infrastructure records.

Last updated 14 October 2026. No assessment points have been awarded; this document tracks
evidence, not grades.

## 1. Project definition and grading rules

FinSight is an original financial analytics platform on synthetic GBP data: a FastAPI service,
a React dashboard, a Pandas ETL producing Parquet and loading PostgreSQL, and a planned dbt ELT
path. It is deployed to Amazon EKS 1.36 in `eu-west-2` with Terraform, GitHub Actions, Argo CD,
F5 NGINX Ingress Controller, cert-manager, ExternalDNS, Prometheus and Grafana, at
`https://eks.<domain>` or `https://eks.labs.<domain>`.

Rules:

- The official scorecard has nine categories, G01-G09, totalling exactly **135 points**. The
  names and weights below are the assessor's and must not be changed.
- None of G01-G09 may be marked Not applicable. Only optional reviewer suggestions (R13) may be.
- Category status is **Not started**, **In progress** or **Verified**. A category is Verified
  only when every criterion in it is Verified.
- A criterion is Verified only when its evidence exists at the stated location and its
  verification method has been carried out and dated. Configuration, plans, local-only runs
  and intent are not runtime evidence.
- Agents and the owner never award points. A readiness estimate, if given, is labelled as such
  and is not a grade.
- A running EKS cluster by itself is not a completed project.
- Recorded evidence from a past deployment must be labelled as recorded, with its date, and
  never presented as a currently live system.

### Assignment requirements and where they are covered

| Official requirement | Criteria |
|---|---|
| Cloud-native application deployed on Amazon EKS | G02.7, G07.6, G08.2, F4 |
| VPC with private subnets for workers and public subnets for public load balancing | G02.1, G02.2, G03.2 |
| Restricted IAM roles and security groups | G02.3, G02.4, R6.6 |
| Reusable Terraform modules and remote state | G02.5, G02.6, R9.1, R9.2 |
| NGINX installed with Helm or Kubernetes manifests | G03.1 |
| Ingress routing to the correct Kubernetes services | G03.3, G03.4 |
| cert-manager issuing TLS certificates automatically | G04.1-G04.3 |
| ExternalDNS updating Route 53 from Kubernetes resources | G04.4, G04.5 |
| Application on the required HTTPS hostname | G04.6, R4.7 |
| Pipeline 1: Terraform automation, validation, state and failures | G06.1-G06.7 |
| Pipeline 2: Checkov, Docker builds, ECR, Trivy and EKS deployment | G07.1-G07.8 |
| Argo CD continuously reconciling the cluster against Git | G08.1-G08.5 |
| Prometheus and Grafana with infrastructure and application metrics | G05.1-G05.5 |
| Architecture diagram showing all components and traffic flows | G09.1-G09.5, R2.1-R2.4 |

**Remote state locking.** The assignment cites S3 with DynamoDB as an example. FinSight uses
S3 with Terraform's native lock file (`use_lockfile = true`), supported since Terraform 1.10
and the current HashiCorp recommendation; DynamoDB-based locking is deprecated in the S3
backend. A lock object `<key>.tflock` is created with a conditional write and removed on
release, giving the same mutual exclusion without a DynamoDB table. This was observed working
for the bootstrap and foundation roots on 14 October 2026 (G02.6).

## 2. Official 135-point scorecard

| ID | Category | Points | Status | Readiness summary (not a grade) | Reviewer IDs |
|---|---|---:|---|---|---|
| G01 | Board / Tickets | 10 | In progress | Public board with 31 issues; PRs #33 and #35 merged and closed #5 and #6; screenshots pending | R11.2 |
| G02 | Terraform for AWS Infrastructure | 15 | In progress | Modules, remote state and two of three roots applied; platform (VPC, EKS, nodes) not applied; security groups defined and tested (#7); load balancer controller role defined and tested locally (#34) | R9.1-R9.6, R6.6 |
| G03 | NGINX Ingress Controller | 10 | In progress | F5 NGINX 5.6.3 / chart 2.7.3 values, Argo CD Application and FinSight Ingress chart implemented and validated locally; not deployed | R6.4 |
| G04 | CertManager and ExternalDNS | 20 | In progress | Pod Identity roles in Terraform; cert-manager, ClusterIssuers, ExternalDNS and Ingress TLS implemented and validated locally; not deployed | R6.3-R6.5, R4.7 |
| G05 | Monitoring Setup | 15 | Not started | Nothing installed | R4.3, R4.4 |
| G06 | Pipeline 1: Terraform | 10 | In progress | Local validation scripts; plan-only and apply roles, scoped policies and workload boundary applied (#8); apply environment protected; pull-request checks and plan workflow merged (#10, first run passed, plan skipped by the compatibility gate); approval-gated apply written and synthetically tested (#11, not run) | R7.3, R7.5-R7.10, R9.2 |
| G07 | Pipeline 2: Security, Docker and Kubernetes | 30 | In progress | Implemented: production api/etl/frontend images and `.github/workflows/app.yml` (tests, Checkov, matrix build, Trivy gate, OIDC ECR publish, GitOps pull request). Locally tested on Linux. Not yet run on GitHub; no ECR/Kubernetes evidence | R7.1-R7.9, R4.5, R5.1-R5.7, R8.2, R10.4 |
| G08 | ArgoCD GitOps | 15 | In progress | Argo CD 3.5.4 (chart 10.9.7) values, app-of-apps root with sync waves and injected account values, Applications for the load balancer controller, cert-manager, ClusterIssuers, NGINX, ExternalDNS and FinSight (values.yaml + image-tags.yaml); 27 offline tests pass; not installed | R8.1-R8.5, R4.2 |
| G09 | Architecture Design | 10 | Not started | Mermaid diagrams only; the draw.io deliverable does not exist | R2.1-R2.4, R1.2 |
| | **Total** | **135** | | | |

## 3. Graded acceptance criteria

Every category has a record table and criteria rows. Tickets are on the
[FinSight — EKS & Data Platform board](https://github.com/users/Fer-as/projects/2) (created 14 October 2026).

### G01 Board / Tickets (10 points)

| Field | Record |
|---|---|
| Status | In progress |
| Existing implementation | [Board](https://github.com/users/Fer-as/projects/2) with Backlog, Todo, In Progress, Review, Done and a Priority field; Board and Table views; 30 issues ([#3](https://github.com/Fer-as/finsight-eks-data-platform/issues/3)-[#32](https://github.com/Fer-as/finsight-eks-data-platform/issues/32)) labelled by category and priority; linked to this repository |
| Missing | Remaining pull requests linked to issues; dated board screenshots; continued use as work progresses |
| Runtime / repository evidence | Board screenshot over time; issues and PRs on GitHub |
| Objective verification | Open the board: every remaining graded criterion maps to an issue; merged PRs close issues |
| Reviewer IDs | R11.2 |
| Ticket | [#4](https://github.com/Fer-as/finsight-eks-data-platform/issues/4) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G01.1 | A GitHub Projects board with columns Backlog, Todo, In Progress, Review and Done | In progress (board and statuses exist and the board is public, verified 14 October 2026 by anonymous HTTP 200; still to be shown in active use) | Board | GitHub Projects; `docs/screenshots/board/` | Columns exist and are used |
| G01.2 | One issue per remaining deliverable, each with acceptance criteria that cite this checklist's IDs | Verified (14 October 2026: script check found every non-Verified G, R and F criterion cited by an open issue) | Issues | GitHub issues | Every G criterion not yet Verified is covered by an open issue |
| G01.3 | Pull requests link their issues (`Closes #n`) and move cards to Done on merge | Verified (14 October 2026: [#33](https://github.com/Fer-as/finsight-eks-data-platform/pull/33) closed #5 and [#35](https://github.com/Fer-as/finsight-eks-data-platform/pull/35) closed #6 on merge; cards moved to Done by hand because the board's close automation is not configured) | PRs | GitHub | Merged PRs show linked, closed issues |
| G01.4 | Honest history: work done before the board existed is recorded in one issue labelled `retrospective`, not backdated tickets | Verified (14 October 2026: [#3](https://github.com/Fer-as/finsight-eks-data-platform/issues/3), created and closed after verifying #1, #2 and the S3 state objects) | Retrospective issue | GitHub issues | Issue creation dates are after 14 October 2026 and say so |
| G01.5 | Dated board screenshots at the start, middle and end of the remaining work | Not started | Screenshots | `docs/screenshots/board/` | Cards visibly progress between screenshots |

### G02 Terraform for AWS Infrastructure (15 points)

| Field | Record |
|---|---|
| Status | In progress |
| Existing implementation | `infra/terraform/` modules network, eks, pod-role, github-oidc, ecr, retained-bucket, access-log-bucket, config; roots bootstrap (applied), foundation (applied), platform (validated, not planned) |
| Missing | Platform plan and apply; post-deployment security-group and controller evidence; CI apply role (#8) |
| Runtime / repository evidence | Plan and apply summaries, `aws eks describe-*`, `kubectl get nodes`, Checkov results |
| Objective verification | Plans match expected counts; resources exist with the stated settings; teardown leaves retained resources only |
| Reviewer IDs | R9.1-R9.6, R6.6, R12.1-R12.3 |
| Ticket | [#5](https://github.com/Fer-as/finsight-eks-data-platform/issues/5), [#6](https://github.com/Fer-as/finsight-eks-data-platform/issues/6), [#7](https://github.com/Fer-as/finsight-eks-data-platform/issues/7), [#8](https://github.com/Fer-as/finsight-eks-data-platform/issues/8), [#9](https://github.com/Fer-as/finsight-eks-data-platform/issues/9); deployment [#30](https://github.com/Fer-as/finsight-eks-data-platform/issues/30); retrospective [#3](https://github.com/Fer-as/finsight-eks-data-platform/issues/3); load balancer controller [#34](https://github.com/Fer-as/finsight-eks-data-platform/issues/34) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G02.1 | VPC with two public and two private subnets across two AZs, internet gateway, one NAT gateway, private routes via NAT, S3 gateway endpoint, flow logs | In progress (code and validation only) | Platform plan and apply; `describe-subnets` / `describe-route-tables` | `infra/terraform/modules/network`, `docs/evidence/` | Public subnets route to the IGW; private subnets route to the NAT; `map_public_ip_on_launch` false |
| G02.2 | EKS 1.36 STANDARD cluster with the managed node group in private subnets only, IMDSv2 required, encrypted root volumes | In progress (code only) | Apply output; `describe-cluster`, `describe-nodegroup`; node ENIs without public IPs | `infra/terraform/modules/eks`, `docs/evidence/` | Nodes Ready; no node has a public IP |
| G02.3 | IAM roles restricted: cluster, node, Pod Identity (CNI, EBS CSI, ETL, ExternalDNS), GitHub plan and image roles, administrator role; no wildcard admin | In progress (GitHub roles applied and verified 14 October 2026; others code only. cert-manager and AWS Load Balancer Controller roles added in code with offline trust and scope tests; independent review 14 October: 32 tests passed, Checkov 181 passed / 0 failed / 16 existing skips (test fixtures included), [#34](https://github.com/Fer-as/finsight-eks-data-platform/issues/34), `docs/infrastructure/load-balancer-controller.md`) | IAM policy listings | `infra/terraform/modules/*`, `docs/evidence/` | Each role's policies match the documented scope |
| G02.4 | Security groups: cluster and node groups defined in Terraform, or the EKS-managed cluster group documented with its actual rules; the VPC default group has no rules; API endpoint restricted to explicit CIDRs | In progress (14 October 2026: EKS-managed cluster group documented; Terraform-owned public NLB group and NLB-to-ingress rules added with offline tests ([#7](https://github.com/Fer-as/finsight-eks-data-platform/issues/7), PR [#36](https://github.com/Fer-as/finsight-eks-data-platform/pull/36), `docs/infrastructure/network-security.md`); not applied; post-deployment `describe-security-groups` evidence tracked in [#30](https://github.com/Fer-as/finsight-eks-data-platform/issues/30)) | Terraform or design note; `describe-security-groups` after apply | `infra/terraform/modules/network`, `modules/eks`, `docs/infrastructure/` | Every inbound rule has a named source and reason; no 0.0.0.0/0 except the public load balancer listener ports |
| G02.5 | Reusable modules with typed inputs, validations, outputs and READMEs (same as R9.1) | Verified | Module tree; validation run | `infra/terraform/modules/` | `scripts/validate-terraform.ps1` passed on 14 October 2026 (3/3 roots, 9/9 tests) |
| G02.6 | Remote state in S3 with native locking, encryption, versioning and a separate key per root | In progress (bootstrap and foundation verified 14 October 2026; platform pending) | Backend configuration; S3 object listing; lock create/release observed | `infra/terraform/*/backend.tf`, `docs/evidence/` | All three keys present in the state bucket; a concurrent plan is refused while locked |
| G02.7 | Platform applied and verified: cluster and node group ACTIVE, five add-ons ACTIVE, two nodes Ready in both AZs | Not started | Command output summary and screenshot | `docs/evidence/`, `docs/screenshots/eks/` | Runbook section 5 checks pass |

### G03 NGINX Ingress Controller (10 points)

| Field | Record |
|---|---|
| Status | In progress (local implementation; no live evidence) |
| Existing implementation | Implemented locally (not deployed): F5 NGINX Ingress Controller 5.6.3 / chart 2.7.3 values and Argo CD Application (`gitops/platform/nginx-ingress`), FinSight chart with Services and host/path Ingress (`gitops/apps/finsight`); helm lint/template and kubeconform (Kubernetes 1.36) pass; see `docs/infrastructure/ingress.md` |
| Missing | Live deployment and evidence (controller pods, NLB in public subnets, curl results), production frontend image (R5.7), Argo CD (G05), TLS redirect after G04 |
| Runtime / repository evidence | Controller pods, LoadBalancer service, Ingress objects, `curl` results |
| Objective verification | Requests reach the correct services by host and path; wrong host or path is rejected |
| Reviewer IDs | R6.4, R4.7 |
| Ticket | [#20](https://github.com/Fer-as/finsight-eks-data-platform/issues/20), [#34](https://github.com/Fer-as/finsight-eks-data-platform/issues/34) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G03.1 | F5 NGINX Ingress Controller installed from its official Helm chart at a pinned version supporting Kubernetes 1.36, managed by Argo CD | In progress (pinned chart 2.7.3 / controller 5.6.3, values and Argo CD Application written and validated locally; Argo CD not installed; not deployed) | Helm values and Argo CD Application | GitOps directory | `kubectl get pods -n <nginx ns>` Running; chart version equals the pin |
| G03.2 | Controller exposed through a load balancer in the public subnets while workloads stay on private nodes | In progress (Service uses loadBalancerClass service.k8s.aws/nlb, internet-facing, IP targets, Terraform security group; pods on private nodes; not deployed) | Service and load balancer description | `docs/evidence/` | Load balancer subnets are the public ones |
| G03.3 | Ingress routes the hostname to the frontend Service and `/api` to the API Service | In progress (Ingress: eks.feras-dev.co.uk, / and /assets to frontend, /api to API; Services in the FinSight chart; needs production frontend image and deployment) | Ingress manifests; `curl` output | GitOps directory, `docs/evidence/` | `curl https://<host>/` returns the app; `/api/health` returns the API response |
| G03.4 | Negative routing: unknown host or path gets a 404 from NGINX, and HTTP redirects to HTTPS | In progress (only /, /assets and /api routed, so other paths and hosts get the NGINX 404; HTTPS redirect follows once TLS is enabled in G04; no curl evidence yet) | `curl` output | `docs/evidence/` | Status codes recorded |

### G04 CertManager and ExternalDNS (20 points)

Certificate issuance, renewal, DNS management and the final HTTPS result are tested separately.

| Field | Record |
|---|---|
| Status | In progress |
| Existing implementation | Public hosted zone; Terraform Pod Identity roles for cert-manager and ExternalDNS (name-scoped Route 53 policies, tested). Implemented locally, not deployed: cert-manager v1.21.2 values + Argo CD Application, staging/production DNS-01 ClusterIssuers chart, ExternalDNS 1.23.0 (v0.23.0) values + Argo CD Application, Ingress TLS switch; helm lint/template, kubeconform (Kubernetes 1.36) and record-name/IAM checks pass; see `docs/infrastructure/dns-and-certificates.md` |
| Missing | Live deployment and evidence (pods, DNS-01 challenges, Ready certificate, renewal, Route 53 records, HTTPS); Argo CD (G05); decision on ExternalDNS `policy: sync` for the removal test (default upsert-only) |
| Runtime / repository evidence | Certificate and Order status, Route 53 record listing, renewal output, `curl -v` |
| Objective verification | Each of G04.2-G04.6 shown independently |
| Reviewer IDs | R6.3, R6.4, R6.5, R4.7, R3.1 |
| Ticket | [#6](https://github.com/Fer-as/finsight-eks-data-platform/issues/6), [#21](https://github.com/Fer-as/finsight-eks-data-platform/issues/21), [#22](https://github.com/Fer-as/finsight-eks-data-platform/issues/22) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G04.1 | cert-manager installed (pinned chart, via Argo CD) with Let's Encrypt staging and production ClusterIssuers; staging tested first | In progress (cert-manager v1.21.2 values and Argo CD Application; staging and production DNS-01 ClusterIssuers; validated locally; not deployed; staging first) | Manifests; issuer status | GitOps directory | Both issuers Ready |
| G04.2 | Certificate for the hostname issued automatically from the Ingress or Certificate resource by the production issuer | In progress (Ingress TLS switch: secret `finsight-tls`, `cert-manager.io/cluster-issuer`; production issuer selected by value; needs live issuance) | `kubectl get certificate`; certificate details | `docs/evidence/` | Ready=True; issuer is Let's Encrypt; SAN equals the hostname |
| G04.3 | Automatic renewal configured and demonstrated | In progress (`cert-manager.io/renew-before: 720h` on the Ingress; forced-renewal demonstration needs a live certificate) | `renewBefore` setting; forced renewal output showing a new serial | GitOps directory, `docs/evidence/` | Serial before and after differ; the secret updated without manual edits |
| G04.4 | ExternalDNS installed with a Pod Identity role allowed to change only the one hosted zone, using a TXT ownership registry | In progress (role, zone- and name-scoped policy and association in Terraform with unit tests, [#6](https://github.com/Fer-as/finsight-eks-data-platform/issues/6); not applied; controller not installed; ExternalDNS values/Application written with matching service account, zone-id and domain filters, TXT registry; record names verified against the IAM policy; not deployed) | Helm values; Terraform role; IAM policy | GitOps directory, `infra/terraform/` | Policy names the single zone; controller logs show the zone filter |
| G04.5 | DNS records managed dynamically: creating the Ingress creates the A/alias record; changing or removing it updates or removes the record | In progress (ExternalDNS 1.23.0 / v0.23.0 on Ingress status, TXT owner `finsight-dev`; default policy upsert-only creates/updates but does not delete, so the removal test needs `policy: sync`; not deployed) | Route 53 listings before and after | `docs/evidence/` | Records follow the Ingress; ownership TXT present |
| G04.6 | Working HTTPS at `https://eks.<domain>` or `https://eks.labs.<domain>` | Not started (live only: needs the platform, NGINX, the production image and a production certificate) | `curl -v` output and browser screenshot | `docs/evidence/`, `docs/screenshots/app/` | Valid chain, no warnings, app loads |

### G05 Monitoring Setup (15 points)

| Field | Record |
|---|---|
| Status | Not started |
| Existing implementation | None |
| Missing | kube-prometheus-stack (or equivalent), NGINX metrics scraping, application metrics, dashboards |
| Runtime / repository evidence | Prometheus targets, Grafana dashboards with live data, sizing note |
| Objective verification | Each metric family is visible with non-empty, current data |
| Reviewer IDs | R4.3, R4.4 |
| Ticket | [#25](https://github.com/Fer-as/finsight-eks-data-platform/issues/25) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G05.1 | Prometheus and Grafana installed with node-exporter and kube-state-metrics, pinned chart, via Argo CD; resource requests sized for two m7i.large nodes | Not started | Helm values; pod list | GitOps directory | All monitoring pods Running; nodes not over-committed |
| G05.2 | Node, pod, namespace and service metrics, including CPU and memory, shown in Grafana with real data | Not started | Dashboard screenshots with timestamps | `docs/screenshots/monitoring/` | Panels show non-empty series within the deployment window |
| G05.3 | Ingress metrics: NGINX controller metrics scraped (requests, status codes, latency) and shown on a dashboard | Not started | Target and dashboard screenshots | Same | Generated traffic visibly changes the panels |
| G05.4 | Application metrics from FinSight (API request metrics, or at minimum per-service ingress metrics) | Not started | Metrics endpoint or ingress breakdown; dashboard | `apps/api`, GitOps directory, screenshots | Calling the API changes the panel |
| G05.5 | Grafana access secured: no default admin password, not publicly exposed without authentication | Not started | Values and access note | GitOps directory, `docs/` | Login with defaults fails |

### G06 Pipeline 1: Terraform (10 points)

| Field | Record |
|---|---|
| Status | In progress |
| Existing implementation | `scripts/validate-terraform.ps1` and `scan-terraform.ps1`; `.github/workflows/terraform.yml` (#10, not yet run); applied roles `finsight-dev-github-infra-plan` (plan-only) and `finsight-dev-github-infra-apply` (#8); protected `dev-infrastructure-apply` |
| Missing | Workflow; an apply role used only behind a protected GitHub environment with required reviewers; plan/apply separation; failure handling |
| Runtime / repository evidence | Workflow file; successful and failing runs; environment protection settings |
| Objective verification | A pull request gets checks and a plan; apply waits for a reviewer; a bad change fails |
| Reviewer IDs | R7.3, R7.5-R7.10, R9.2 |
| Ticket | [#8](https://github.com/Fer-as/finsight-eks-data-platform/issues/8), [#10](https://github.com/Fer-as/finsight-eks-data-platform/issues/10), [#11](https://github.com/Fer-as/finsight-eks-data-platform/issues/11) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G06.1 | On pull requests: `terraform fmt -check`, `validate`, `terraform test` and Checkov for all roots | In progress ([#10](https://github.com/Fer-as/finsight-eks-data-platform/issues/10): `checks` job in `.github/workflows/terraform.yml` runs `scripts/validate-terraform.ps1`; validated locally and on Linux; no run yet) | Workflow and run | `.github/workflows/` | A formatting error fails the run |
| G06.2 | Plan runs with the plan-only OIDC role against remote state with locking, and its summary is posted to the run | In progress (#10: `plan` job written; needs the `dev-infrastructure` environment and `eks.compatibility_verified` before a real plan; no run yet) | Run with plan summary | `.github/workflows/`, `docs/screenshots/cicd/` | Plan shown; the role cannot write resources |
| G06.3 | Controlled deployment: apply runs only from the reviewed saved plan, through a protected environment with required reviewers, using a separate least-privilege apply role | In progress (apply role, scoped policies and boundary applied (#8); `dev-infrastructure-apply` protected; [#11](https://github.com/Fer-as/finsight-eks-data-platform/issues/11) `terraform-apply.yml` written: plan role saves an age-encrypted plan, apply role only after approval, executes the exact decrypted plan after commit/run/backend/config/lock/version/digest checks; reviewer decrypts an identity-headed review copy locally; independently reviewed; security regression tests 59/59 in `scripts/ci/tests` (run by the PR checks job); keys and environments configured; no apply run yet) | Workflow, environment protection, apply role | `.github/workflows/`, `infra/terraform/modules/github-oidc` | The apply job pauses for approval; the plan role alone cannot apply |
| G06.4 | Costly or destructive actions (platform apply, any destroy or replacement) require explicit manual approval and are never automatic | In progress (#11: manual dispatch only; deletes/replacements/forgets/unrecognised actions refused without `allow_destroy`, then reviewer approval; VPC and EKS cluster create/replace/delete/forget and imports always human-run; tested synthetically; no run yet) | Workflow conditions | `.github/workflows/` | A plan containing deletes is blocked without approval |
| G06.5 | Error handling: fail fast, a per-root concurrency group, no automatic force-unlock, clear failure summaries | In progress (shared `terraform-state-dev-platform` group across PR plans and apply, never cancelled; 5-minute lock timeout; no force-unlock; failure summaries; no run yet) | Workflow | `.github/workflows/` | Two concurrent runs serialise; a lock conflict fails cleanly |
| G06.6 | Successful and failing runs recorded | In progress (#10 PR run 38573056287 passed; apply runs pending; deliberate refusals planned as failing-run evidence) | Run screenshots or links | `docs/screenshots/cicd/` | One passing and one deliberately failing run |
| G06.7 | No state or secrets in artifacts or logs; plan artifacts short-lived and access-restricted | In progress (#10: plan text kept out of public logs, private values masked, value-free summary, no plan artifact; no run yet) | Workflow settings | `.github/workflows/` | Review artifacts and logs |

### G07 Pipeline 2: Security, Docker and Kubernetes (30 points)

Deployment to EKS is done through Git: the pipeline publishes images and updates the GitOps
manifests, and Argo CD applies them (G08). There is no second, direct `kubectl` deployment path.

| Field | Record |
|---|---|
| Status | In progress |
| Existing implementation | Local tests (Day 1: 37 Python and 6 frontend passed), API Dockerfile with non-root user, frontend development Dockerfile, ECR repositories and image publisher role (applied 14 October 2026), local Checkov script |
| Missing | GitHub runs (green and failing), dev-images environment + IMAGE_PUBLISHING_ENABLED, Actions permission to open pull requests, ECR digests, Argo CD rollout evidence |
| Runtime / repository evidence | Workflow runs, image digests in ECR, Trivy and Checkov reports, manifest-update commits |
| Objective verification | A commit produces scanned images in ECR and a deployed change; a vulnerable or failing change is blocked |
| Reviewer IDs | R7.1, R7.2, R7.4-R7.9, R4.5, R5.1-R5.7, R8.2, R8.3, R10.4 |
| Ticket | [#12](https://github.com/Fer-as/finsight-eks-data-platform/issues/12), [#13](https://github.com/Fer-as/finsight-eks-data-platform/issues/13), [#14](https://github.com/Fer-as/finsight-eks-data-platform/issues/14), [#15](https://github.com/Fer-as/finsight-eks-data-platform/issues/15), [#17](https://github.com/Fer-as/finsight-eks-data-platform/issues/17), [#24](https://github.com/Fer-as/finsight-eks-data-platform/issues/24) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G07.1 | Checkov runs against Terraform (and Kubernetes manifests) in the pipeline and fails on new findings | In progress (app.yml `checkov` job scans Terraform, Dockerfiles and rendered FinSight/ClusterIssuer manifests and fails on findings; all exit 0 locally; Kubernetes skips documented on resources; not yet run on GitHub) | Workflow and report | `.github/workflows/` | An insecure test change fails |
| G07.2 | Application tests run: pytest (unit and PostgreSQL integration) and Vitest | In progress (app.yml `python` job: ruff + pytest with PostgreSQL service (37 passed locally on Linux, integration included); `frontend` job: Prettier, Vitest 6/6, build; not yet run on GitHub) | Workflow and run | `.github/workflows/` | A failing test fails the run |
| G07.3 | Production Docker images built for api, etl and frontend with one matrix job | In progress (one `images` matrix job builds api, etl and frontend production targets; built locally; not yet run on GitHub) | Dockerfiles and workflow | `apps/*/Dockerfile`, `.github/workflows/` | Three images built from one job definition |
| G07.4 | Trivy scans each image and blocks publishing on fixable HIGH/CRITICAL findings | In progress (Trivy 0.75.0 gate fails on fixable HIGH/CRITICAL; unfixed findings listed in the job summary; local gate passes for all three images (api/etl 44 unfixed Debian findings, frontend 0); not yet run on GitHub) | Workflow and results | `.github/workflows/`, `docs/evidence/` | A known-vulnerable base image fails the job |
| G07.5 | Images pushed to ECR via the OIDC image role, tagged with the commit SHA | In progress (`publish` job: main only, environment dev-images, OIDC image role, pushes the scanned artifacts tagged with the commit SHA, never latest; blocked until dev-images and IMAGE_PUBLISHING_ENABLED are configured; no image pushed yet) | ECR image list | `docs/evidence/` | Tag equals the commit; no `latest` |
| G07.6 | Deployment to EKS: the pipeline updates the GitOps image reference and Argo CD rolls it out | In progress (`gitops` job writes tag + digest to image-tags.yaml on a branch and opens a pull request, never pushes to main; chart renders repository@digest; needs "Allow GitHub Actions to create pull requests" and Argo CD; not run) | Manifest-update commit; Argo CD sync; rollout | GitOps directory, `docs/screenshots/argocd/` | The running pod's image digest equals the ECR digest |
| G07.7 | Successful end-to-end run recorded | Not started (needs the first green GitHub run) | Run screenshot | `docs/screenshots/cicd/` | All jobs green |
| G07.8 | Appropriately failing runs recorded: a failing test and a security finding each stop publishing | Not started (planned: a failing test and a Trivy-blocked image, each stopping publish) | Run screenshots | `docs/screenshots/cicd/` | Publish and deploy jobs skipped after the failure |

### G08 ArgoCD GitOps (15 points)

| Field | Record |
|---|---|
| Status | In progress |
| Existing implementation | Implemented locally (not installed): `gitops/argocd/values.yaml` (Argo CD v3.5.4, chart 10.9.7, non-HA, no Dex/notifications/Ingress, port-forward access, Application health check for waves), `gitops/argocd/root-application.yaml` (app of apps over `gitops/kustomization.yaml`; Kustomize patches with `test` guards inject VPC, zone, security group and ECR URLs, never committed), child Applications with automated prune/self-heal and sync waves (cert-manager 0; load balancer controller and ClusterIssuers 1; NGINX 2; ExternalDNS 3; FinSight 4), `scripts/render-argocd-root.ps1`, `scripts/validate-gitops.ps1` + `tests/gitops` (27 passed); runbook `docs/infrastructure/argocd.md` |
| Missing | Live install and evidence (pods, admin secret deleted, app tree, Git-triggered sync, Synced/Healthy, drift reverted, history/rollback); monitoring Application (G05 extension point) |
| Runtime / repository evidence | Application status, sync history, drift test |
| Objective verification | Git changes reach the cluster without manual `kubectl`; drift is corrected |
| Reviewer IDs | R8.1-R8.5, R4.2 |
| Ticket | [#23](https://github.com/Fer-as/finsight-eks-data-platform/issues/23), [#24](https://github.com/Fer-as/finsight-eks-data-platform/issues/24) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G08.1 | Argo CD installed from a pinned chart; initial admin secret rotated or removed | In progress (chart 10.9.7 / v3.5.4 values validated for Kubernetes 1.36; rotation and secret deletion are runbook step 4; not installed) | Values; secret status | GitOps directory | Argo CD pods Running |
| G08.2 | Desired state for FinSight and platform add-ons (NGINX, cert-manager, ExternalDNS, monitoring) declared in Git, e.g. app-of-apps | In progress (root Application `finsight-root` over `gitops/kustomization.yaml`: load balancer controller, cert-manager, ClusterIssuers, NGINX, ExternalDNS, FinSight; monitoring slot for G05; root build and every child render validated; not applied) | Application manifests | GitOps directory | Every workload is owned by an Argo CD Application |
| G08.3 | Automated sync with prune and self-heal; a Git change reaches the cluster without manual steps | In progress (automated prune + self-heal on every Application, polling 120 s + jitter; pruning/deletion semantics documented; demonstration not run) | Sync history | `docs/screenshots/argocd/` | Change replicas in Git and observe reconciliation |
| G08.4 | All applications Synced and Healthy | Not started (needs the live install) | Screenshot | `docs/screenshots/argocd/` | No OutOfSync or Degraded applications |
| G08.5 | Manual drift is reverted automatically | In progress (self-heal configured; `kubectl scale` demonstration prepared in the runbook; not run) | Before/after evidence | `docs/evidence/` | `kubectl scale` is undone by Argo CD |

### G09 Architecture Design (10 points)

| Field | Record |
|---|---|
| Status | Not started |
| Existing implementation | Mermaid diagrams in `docs/architecture/day1.md` and `day2-aws.md` (not the deliverable) |
| Missing | Original editable draw.io diagram and exported image |
| Runtime / repository evidence | `.drawio` source and PNG |
| Objective verification | Every required component and flow is present and matches the deployed system |
| Reviewer IDs | R2.1-R2.4, R1.2 |
| Ticket | [#28](https://github.com/Fer-as/finsight-eks-data-platform/issues/28) |

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| G09.1 | Original, editable draw.io source with official AWS icons and an exported PNG | Not started | `.drawio` and `.png` | `docs/architecture/` | Opens and edits in diagrams.net |
| G09.2 | AWS networking: Region, VPC, two AZs, public and private subnets, IGW, NAT gateway, routes, S3 endpoint | Not started | Diagram | Same | Labels match Terraform |
| G09.3 | EKS, ingress (NGINX and load balancer), DNS (Route 53, ExternalDNS) and certificates (cert-manager, Let's Encrypt) | Not started | Diagram | Same | Every component present |
| G09.4 | IAM (cluster, node and Pod Identity roles, GitHub OIDC roles), CI/CD (both pipelines, ECR), GitOps (Argo CD) and monitoring (Prometheus, Grafana) | Not started | Diagram | Same | Every component present |
| G09.5 | Traffic and data flows drawn with a legend: user request, outbound via NAT, CI to ECR to Git to Argo CD, ETL to S3 and PostgreSQL, metrics scraping | Not started | Diagram | Same | Each flow traceable to code or manifests |

## 4. Reviewer-quality criteria (R1-R13, preserved)

These are the original reviewer-derived criteria with their original IDs, statuses, evidence
and verification fields. Section numbers changed from 1-13 to 4.1-4.13 to fit this document;
the IDs did not change. The only content change is the evidence note on R10.5, updated
because the stale tracker statement it cited has been corrected.

Evidence conventions are in part 6. The graded criteria in part 3 cite these IDs.

### Reviewer-quality status summary (14 October 2026)

| Area | Verified | In progress | Not started | Not applicable |
|---|---:|---:|---:|---:|
| 1. README | 0 | 2 | 4 | 0 |
| 2. Architecture diagram | 0 | 0 | 4 | 0 |
| 3. Application demo | 0 | 0 | 3 | 0 |
| 4. Screenshots | 0 | 0 | 7 | 0 |
| 5. Workload hardening | 0 | 1 | 6 | 0 |
| 6. Secrets, TLS, ingress, identity | 0 | 1 | 5 | 0 |
| 7. CI/CD | 0 | 1 | 9 | 0 |
| 8. GitOps and image tagging | 0 | 0 | 5 | 0 |
| 9. Terraform | 3 | 2 | 1 | 0 |
| 10. Code quality | 0 | 2 | 4 | 0 |
| 11. Commit messages | 0 | 1 | 1 | 0 |
| 12. Teardown and evidence | 0 | 1 | 3 | 0 |
| 13. Scope decisions | 0 | 0 | 0 | 3 |

### 4.1 Professional README

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R1.1 | Overview states what FinSight does, for whom, and that all data is synthetic, in under 150 words | In progress | Overview section | `README.md` | Read the top section; a newcomer can say what the app does without opening other files |
| R1.2 | Architecture summary with the exported diagram embedded and links to the detailed architecture docs | Not started | Embedded diagram image and links | `README.md`, `docs/architecture/` | Diagram renders on GitHub; every link resolves |
| R1.3 | Key architecture decisions listed with the reason for each (e.g. EKS 1.36 STANDARD, Pod Identity over IRSA, single NAT, managed node group, S3 native locking) | Not started | Decisions section linking to the detailed records | `README.md`, `docs/infrastructure/` | Each decision has a stated reason and a link |
| R1.4 | Local setup works from a clean clone with the documented prerequisites and commands | In progress | Prerequisites list, commands, expected result | `README.md` "Start locally" section | Follow it on a clean clone; app starts and `scripts/verify.ps1` passes |
| R1.5 | Deployment section gives the ordered bootstrap, foundation, platform and application steps, with approval gates and links to the runbook | Not started | Deployment section | `README.md`, `docs/infrastructure/runbook.md` | Steps match the runbook and the readiness record |
| R1.6 | Technology choices table and a short future-improvements list | Not started | Both sections | `README.md` | Every major component appears with a one-line reason; improvements are concrete |

### 4.2 Original draw.io architecture diagram

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R2.1 | Original, editable draw.io source committed (not a copied template) | Not started | `.drawio` file | `docs/architecture/finsight-architecture.drawio` | Opens in diagrams.net and is editable |
| R2.2 | Network layer labelled: Region, VPC CIDR, two AZs, public and private subnets with CIDRs, internet gateway, single NAT gateway, route to the internet, S3 gateway endpoint | Not started | Diagram | Same file and exported PNG | Compare every label with `infra/terraform/config/defaults.json` and the network module |
| R2.3 | Traffic and platform layer labelled: Route 53, load balancer, ingress controller, cert-manager, ExternalDNS, EKS control plane, managed nodes, namespaces, services, Argo CD, Prometheus and Grafana | Not started | Diagram | Same | Every component shown is deployed or explicitly marked "planned" |
| R2.4 | Data flow drawn: user request path, ETL reading and writing S3 raw/curated, PostgreSQL, CI to ECR to Argo CD, and the GitHub OIDC trust | Not started | Diagram with arrows and a legend | Same | Trace each flow against the code and manifests |

### 4.3 Short application demonstration

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R3.1 | Recorded demo of three to five minutes showing real FinSight usage over HTTPS on the EKS hostname: dashboard, KPIs, and data produced by the ETL | Not started | Video file or unlisted link | Linked from `README.md` | Watch it; the URL bar shows HTTPS on the project hostname |
| R3.2 | The demo shows the application, not a long infrastructure walkthrough; infrastructure is evidenced by screenshots and docs instead | Not started | Same video | Same | Infrastructure screens take under a quarter of the running time |
| R3.3 | No secrets, account IDs or private data visible in the recording | Not started | Same video | Same | Review the full recording before publishing |

### 4.4 Genuine screenshots

Each screenshot must come from the real deployed environment and be dated in its filename.

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R4.1 | EKS workloads: nodes Ready across both AZs and all FinSight pods Running | Not started | `kubectl get nodes` and `get pods -A` output, or console view | `docs/screenshots/eks/` | Names and dates match the deployment record |
| R4.2 | Argo CD applications Synced and Healthy | Not started | Argo CD UI | `docs/screenshots/argocd/` | Application names match the repository manifests |
| R4.3 | Prometheus targets up | Not started | Targets page | `docs/screenshots/monitoring/` | FinSight and cluster targets show UP |
| R4.4 | Grafana dashboard with live FinSight or cluster metrics | Not started | Dashboard view | `docs/screenshots/monitoring/` | Time range is within the deployment window |
| R4.5 | CI/CD runs passing: tests, scans, image build and publish | Not started | GitHub Actions run summaries | `docs/screenshots/cicd/` | Run IDs match the repository history |
| R4.6 | Data processing: ETL job completed and curated output in S3 | Not started | Job logs and S3 listing | `docs/screenshots/data/` | Object keys match the ETL code's prefixes |
| R4.7 | Application served over HTTPS with a valid certificate | Not started | Browser view with certificate details | `docs/screenshots/app/` | Issuer is Let's Encrypt; hostname matches the configuration |

### 4.5 Kubernetes workload hardening

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R5.1 | Every FinSight container runs as a non-root user (`runAsNonRoot: true` with an explicit UID) | In progress | Dockerfiles already set non-root users; manifests pending | `apps/*/Dockerfile`, Kubernetes manifests | `kubectl get pod -o jsonpath` shows the securityContext; `id` inside the container is not 0 |
| R5.2 | `allowPrivilegeEscalation: false` and all capabilities dropped | Not started | Manifests | Kubernetes manifests | Inspect manifests; Checkov Kubernetes checks pass |
| R5.3 | `readOnlyRootFilesystem: true` wherever compatible, with writable `emptyDir` mounts only where needed; exceptions documented | Not started | Manifests and an exceptions note | Kubernetes manifests, `docs/evidence/` | Pods run; each exception has a reason |
| R5.4 | Readiness and liveness probes on every long-running container, pointing at real health endpoints | Not started | Manifests and health endpoints | Kubernetes manifests, `apps/api` | Kill the process or block the endpoint and observe restart or removal from the Service |
| R5.5 | Rolling updates with `maxUnavailable` / `maxSurge` set; a new release rolls out without downtime | Not started | Deployment spec and rollout output | Kubernetes manifests, `docs/evidence/` | `kubectl rollout status` during a version change while requests continue |
| R5.6 | CPU and memory requests and limits set for every container | Not started | Manifests | Kubernetes manifests | Inspect manifests; pods fit on two m7i.large nodes |
| R5.7 | Production frontend image serves the built static assets (the current frontend Dockerfile provides only a development stage) | In progress (production target: Vite build served by unprivileged NGINX on 8080; built and smoke-tested locally; not published) | Production build stage | `apps/frontend/Dockerfile` | Image runs without the dev server and passes Trivy |

### 4.6 Secrets, TLS, ingress and workload identity

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R6.1 | No secret values in Git, images or plain manifests; the chosen secret mechanism is documented with its reason | Not started | Design note and manifests | `docs/`, Kubernetes manifests | Secret scanning (e.g. gitleaks) passes; manifests reference secrets only by name |
| R6.2 | Database credentials delivered to pods through the documented mechanism and rotatable without rebuilding images | Not started | Manifests and a rotation note | Kubernetes manifests, `docs/` | Rotate once and confirm the app reconnects |
| R6.3 | TLS certificate issued by cert-manager (Let's Encrypt) and shown Ready | Not started | `kubectl get certificate` | `docs/evidence/`, `docs/screenshots/app/` | Certificate Ready=True; browser shows a valid chain |
| R6.4 | Ingress routes only the intended hostname and paths, with HTTP redirected to HTTPS; controller choice approved by the assessor | In progress | Ingress manifest, controller values, assessor decision | Kubernetes manifests, `docs/assessment-tracker.md` | `curl -I http://...` redirects; unknown hosts are rejected |
| R6.5 | ExternalDNS limited to the one hosted zone and owns only its records | In progress (zone-id and domain filters, TXT owner ID, name-scoped IAM policy; verified offline; not deployed) | Controller values and IAM policy | Helm values, Terraform | Records carry the ownership TXT record; IAM policy names a single zone |
| R6.6 | Workloads that call AWS use EKS Pod Identity with one role per service account; no node-role permissions used by apps | Not started (Terraform for CNI, EBS CSI and ETL roles exists; not yet deployed) | Pod Identity associations and a test pod | `infra/terraform/modules/eks`, `environments/dev/platform` | From the ETL pod, `aws sts get-caller-identity` shows the ETL role; access outside raw/ and curated/ is denied |

### 4.7 Efficient CI/CD

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R7.1 | Application tests run in CI for the API, ETL and frontend | Not started | Workflow and passing run | `.github/workflows/`, `docs/screenshots/cicd/` | A failing test fails the run |
| R7.2 | Build matrix used only where it removes duplication (e.g. one job definition building api, etl and frontend images); no matrix for its own sake | Not started | Workflow | `.github/workflows/` | Review: no copy-pasted jobs; matrix entries map to real artefacts |
| R7.3 | Terraform fmt, validate, tests and Checkov run in CI | In progress (#10 workflow written; no run yet) | Workflow and run | `.github/workflows/`, `scripts/validate-terraform.ps1` | Introduce a formatting error on a branch and see the run fail |
| R7.4 | Trivy scans every image before publishing, failing on HIGH/CRITICAL fixable findings, with documented exceptions | Not started | Workflow, results, exceptions file | `.github/workflows/`, `docs/evidence/` | Results attached to the run; exceptions have reasons and expiry dates |
| R7.5 | AWS access only through GitHub OIDC roles; no long-lived AWS keys in GitHub | In progress (roles applied; plan job uses OIDC only; repository and environment secrets contain no AWS keys) | Workflow `permissions: id-token: write`, repository secret list | `.github/workflows/` | Repository and environment secrets contain no AWS access keys |
| R7.6 | Role ARNs supplied as GitHub environment variables in `dev-infrastructure` and `dev-images`, taken from Terraform outputs, not hard-coded in workflow files | In progress (`AWS_ROLE_ARN` set in `dev-infrastructure-apply`; workflow uses `vars.AWS_ROLE_ARN`, no `arn:aws` literal; `AWS_ROLE_ARN` also set in protected `dev-infrastructure`; `dev-images` not configured) | Environment settings, workflow references | GitHub settings, `.github/workflows/` | `grep` for `arn:aws` in workflows returns nothing |
| R7.7 | Clear job dependencies (`needs:`): test and scan, then build, then publish, then manifest update | Not started | Workflow graph | `.github/workflows/` | Workflow graph screenshot shows the intended order |
| R7.8 | No unnecessary repeated work: path filters, a concurrency group with cancel-in-progress, dependency caching, and each check run once per change | In progress (Terraform workflow: path filters, per-PR cancel-in-progress for checks, provider plugin cache; plan serialised per state, never cancelled) | Workflow | `.github/workflows/` | A docs-only change does not run image builds; a pushed fix cancels the superseded run |
| R7.9 | Pinned action versions (commit SHA or exact tag) and least-privilege `permissions:` per workflow | In progress (Terraform workflow: all actions pinned to commit SHAs, `permissions: {}` default, per-job grants; Checkov GitHub Actions 64 passed / 0 failed; actionlint clean) | Workflow | `.github/workflows/` | Review; Checkov GitHub Actions checks pass |
| R7.10 | Infrastructure plan runs in CI with the plan-only role; apply stays a reviewed manual step | In progress (#10 plan job uses the plan-only role; no apply in the workflow) | Workflow and run | `.github/workflows/` | The plan role cannot apply (its IAM policy is read-only apart from the lock file) |

### 4.8 Argo CD GitOps and image tagging

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R8.1 | Argo CD deploys FinSight from Git; no manual `kubectl apply` for application workloads | In progress (FinSight Application from Git at `main`; the only manual applies are the one-time root Application and the database Secret; not installed) | Application manifests | Repository GitOps directory | Change a replica count in Git and watch Argo CD reconcile it |
| R8.2 | Images tagged reproducibly with the Git commit SHA (no `latest`); manifests pin by tag and digest | In progress (pipeline tags with the commit SHA, writes tag + digest to `image-tags.yaml`; the FinSight Application renders `repository@digest`, tested; no image published yet) | Workflow and manifests | `.github/workflows/`, GitOps directory | The deployed image digest equals the ECR digest for that commit |
| R8.3 | CI updates manifests efficiently: one small commit changing only the image reference (e.g. `kustomize edit set image`), not regenerated files | In progress (the GitOps pull request changes only `gitops/apps/finsight/image-tags.yaml`; not yet run) | Commit history | GitOps directory | The manifest-update commit diff touches only image lines |
| R8.4 | Sync and self-heal behaviour documented and demonstrated | In progress (documented in `docs/infrastructure/argocd.md`; demonstration not run) | Screenshot and note | `docs/screenshots/argocd/`, `docs/` | Manual drift is reverted by Argo CD |
| R8.5 | Argo CD admin access secured; initial admin password rotated or disabled | In progress (no Ingress, port-forward only, exec off, no Dex; rotation and initial-secret deletion in runbook step 4; not done) | Note and configuration | `docs/` | Initial admin secret removed after setup |

### 4.9 Terraform

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R9.1 | Modular Terraform: reusable modules with READMEs, separate bootstrap, foundation and platform roots, central configuration | Verified | Module tree, `validate` passing on all three roots | `infra/terraform/` | `scripts/validate-terraform.ps1` passed 14 October 2026 (3/3 roots, 9/9 tests) |
| R9.2 | Remote S3 state with native locking, encryption, versioning and a distinct key per root | Verified (bootstrap and foundation) | Applied backends and lock behaviour | `infra/terraform/*/backend.tf`, `scripts/new-terraform-backend-config.ps1` | Bootstrap migrated and foundation applied to S3 on 14 October 2026; plans showed no changes; lock objects created and released |
| R9.3 | Security exceptions are resource-scoped, justified and listed in one place | Verified | Checkov results and exceptions table | `docs/evidence/day2-terraform-validation.md`, `docs/evidence/day2-checkov-results.json` | Checkov 3.3.27: 130 passed, 0 failed, 15 documented skips |
| R9.4 | Architecture decisions documented in one index (decision, reason, alternatives, date) | In progress | Decision records exist across several documents; no single index yet | `docs/infrastructure/`, `docs/architecture/` | Every R1.3 decision has a record linked from the index |
| R9.5 | Platform applied and verified, then torn down cleanly with no orphaned resources | Not started | Apply, verification and teardown evidence | `docs/evidence/` | Runbook section 6 checks completed and recorded |
| R9.6 | Retention safeguards demonstrated: `prevent_destroy`, no forced deletion, retained data survives platform teardown | In progress (configured and applied; survival not yet demonstrated) | Post-teardown listing | `docs/evidence/` | After platform teardown, the state, data, log buckets and ECR repositories still exist |

### 4.10 Formatting, linting and documentation quality

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R10.1 | Pre-commit hooks for whitespace, end-of-file, YAML/JSON validity, large files and secret detection | Not started | Config file | `.pre-commit-config.yaml` | `pre-commit run --all-files` passes |
| R10.2 | Python formatted and linted (ruff), frontend formatted (prettier), Terraform formatted (`terraform fmt`) | In progress (tool configuration and scripts exist; not wired into pre-commit or CI) | Config and passing runs | `pyproject.toml`, `apps/frontend/package.json`, scripts | All format checks pass in CI |
| R10.3 | YAML and HCL linted (yamllint, tflint) with a clean result | Not started | Config files and run output | `.yamllint`, `.tflint.hcl` | Linters pass in CI |
| R10.4 | Kubernetes manifests validated (e.g. kubeconform) and scanned (Checkov) | Not started | CI step | `.github/workflows/` | An invalid manifest fails CI |
| R10.5 | Documentation concise and professional: no stale statements, every claim dated or evidenced | In progress | Documentation review | `docs/` | Review before submission. The stale add-on statement in `assessment-tracker.md` was corrected on 14 October 2026; repeat the review after each milestone |
| R10.6 | No broken links in Markdown | Not started | Link check output | CI or local check | Link checker passes |

### 4.11 Meaningful Git commit messages

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R11.1 | Every commit message states what changed and why in specific terms (Conventional Commits style); no vague messages such as "fix", "update" or "changes" | In progress (existing feature commits follow this; convention not enforced) | Git history | `git log` | Review the history before submission |
| R11.2 | Convention written down and checked (e.g. commit-msg hook or PR title check) | Not started | Contributing note and hook or check | `README.md` or `CONTRIBUTING.md`, `.pre-commit-config.yaml` | A vague message is rejected |

### 4.12 Cost-conscious teardown and retained evidence

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| R12.1 | Teardown procedure covering controller-created resources (load balancers, DNS records, volumes) before Terraform destroy | In progress (documented, not executed) | Runbook section | `docs/infrastructure/runbook.md` section 6 | Executed once; every step recorded |
| R12.2 | All portfolio evidence (screenshots, demo, command evidence) captured and committed **before** teardown | Not started | Evidence files | `docs/screenshots/`, `docs/evidence/` | Checklist sections 3 and 4 complete before the destroy plan is approved |
| R12.3 | Post-teardown verification shows no billable platform resources remain | Not started | Listing of EKS, EC2, NAT, EIP, load balancers and EBS volumes | `docs/evidence/` | Each listing is empty for FinSight tags |
| R12.4 | Actual cost recorded against the estimate | Not started | Cost Explorer summary | `docs/infrastructure/costs.md` | Actual vs estimate with an explanation of any difference |

### 4.13 Reviewer-praised technologies not adopted

These were praised in the reviewed project. For FinSight they would add cost and moving parts
without serving a requirement, so they are **Not applicable**, with the rationale recorded here
for the assessor.

| ID | Technology | Status | Rationale | Revisit if |
|---|---|---|---|---|
| R13.1 | Amazon SQS | Not applicable | FinSight's ETL is a scheduled batch over synthetic files in S3. No producer emits events that need buffering or retry between services; a queue would add IAM, monitoring and failure paths with nothing to decouple. | Ingestion becomes event-driven, e.g. per-file processing on S3 upload. |
| R13.2 | KEDA | Not applicable | KEDA scales on event sources such as queues. With no queue and a fixed, low-traffic demo load, it would have nothing meaningful to scale on. A standard HorizontalPodAutoscaler on CPU covers the API if scaling is demonstrated. | An event source (R13.1) is introduced. |
| R13.3 | Karpenter | Not applicable | The budget and design use a fixed managed node group of two m7i.large nodes for a short demo window. Karpenter needs its own controller, IAM, an interruption queue and node-class configuration, and its main benefit (fast, varied node provisioning) does not apply to a two-node cost-capped cluster. | Workloads need varied instance types, Spot capacity or frequent scale-out. |

### Using part 4

- Update the status, evidence and location columns in the same change that produces the evidence.
- Change a status to Verified only after carrying out the verification method, and note the date.
- Keep the reviewer status summary table in step with the rows.

## 5. FinSight application and data-engineering criteria

These are FinSight's own goals, beyond the rubric.

| ID | Criterion | Status | Required evidence | Location | Verification |
|---|---|---|---|---|---|
| F1 | Original financial analytics application: FastAPI reporting API and React dashboard over synthetic GBP data, with documented KPI definitions | Verified (local, 13 October 2026) | Day 1 verification record | `apps/`, `docs/kpi-definitions.md`, `docs/evidence/day1-verification.md` | Day 1: API analytics returned a populated GBP report through the frontend proxy |
| F2 | Deterministic synthetic data generator; no real personal or financial data anywhere | In progress | Generator code and data note; a written statement reviewed before submission | `pipelines/src/finsight_pipelines/synthetic.py`, `config/synthetic.json`, `data/README.md` | Same seed reproduces identical data; review confirms no real data |
| F3 | Pandas ETL validates and rejects bad records, writes curated Parquet, and loads PostgreSQL from that Parquet atomically | Verified (local, 13 October 2026) | ETL tests and Day 1 record | `pipelines/src/finsight_pipelines/etl.py`, `pipelines/tests/test_etl.py`, `docs/evidence/day1-verification.md` | Day 1: 37 Python tests passed, including Parquet reconciliation and atomic rollback |
| F4 | ETL runs on EKS as a Kubernetes Job or CronJob, reading and writing S3 `raw/` and `curated/` through its Pod Identity role | Not started | Job manifest, logs, S3 listing | GitOps directory, `docs/screenshots/data/` | Job completes; objects appear under the expected prefixes; other prefixes denied |
| F5 | ELT path: raw loader plus dbt staging, intermediate and mart models with uniqueness, not-null, relationship and reconciliation tests | Not started (reserved; READMEs only) | dbt project and `dbt test` output | `warehouse/dbt/`, `pipelines/src/finsight_pipelines/elt/` | `dbt build` passes; marts reconcile with ETL totals |
| F6 | PostgreSQL on EKS with an encrypted gp3 volume (EBS CSI), credentials from the documented secret mechanism, and a backup taken before teardown | Not started | Manifests, PVC status, backup record | GitOps directory, `docs/evidence/` | PVC Bound and encrypted; restore of the backup tested |
| F7 | Python and PostgreSQL integration tests and frontend tests pass in CI as well as locally | In progress (local: 37 + 6 passed on 13 October 2026) | CI run | `.github/workflows/` | Same suites green in GitHub Actions |
| F8 | Dashboard figures match the KPI definitions and the database totals | In progress (KPI definitions documented) | Comparison note | `docs/kpi-definitions.md`, `docs/evidence/` | Spot-check three KPIs against SQL |
| F9 | Deployed application demonstrated end to end: data generated, processed, served and viewed over HTTPS | Not started | Demo video (R3.1) and screenshots | `README.md` link, `docs/screenshots/` | Watch the demo |

## 6. Evidence and verification requirements

- Screenshots: `docs/screenshots/<area>/<yyyy-mm-dd>-<subject>.png`. Areas: `board`, `eks`,
  `argocd`, `monitoring`, `cicd`, `data`, `app`.
- Diagrams: `docs/architecture/finsight-architecture.drawio` and the exported
  `finsight-architecture.png`.
- Command evidence: `docs/evidence/<topic>.md` with date, command, summarised result and who
  ran it. Never commit raw Terraform state or plan output.
- Redact account IDs, ARNs containing them, public IPs, zone IDs and OIDC repository IDs
  before committing. Do not commit secrets, tokens, kubeconfigs or `.env` files.
- Runtime claims need runtime evidence: workflow runs, Kubernetes output, HTTPS tests,
  dashboards with live data, or the demo recording. Planned configuration is not evidence.
- No fabricated screenshots, outputs, scores or approvals. If evidence is lost, the
  criterion returns to In progress.
- Every runtime artefact records whether it came from a live system or a recorded deployment,
  and its date. After teardown, the portfolio must remain fully reviewable from these records.

## 7. Outstanding implementation gaps, by priority

Ordered by grading weight, dependencies and the aim of keeping the paid EKS window short:
everything that can be built and tested without the platform comes first.

| Priority | Gap | Categories | Needs AWS spend? |
|---:|---|---|---|
| 1 | Board and issues created 14 October 2026 ([#4](https://github.com/Fer-as/finsight-eks-data-platform/issues/4)). Board made public 14 October 2026. Remaining: link every PR, capture dated screenshots | G01 (10) | No |
| 2 | Terraform gaps before the first platform plan: ExternalDNS and cert-manager DNS-01 roles done locally ([#6](https://github.com/Fer-as/finsight-eks-data-platform/issues/6)); AWS Load Balancer Controller role done locally ([#34](https://github.com/Fer-as/finsight-eks-data-platform/issues/34)); security groups done locally, runtime evidence pending #30 ([#7](https://github.com/Fer-as/finsight-eks-data-platform/issues/7)); a CI apply role behind a protected environment | G02, G04, G06 | No (plan only) |
| 3 | Pipelines: Terraform workflow (checks, plan, gated apply); application workflow (tests, Checkov, matrix builds, Trivy, ECR push, GitOps image update); production frontend and ETL images | G06 (10), G07 (30), R5.7 | ECR storage only |
| 4 | GitOps repository layout and Argo CD applications for FinSight, NGINX, cert-manager, ExternalDNS and monitoring, with hardened manifests (R5), tested on a local cluster first | G03, G04, G05, G08, R5 | No |
| 5 | Original draw.io architecture diagram and README rewrite | G09 (10), R1, R2 | No |
| 6 | One planned deployment window: platform apply, sync everything, capture all runtime evidence (G02-G08), record the demo, then tear down | G02-G08, R3, R4, R12 | Yes, about $10/day |
| 7 | dbt ELT path | F5 | No |

Decisions needed from the owner: assessor confirmation that F5 NGINX Ingress Controller
satisfies "NGINX Ingress Controller"; HTTP-01 or DNS-01 for cert-manager; whether to use the
AWS Load Balancer Controller or the default cloud-provider load balancer for NGINX.

## 8. Final pre-submission quality gate

FinSight may be submitted only when all of the following hold:

- [ ] All nine categories G01-G09 are Verified, and the scorecard still totals 135.
- [ ] Every R criterion (part 4) is Verified, or Not applicable with a rationale (R13 only).
- [ ] Every F criterion (part 5) is Verified, or explicitly deferred by the owner with a reason.
- [ ] Section 9 is complete: evidence captured during a real deployment and teardown verified.
- [ ] `docs/assessment-tracker.md` agrees with this checklist.
- [ ] No secrets or unredacted identifiers in the repository (secret scan clean).
- [ ] All formatting, linting and tests pass in CI on the final commit.
- [ ] README, diagram, demo link and evidence links all resolve.
- [ ] Commit history is meaningful; no work-in-progress or vague messages on the main branch.

## 9. Live-deployment evidence and teardown gate

Before the platform apply:

- [ ] Steps 1-5 of part 7 are done, so the paid window is used only for deployment and evidence.
- [ ] The owner has approved the window length, the teardown time and the platform plan.
- [ ] `eks.compatibility_verified=true` set in the ignored `local.json` with the owner's approval.

During the window, capture and commit before any teardown:

- [ ] G02.7, G03.2-G03.4, G04.2-G04.6, G05.2-G05.4, G07.6-G07.8, G08.3-G08.5, F4, F6 evidence.
- [ ] Screenshots R4.1-R4.7 and the demo recording R3.1-R3.3.

Teardown:

- [ ] Runbook section 6 followed: controller-created load balancers, DNS records and volumes
      removed first, then the platform destroy plan reviewed and approved.
- [ ] Post-teardown listing shows no FinSight EKS, EC2, NAT, Elastic IP, load balancer or
      unattached EBS resources (R12.3), and retained buckets and repositories still exist (R9.6).
- [ ] Actual cost recorded against the estimate (R12.4).
- [ ] All evidence labelled "recorded deployment, <date>"; nothing claims to be live.

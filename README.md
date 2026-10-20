# FinSight on Amazon EKS

FinSight is a financial reporting application (React, FastAPI, PostgreSQL and a Pandas ETL) that I
deployed to Amazon EKS in eu-west-2. Its dashboard shows revenue, expenses, profit, departmental budgets
and transaction risk indicators, the view a small finance team would use. The application is
intentionally small; it is a DevOps portfolio and assessment project, and the work in this repository
is the platform around it:

- Terraform split into three roots with remote state;
- GitHub Actions pipelines that use OIDC instead of stored AWS keys;
- Terraform applies that run only after an approved, encrypted saved plan;
- Argo CD deploying and reconciling the application and Kubernetes platform services.

**Recorded deployment, 16–20 October 2026.** It ran at `eks.feras-dev.co.uk` and used synthetic GBP
data only. I tore the platform down on 20 October 2026 to stop its running costs
([teardown evidence](docs/evidence/2026-10-20-platform-teardown.md)); the state, data, images and CI
identity are retained.

- [Architecture](#architecture)
- [Recorded deployment](#recorded-deployment)
- [Infrastructure (Terraform)](#infrastructure-terraform)
- [Cluster platform (Argo CD)](#cluster-platform-argo-cd)
- [CI/CD](#cicd)
- [Deploying from scratch](#deploying-from-scratch)
- [Technology choices](#technology-choices)
- [Application and data](#application-and-data)
- [Monitoring](#monitoring)
- [Limitations and planned work](#limitations-and-planned-work)
- [Running locally](#running-locally)
- [Repository layout](#repository-layout)

## Architecture

![FinSight architecture: AWS network, EKS, ingress, DNS/TLS, CI/CD, GitOps and monitoring](docs/architecture/finsight-architecture.png)

The diagram is an editable diagrams.net file,
[docs/architecture/finsight-architecture.drawio](docs/architecture/finsight-architecture.drawio). It has
three pages: the AWS overview, the Kubernetes platform
([PNG](docs/architecture/finsight-architecture-kubernetes.png)), and CI/CD with IAM
([PNG](docs/architecture/finsight-architecture-cicd.png)).

A request travels:
1. from Route 53 to an internet-facing Network Load Balancer in the public subnets;
2. then to the F5 NGINX Ingress Controller;
3. then to the frontend or API pods on worker nodes in private subnets;
4. and finally to PostgreSQL, which runs in the cluster.

## Recorded deployment

Verified on 16–17 October 2026, and removed on 20 October 2026:

| Area | State |
|---|---|
| EKS | Kubernetes 1.36 cluster `finsight-dev`; two `m7i-flex.large` nodes Ready, one in eu-west-2a and one in eu-west-2b |
| GitOps | Eight Argo CD Applications (a root app and seven children), all Synced and Healthy |
| Ingress, DNS and TLS | NGINX behind an NLB; ExternalDNS manages the Route 53 records; Let's Encrypt production certificate from cert-manager; HTTP redirects to HTTPS |
| Application | API, frontend and PostgreSQL running; images pulled from ECR by digest |
| Monitoring | Prometheus scrape targets up, including the API and NGINX; FinSight dashboard in Grafana. After OOMKilled restarts, Grafana's memory was raised on 19 October 2026 (PR #57) and its dashboards were re-checked the same day |

The cluster is a development environment. I can destroy the `platform` Terraform root (VPC, NAT
gateway, EKS and nodes) to control costs while retaining `bootstrap` and `foundation` for Terraform
state, container images and CI identity. The table above records the deployment state verified on
16–17 October 2026, plus the Grafana recovery on 19 October 2026.

## Infrastructure (Terraform)

The code uses Terraform 1.16.2, with the AWS provider pinned to 6.59.0 and checksum lock files in
every root. Setup and configuration are described in [infra/terraform](infra/terraform/README.md).

| Root | Contents | Lifetime |
|---|---|---|
| [`bootstrap`](infra/terraform/bootstrap) | Encrypted, versioned state bucket and its access-log bucket | Permanent |
| [`environments/dev/foundation`](infra/terraform/environments/dev/foundation) | ECR repositories, data bucket, GitHub OIDC provider and CI roles | Kept when the cluster is rebuilt |
| [`environments/dev/platform`](infra/terraform/environments/dev/platform) | VPC, NAT gateway, flow logs, EKS, node group, add-ons and Pod Identity roles | Disposable |

Each root has its own S3 state key and uses S3 native locking. I split the roots by lifetime:
- The expensive, short-lived resources (NAT gateway, EKS) live in `platform`, and I can destroy it
  without touching the state bucket, the image repositories or the CI identity.
- The roots don't read each other's state. Shared names come from a single `config` module.

The roots are built from eleven local [modules](infra/terraform/modules), including `network`, `eks`,
`ecr`, `github-oidc` and `pod-role`. Their inputs are typed and validated, and eight of the modules
have `terraform test` suites.

Decisions and trade-offs:

- **Single NAT gateway.** It costs less than one per AZ. The downside is that the private subnets lose
  outbound access if eu-west-2a fails, which I accept for a development environment
  ([costs](docs/infrastructure/costs.md)).
- **Private worker nodes.** Nodes run only in private subnets, with IMDSv2 required and encrypted root
  volumes. The EKS API endpoint is public but limited to configured CIDR ranges. On the deployed
  cluster I checked that the endpoint is not open to `0.0.0.0/0`, that no node has a public IP and that
  the node group has no SSH access ([network security](docs/infrastructure/network-security.md)).
- **EKS Pod Identity.** The load balancer controller, ExternalDNS and cert-manager each get their own IAM
  role, tied to one service account. The two DNS controllers can change records only in the FinSight
  hosted zone ([DNS and certificates](docs/infrastructure/dns-and-certificates.md),
  [load balancer controller](docs/infrastructure/load-balancer-controller.md)).
- **Ingress only through the NLB.** The application is reached only through the internet-facing NLB.
  The Terraform configuration gives the NLB its own security group and allows it to reach only the
  ingress controller's pod ports. The rule set is in
  [network security](docs/infrastructure/network-security.md); the deployed security groups were
  checked against it on 18 October 2026 ([evidence](docs/screenshots/eks/2026-10-18-network-iam-security-verification.md#g024-security-groups-every-group-in-the-vpc)).

## Cluster platform (Argo CD)

Argo CD (chart 10.9.7) uses an app-of-apps layout: a single root Application tracks
[`gitops/kustomization.yaml`](gitops/kustomization.yaml). Sync waves install the dependencies first:

| Wave | Application | Version |
|---|---|---|
| 0 | cert-manager | v1.21.2 |
| 1 | AWS Load Balancer Controller | 3.6.0 |
| 1 | ClusterIssuers (Let's Encrypt staging and production) | n/a |
| 1 | kube-prometheus-stack | 91.8.2 |
| 2 | F5 NGINX Ingress Controller | chart 2.7.3, controller 5.6.3 |
| 3 | ExternalDNS | 1.23.0 |
| 4 | FinSight (local Helm chart) | n/a |

All chart versions are pinned. Automated sync runs with `prune` and `selfHeal`, so manual changes in the
cluster are reverted; the drift test is in the [Argo CD runbook](docs/infrastructure/argocd.md). The
FinSight chart reads image digests from [`image-tags.yaml`](gitops/apps/finsight/image-tags.yaml), and
that file changes only through a pull request.

Two decisions about DNS and TLS:
- **ExternalDNS runs in `upsert-only` mode with a TXT ownership registry.** It can create and update
  records, but it never deletes them.
- **TLS was validated against the Let's Encrypt staging issuer first.** Once staging issued a
  certificate, I switched to production. This lowered the risk of hitting production rate limits while
  debugging DNS or issuer settings, though it does not remove that risk.

More detail: [ingress](docs/infrastructure/ingress.md),
[DNS and certificates](docs/infrastructure/dns-and-certificates.md),
[load balancer controller](docs/infrastructure/load-balancer-controller.md).

## CI/CD

No AWS access keys are stored in GitHub. Every job that needs AWS assumes a narrowly scoped IAM role
through GitHub OIDC. The Terraform `github-oidc` module validates that each role trusts only this
repository and a named GitHub environment. The deployed trust statements were reviewed against
that on 20 October 2026, from a read-only capture taken on 18 October
([IAM review](docs/screenshots/eks/2026-10-20-iam-policy-review.md)).

### Terraform pipeline

On pull requests, [terraform.yml](.github/workflows/terraform.yml) runs `fmt`, `validate`, `test` and
Checkov across all roots, then plans the platform with a plan-only role.

[terraform-apply.yml](.github/workflows/terraform-apply.yml) is started manually from `main`. It has two
approval-protected environments:

1. **Plan.** The plan job saves the plan and encrypts it with [age](https://age-encryption.org) for the
   CI key. It also encrypts a readable copy for my reviewer key.
2. **Review.** I decrypt my copy locally and review the changes before approving the apply.
3. **Apply.** The apply job checks that the commit, run, backend, configuration, lock file and plan
   digests all match the reviewed plan. It then applies exactly that plan.

The apply refuses destructive changes unless an explicit input allows them. It always refuses changes to
the lifecycle of the VPC or the EKS cluster.

[Run 38901260888](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38901260888) went
through this process for a reviewed, tag-only change: 0 create, 1 update, 0 delete. The full design is
in [Terraform CI](docs/infrastructure/terraform-ci.md).

### Application pipeline

[app.yml](.github/workflows/app.yml) runs these stages:

1. Ruff and pytest against a real PostgreSQL service; frontend format check, tests and build.
2. Checkov across Terraform, the Dockerfiles and the rendered Kubernetes manifests.
3. Builds the API, ETL and frontend images. Trivy fails the build on any HIGH or CRITICAL vulnerability
   that has a fix available. Unfixed findings are reported but do not fail it.
4. On `main`, after approval in the `dev-images` environment: pushes the images to ECR, tagged with the
   commit SHA. The repositories have immutable tags.
5. Opens a pull request that updates the image digests in GitOps. Argo CD deploys them once it is merged.

[Run 38761479287](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38761479287) built the
images that ran on the cluster until the 20 October 2026 teardown; they were deployed through GitOps
PR #46. The pipeline is described in
[application pipeline](docs/infrastructure/app-pipeline.md).

## Deploying from scratch

Each step needs its own approval. The commands, checks and approval gates are in the
[runbook](docs/infrastructure/runbook.md); this is the order.

1. **Prepare and validate locally.** Create the git-ignored `infra/terraform/config/local.json`, run
   `scripts/validate-terraform.ps1` and generate the backend configuration
   ([runbook 1](docs/infrastructure/runbook.md#1-local-preparation-and-review)). Get approval for read-only account checks,
   then for provisioning ([runbook 2](docs/infrastructure/runbook.md#2-explicit-approval-gates)).
2. **Bootstrap.** Apply the state bucket with local state, then migrate that state into the bucket
   ([runbook 3](docs/infrastructure/runbook.md#3-bootstrap-local-state-first-then-s3-migration)).
3. **Foundation.** Plan, review and apply the ECR repositories, data bucket, GitHub OIDC provider and
   CI roles ([runbook 4](docs/infrastructure/runbook.md#4-foundation-then-platform)).
4. **Images.** Merge an application change to `main`. After approval in `dev-images`, the
   [application pipeline](#application-pipeline) publishes the images and opens the GitOps pull
   request that pins their digests. Merge it.
5. **Platform.** Plan, review and apply the VPC, NAT gateway, EKS cluster, nodes, add-ons and Pod
   Identity roles ([runbook 4](docs/infrastructure/runbook.md#4-foundation-then-platform)). I applied the first platform plan
   locally; later platform changes go through the [approval-gated apply](#terraform-pipeline).
6. **Cluster secrets.** Run `scripts/new-cluster-secrets.ps1`, which creates the database and
   Grafana Secrets outside Git
   ([Argo CD bootstrap](docs/infrastructure/argocd.md#bootstrap-during-a-deployment-window)).
7. **Argo CD.** Install Argo CD with Helm, replace the initial admin password, then render and apply
   the root Application. Argo CD installs the platform services and FinSight in sync-wave order
   ([Argo CD bootstrap](docs/infrastructure/argocd.md#bootstrap-during-a-deployment-window)).
8. **Verify.** Run the read-only checks
   ([runbook 5](docs/infrastructure/runbook.md#5-deployment-verification-carried-out-1618-october-2026)).

Teardown has its own ordered sequence, which removes controller-created load balancers, DNS records
and volumes before the Terraform destroy ([runbook 6](docs/infrastructure/runbook.md#6-precise-teardown-sequence)).

## Technology choices

| Area | Choice | Why |
|---|---|---|
| Infrastructure as code | Terraform 1.16.2, three roots, eleven local modules | Typed, tested modules; roots split so the costly platform can be destroyed alone |
| Kubernetes | Amazon EKS 1.36 with managed nodes in private subnets | Managed control plane and node lifecycle |
| Workload identity | EKS Pod Identity | One role per service account, no per-cluster OIDC provider |
| CI/CD | GitHub Actions with OIDC | No stored AWS keys; environment approvals gate plan, apply and publishing |
| Image registry | Amazon ECR with immutable tags | Images are pushed by commit SHA and deployed by digest |
| Image scanning | Trivy | Fails the build on fixable HIGH/CRITICAL findings |
| Policy scanning | Checkov | Scans Terraform, Dockerfiles and rendered manifests in CI |
| GitOps | Argo CD, app-of-apps | Git is the source of truth; drift is reverted |
| Ingress | F5 NGINX Ingress Controller behind an NLB | NGINX without the retired community controller |
| DNS and TLS | ExternalDNS and cert-manager with Let's Encrypt | Records and certificates follow the Ingress |
| Monitoring | kube-prometheus-stack | Prometheus, Grafana and alerting in one pinned chart |
| Database | PostgreSQL 17 StatefulSet | Cheapest reproducible option for synthetic data |

Each decision is recorded with its reason, the alternatives and its date in the
[decision index](docs/architecture/decisions.md).

## Application and data

| Component | Implementation |
|---|---|
| Frontend | React and Vite, served by unprivileged NGINX |
| API | FastAPI with read-only reporting endpoints (`/api/dashboard`, `/api/transactions`, `/api/departments`), health probes and `/metrics` |
| Database | PostgreSQL 17 StatefulSet on a gp3 EBS volume, with checksummed SQL migrations |
| ETL | Pandas: generated CSV → validated Parquet → PostgreSQL. Re-running it does not create duplicate data. |

In the cluster, an Argo CD Sync-hook Job runs before the API starts. It applies the migrations,
generates the dataset and loads it with the ETL. The database credentials are a Kubernetes Secret,
created outside Git by [`scripts/new-cluster-secrets.ps1`](scripts/new-cluster-secrets.ps1). The KPI
definitions are in [docs/kpi-definitions.md](docs/kpi-definitions.md).

## Monitoring

Monitoring uses kube-prometheus-stack 91.8.2. Prometheus keeps 2 days of data, capped at 3 GB. The
FinSight chart adds:
- a `ServiceMonitor` for the API;
- two alert rules, `FinSightApiDown` and `FinSightApiHighErrorRate`;
- a Grafana dashboard, provisioned from a ConfigMap.

NGINX is scraped through its own ServiceMonitor. Grafana and Prometheus have ClusterIP Services only, so
I reach them with `kubectl port-forward`. More detail: [monitoring](docs/infrastructure/monitoring.md).

## Limitations and planned work

- **ETL to S3: planned.** The data bucket and an ETL Pod Identity role exist, but the ETL still loads
  straight into PostgreSQL.
- **ELT with dbt: not started.** Only the contract in [`warehouse/dbt`](warehouse/dbt/README.md) exists.
- **No automated backups.** There was no recurring backup service for the in-cluster database;
  the data is synthetic and can be regenerated. Before the teardown on 20 October 2026 I took a
  PostgreSQL custom-format backup and restore-tested it in a separate database
  ([teardown evidence](docs/evidence/2026-10-20-platform-teardown.md#database-backup)).
- **Not highly available.** There is one NAT gateway and one PostgreSQL replica.
- **Frontend badge.** It still says "LOCAL ENVIRONMENT", a leftover from local development.
- **Next improvements.** Two NAT gateways for AZ resilience; Amazon RDS with automated backups in
  place of the in-cluster database; External Secrets with AWS Secrets Manager in place of
  out-of-band Secrets; kubeconform in CI alongside Checkov.

Verification notes and Terraform validation results are in [docs/evidence](docs/evidence).
Screenshots for each assessment area are indexed in [docs/screenshots](docs/screenshots/README.md).
Requirement-by-requirement status is in the [assessment tracker](docs/assessment-tracker.md).
I tracked the work as [GitHub Issues](https://github.com/Fer-as/finsight-eks-data-platform/issues) on the
[FinSight project board](https://github.com/users/Fer-as/projects/2).

## Running locally

You need Docker Desktop with Compose v2 and about 4 GB of memory allocated to Docker.

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
docker compose up --build -d --wait frontend
Start-Process 'http://localhost:5173'
```

Compose runs the migrations, data generation and ETL before it starts the API and frontend. The
`migrate`, `generate` and `etl` containers exit with code 0; that is expected. API docs are at
<http://localhost:8000/docs>.

To run all the tests, use [`scripts/verify.ps1`](scripts/verify.ps1):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

It runs the Python tests against a temporary PostgreSQL database, then the frontend tests and build,
then smoke checks.

Dataset parameters are in [`config/synthetic.json`](config/synthetic.json). Rebuild the images after
changing them, because the file is copied in at build time.

To stop, run `docker compose down`. Add `--volumes` to delete the local database as well.

## Repository layout

| Path | Contents |
|---|---|
| `apps/api`, `apps/frontend` | Application code, tests and Dockerfiles |
| `pipelines/` | Synthetic data generator and ETL |
| `warehouse/` | SQL migrations and the planned dbt contract |
| `infra/terraform/` | Terraform roots and modules |
| `gitops/` | Argo CD root, platform Applications and the FinSight Helm chart |
| `.github/workflows/` | Terraform and application pipelines |
| `scripts/` | Validation, CI helpers and operator scripts |
| `docs/` | Architecture, runbooks, evidence and assessment mapping |

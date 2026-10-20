# FinSight on Amazon EKS

FinSight is a financial analytics application built with React, FastAPI, PostgreSQL and a
Python/Pandas ETL. Its dashboard reports revenue, expenses, profit and margin, departmental budgets
against actual spending, and rule-based transaction-risk indicators, all from a deterministic
synthetic GBP dataset.

The application is intentionally small. Most of this repository is the platform that builds, secures,
deploys and monitors it on AWS:
- Amazon EKS in private subnets, provisioned with modular Terraform split into three roots by
  lifetime;
- GitHub Actions pipelines that authenticate to AWS through OIDC, with no stored keys;
- infrastructure changes applied only from an approved, encrypted saved plan;
- Argo CD (app-of-apps) deploying the application and its platform services from Git;
- F5 NGINX ingress behind a Network Load Balancer, with ExternalDNS, cert-manager and Let's Encrypt
  for DNS and TLS;
- Prometheus and Grafana for monitoring.

I built it as a practical implementation of cloud infrastructure, security, automation and
container orchestration, end to end.

> **Deployment status.** The platform ran on EKS in eu-west-2, at `eks.feras-dev.co.uk`, from 16 to
> 20 October 2026. I then destroyed it to stop its running costs
> ([teardown record](docs/evidence/2026-10-20-platform-teardown.md)). The cluster, the hostname and
> the dashboards are no longer online. The Terraform state, the container images in ECR, the CI
> identity, the code and the deployment evidence are retained.

## Contents

- [Architecture](#architecture)
- [Technology stack and design decisions](#technology-stack-and-design-decisions)
- [Infrastructure (Terraform)](#infrastructure-terraform)
- [CI/CD and GitOps](#cicd-and-gitops)
- [Application and data pipeline](#application-and-data-pipeline)
- [Monitoring and observability](#monitoring-and-observability)
- [Deployment and verification](#deployment-and-verification)
- [Running locally](#running-locally)
- [Repository structure](#repository-structure)
- [Limitations and future improvements](#limitations-and-future-improvements)
- [Further documentation](#further-documentation)

## Architecture

![FinSight architecture: AWS network, EKS, ingress, DNS/TLS, CI/CD, GitOps and monitoring](docs/architecture/finsight-architecture.png)

The diagram is an editable diagrams.net file,
[docs/architecture/finsight-architecture.drawio](docs/architecture/finsight-architecture.drawio). It has
three pages:
- the AWS overview;
- the Kubernetes platform ([PNG](docs/architecture/finsight-architecture-kubernetes.png));
- CI/CD with IAM ([PNG](docs/architecture/finsight-architecture-cicd.png)).

The labels were checked against the Terraform configuration and the flows against the code and
manifests ([diagram verification](docs/screenshots/architecture/2026-10-19-diagram-verification.md)).

A request travels:
1. from Route 53 to an internet-facing Network Load Balancer in the public subnets;
2. then to the F5 NGINX Ingress Controller;
3. then to the frontend or API pods on worker nodes in private subnets;
4. and finally to PostgreSQL, which runs in the cluster.

## Technology stack and design decisions

| Area | Choice | Why |
|---|---|---|
| Infrastructure as code | Terraform 1.16.2, three roots, eleven local modules | Typed, tested modules; roots split so the costly platform can be destroyed alone |
| Kubernetes | Amazon EKS 1.36 with managed nodes in private subnets | Managed control plane and node lifecycle |
| Workload identity | EKS Pod Identity | One role per service account, no per-cluster OIDC provider |
| CI/CD | GitHub Actions with OIDC | No stored AWS keys; environment approvals gate plan, apply and publishing |
| Image registry | Amazon ECR with immutable tags | Images are pushed by commit SHA and deployed by digest |
| Image scanning | Trivy | Fails the build on fixable HIGH/CRITICAL findings |
| Policy scanning | Checkov | Scans Terraform, Dockerfiles, rendered manifests and workflows in CI |
| GitOps | Argo CD, app-of-apps | Git is the source of truth; drift is reverted |
| Ingress | F5 NGINX Ingress Controller behind an NLB | NGINX without the retired community controller |
| DNS and TLS | ExternalDNS and cert-manager with Let's Encrypt | Records and certificates follow the Ingress |
| Monitoring | kube-prometheus-stack | Prometheus, Grafana and alert rules in one pinned chart |
| Database | PostgreSQL 17 StatefulSet | Cheapest reproducible option for synthetic data |

EKS was chosen to work with Kubernetes and the platform around it. A synthetic reporting application
of this size does not need Kubernetes, and a single managed container service would cost less to run
it. Each decision is recorded with its reason, the alternatives considered and its date in the
[decision index](docs/architecture/decisions.md).

## Infrastructure (Terraform)

The Terraform uses version 1.16.2, with the AWS provider pinned to 6.59.0 and checksum lock files in
every root. Setup and configuration are in [infra/terraform](infra/terraform/README.md).

| Root | Contents | Lifetime |
|---|---|---|
| [`bootstrap`](infra/terraform/bootstrap) | Encrypted, versioned state bucket and its access-log bucket | Permanent |
| [`environments/dev/foundation`](infra/terraform/environments/dev/foundation) | ECR repositories, data bucket, GitHub OIDC provider and CI roles | Kept when the cluster is rebuilt |
| [`environments/dev/platform`](infra/terraform/environments/dev/platform) | VPC, NAT gateway, flow logs, EKS, node group, add-ons and Pod Identity roles | Disposable |

Each root has its own S3 state key and uses S3 native locking. The roots are split by lifetime:
- The expensive, short-lived resources (the NAT gateway and EKS) are in `platform`, which can be
  destroyed without touching the state bucket, the image repositories or the CI identity.
- The roots don't read each other's state. Shared names come from a single `config` module.

The roots are built from eleven local [modules](infra/terraform/modules), including `network`, `eks`,
`ecr`, `github-oidc` and `pod-role`. Their inputs are typed and validated, and eight of the modules
have `terraform test` suites.

### Network, identity and secrets

- **Single NAT gateway.** It costs less than one per AZ. The trade-off is that the private subnets
  lose outbound access if eu-west-2a fails, which is acceptable for a development environment
  ([costs](docs/infrastructure/costs.md)).
- **Private worker nodes.**
  - Nodes run only in private subnets, with IMDSv2 required and encrypted root volumes.
  - The EKS API endpoint is public but limited to configured CIDR ranges.
  - On the deployed cluster I checked that the endpoint was not open to `0.0.0.0/0`, that no node had
    a public IP, and that the node group had no SSH access
    ([network security](docs/infrastructure/network-security.md)).
- **EKS Pod Identity.**
  - The load balancer controller, ExternalDNS and cert-manager each have their own IAM role, tied to
    one service account.
  - The two DNS controllers can change records only in the FinSight hosted zone
    ([DNS and certificates](docs/infrastructure/dns-and-certificates.md),
    [load balancer controller](docs/infrastructure/load-balancer-controller.md)).
  - Every role created by the platform carries a permissions boundary.
  - I reviewed every role's trust, boundary and policy statements against Terraform on 20 October
    2026 ([IAM review](docs/screenshots/eks/2026-10-20-iam-policy-review.md)).
- **Ingress only through the NLB.**
  - The NLB has its own security group, which can reach only the ingress controller's pod ports.
  - The deployed security groups were checked against the rule set on 18 October 2026
    ([network security](docs/infrastructure/network-security.md),
    [evidence](docs/screenshots/eks/2026-10-18-network-iam-security-verification.md#g024-security-groups-every-group-in-the-vpc)).
- **Secrets outside Git.** The database and Grafana credentials are Kubernetes Secrets, created
  before the first sync by [`scripts/new-cluster-secrets.ps1`](scripts/new-cluster-secrets.ps1)
  and referenced by name. A secret scan of the tree and the full Git history found no credentials
  ([secret scan](docs/evidence/2026-10-20-secret-scan.md)).

## CI/CD and GitOps

No AWS access keys are stored in GitHub. Every job that needs AWS assumes a narrowly scoped IAM role
through GitHub OIDC. The Terraform `github-oidc` module validates that each role trusts only this
repository and a named GitHub environment.

### Terraform pipeline

On pull requests, [terraform.yml](.github/workflows/terraform.yml) runs `fmt`, `validate`, `test` and
Checkov across all roots, then plans the platform with a plan-only role.

[terraform-apply.yml](.github/workflows/terraform-apply.yml) is started manually from `main` and has two
approval-protected environments:
1. **Plan.** The plan job saves the plan and encrypts it with [age](https://age-encryption.org) for
   the CI key. It also encrypts a readable copy for my reviewer key.
2. **Review.** I decrypt my copy locally and review the changes before approving the apply.
3. **Apply.** The apply job checks that the commit, run, backend, configuration, lock file and plan
   digests all match the reviewed plan. It then applies exactly that plan.

The apply refuses destructive changes unless an explicit input allows them. It always refuses changes
to the lifecycle of the VPC or the EKS cluster.

[Run 38901260888](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38901260888) went
through this process for a reviewed, tag-only change: 0 create, 1 update, 0 delete. The bootstrap,
foundation and first platform applies were run by hand, from reviewed saved plans. The full design is
in [Terraform CI](docs/infrastructure/terraform-ci.md).

### Application pipeline

[app.yml](.github/workflows/app.yml) runs these stages:
1. Ruff and pytest against a real PostgreSQL service; frontend format check, tests and build.
2. Checkov across Terraform, the Dockerfiles and the rendered Kubernetes manifests.
3. Builds the API, ETL and frontend images. Trivy fails the build on any HIGH or CRITICAL
   vulnerability that has a fix available. Unfixed findings are reported but do not fail it.
4. On `main`, after approval in the `dev-images` environment: pushes the images to ECR, tagged with
   the commit SHA. The repositories have immutable tags.
5. Opens a pull request that updates the image digests in GitOps. Argo CD deploys them once it is
   merged.

[Run 38761479287](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38761479287) built
the images that ran on the cluster; they were deployed through GitOps PR #46. Image publishing is now
switched off, because there is no cluster to deploy to. The pipeline is described in
[application pipeline](docs/infrastructure/app-pipeline.md).

The gates were also tested with deliberate failures. A Terraform formatting error, a failing unit test
and a vulnerable base image each stopped their pipeline, with publishing skipped
([failing runs](docs/screenshots/cicd/2026-10-20-deliberate-failing-runs.md)).

One of those runs also exposed two fixable HIGH vulnerabilities, published after the last image build,
in the frontend's pinned base image. The source now pins the upstream rebuild of the same tag, which
passes the Trivy gate. The image that ran on EKS was built before that fix and was not rebuilt.

### Workflow and GitOps validation

Two further read-only workflows check changes that the deployment pipelines would not exercise. Neither
has AWS credentials, an OIDC token or cluster access.
- [workflows.yml](.github/workflows/workflows.yml) runs when a workflow changes, including the
  manually started apply workflow:
  - [`scripts/check-workflows.py`](scripts/check-workflows.py) checks that every workflow has no
    default permissions, pins actions to full commit SHAs, and requests OIDC tokens only behind a
    protected environment;
  - it confirms that the plan, apply and publishing gates are intact;
  - it runs Checkov's GitHub Actions checks and the saved-plan protection tests.
- [gitops.yml](.github/workflows/gitops.yml) runs when `gitops/` or its tests change. It uses
  [`scripts/validate-gitops.ps1`](scripts/validate-gitops.ps1), the same script used locally, with
  tools pinned by digest:
  - renders the Argo CD root Application and the Helm and Kustomize output;
  - validates the manifests with kubeconform against Kubernetes 1.36 schemas;
  - checks the alert rules and dashboard queries with promtool;
  - runs the `tests/gitops` suite, and fails if any test fails or is skipped.

### Argo CD

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

All chart versions are pinned. Automated sync runs with `prune` and `selfHeal`, so manual changes in
the cluster are reverted; the drift test is in the [Argo CD runbook](docs/infrastructure/argocd.md).
The FinSight chart reads image digests from
[`image-tags.yaml`](gitops/apps/finsight/image-tags.yaml), and that file changes only through a pull
request.

DNS and TLS:
- **ExternalDNS runs in `upsert-only` mode with a TXT ownership registry.** It can create and update
  records, but it never deletes them.
- **TLS was validated against the Let's Encrypt staging issuer first.** Once staging issued a
  certificate, I switched to production. That lowered the risk of hitting production rate limits
  while debugging DNS or issuer settings.

More detail: [ingress](docs/infrastructure/ingress.md),
[DNS and certificates](docs/infrastructure/dns-and-certificates.md),
[load balancer controller](docs/infrastructure/load-balancer-controller.md).

## Application and data pipeline

| Component | Implementation |
|---|---|
| Frontend | React and Vite, served by unprivileged NGINX |
| API | FastAPI with read-only reporting endpoints (`/api/dashboard`, `/api/transactions`, `/api/departments`), health probes and `/metrics` |
| Database | PostgreSQL 17 StatefulSet on an encrypted gp3 EBS volume, with checksummed SQL migrations |
| ETL | Pandas: generated CSV → validated Parquet → PostgreSQL. Re-running it does not create duplicate data. |

In the cluster, an Argo CD Sync-hook Job ran before the API started: it applied the migrations,
generated the dataset and loaded it with the ETL. Every dataset is generated from a fixed seed, so the
same configuration always produces the same data ([data statement](data/README.md#data-statement)).
The KPI definitions are in [docs/kpi-definitions.md](docs/kpi-definitions.md). Eight dashboard
figures were checked against SQL totals
([KPI check](docs/evidence/2026-10-20-kpi-sql-check.md)).

Database roles:
- **Locally and in CI**, the components use separate PostgreSQL roles: the migrations and ETL run as
  a writer role, and the API as a read-only reader that cannot write, run DDL or change roles. These
  are tested against a real PostgreSQL server
  ([database roles](docs/infrastructure/database-roles.md)).
- **The EKS deployment** used a single shared database role, from the Secret described above.

## Monitoring and observability

Monitoring uses kube-prometheus-stack 91.8.2. Prometheus keeps 2 days of data, capped at 3 GB. The
FinSight chart adds:
- a `ServiceMonitor` for the API;
- two alert rules, `FinSightApiDown` and `FinSightApiHighErrorRate`;
- a Grafana dashboard, provisioned from a ConfigMap.

NGINX is scraped through its own ServiceMonitor. Grafana and Prometheus have ClusterIP Services only,
and were reached with `kubectl port-forward`.

After the teardown, I corrected two dashboard panels:
- the 5xx ratio now shows zero when there are no errors, instead of "No data";
- the ingress panels now group by NGINX upstream.

Both corrections are tested offline with promtool, but have not been seen on a live cluster. More
detail: [monitoring](docs/infrastructure/monitoring.md).

## Deployment and verification

The deployment was verified on 16–18 October 2026:

| Area | State |
|---|---|
| EKS | Kubernetes 1.36 cluster `finsight-dev`; two `m7i-flex.large` nodes Ready, one in eu-west-2a and one in eu-west-2b |
| GitOps | Eight Argo CD Applications (a root app and seven children), all Synced and Healthy |
| Ingress, DNS and TLS | NGINX behind an NLB; ExternalDNS managed the Route 53 records; Let's Encrypt production certificate from cert-manager; HTTP redirected to HTTPS |
| Application | API, frontend and PostgreSQL running; images pulled from ECR by digest |
| Monitoring | Prometheus scrape targets up, including the API and NGINX; FinSight dashboard in Grafana. After OOMKilled restarts, Grafana's memory was raised on 19 October 2026 (PR #57) and its dashboards were re-checked |

Screenshots and command-output notes from the deployment are indexed in the
[evidence index](docs/screenshots/README.md).

### Deploying from scratch

Each step needs its own approval. The commands, checks and approval gates are in the
[runbook](docs/infrastructure/runbook.md); this is the order:
1. **Prepare and validate locally.** Create the git-ignored `infra/terraform/config/local.json`, run
   `scripts/validate-terraform.ps1` and generate the backend configuration
   ([runbook 1](docs/infrastructure/runbook.md#1-local-preparation-and-review)). Get approval for
   read-only account checks, then for provisioning
   ([runbook 2](docs/infrastructure/runbook.md#2-explicit-approval-gates)).
2. **Bootstrap.** Apply the state bucket with local state, then migrate that state into the bucket
   ([runbook 3](docs/infrastructure/runbook.md#3-bootstrap-local-state-first-then-s3-migration)).
3. **Foundation.** Plan, review and apply the ECR repositories, data bucket, GitHub OIDC provider and
   CI roles ([runbook 4](docs/infrastructure/runbook.md#4-foundation-then-platform)).
4. **Images.** Merge an application change to `main`. After approval in `dev-images`, the
   [application pipeline](#application-pipeline) publishes the images and opens the GitOps pull
   request that pins their digests. Merge it.
5. **Platform.** Plan, review and apply the VPC, NAT gateway, EKS cluster, nodes, add-ons and Pod
   Identity roles ([runbook 4](docs/infrastructure/runbook.md#4-foundation-then-platform)). I applied
   the first platform plan locally; later platform changes went through the
   [approval-gated apply](#terraform-pipeline).
6. **Cluster secrets.** Run `scripts/new-cluster-secrets.ps1`, which creates the database and
   Grafana Secrets outside Git
   ([Argo CD bootstrap](docs/infrastructure/argocd.md#bootstrap-during-a-deployment-window)).
7. **Argo CD.** Install Argo CD with Helm, replace the initial admin password, then render and apply
   the root Application. Argo CD installs the platform services and FinSight in sync-wave order
   ([Argo CD bootstrap](docs/infrastructure/argocd.md#bootstrap-during-a-deployment-window)).
8. **Verify.** Run the read-only checks
   ([runbook 5](docs/infrastructure/runbook.md#5-deployment-verification-carried-out-1618-october-2026)).

### Teardown

On 20 October 2026 I removed the platform in dependency order
([runbook 6](docs/infrastructure/runbook.md#6-precise-teardown-sequence)):
1. A PostgreSQL backup was taken and restore-tested in a separate database.
2. Argo CD reconciliation was stopped.
3. The applications were removed, so the controllers deleted the load balancer and the database
   volume.
4. The ExternalDNS records were removed.
5. A reviewed saved plan destroyed the 68 platform resources.

Read-only checks then found no remaining platform resources. The state, data and log buckets, the ECR
repositories and the CI identity were confirmed intact
([teardown record](docs/evidence/2026-10-20-platform-teardown.md)).

## Running locally

You need Docker Desktop with Compose v2 and about 4 GB of memory allocated to Docker.

```powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
docker compose up --build -d --wait frontend
Start-Process 'http://localhost:5173'
```

Compose creates the database roles, then runs the migrations, data generation and ETL before it
starts the API and frontend. The `roles`, `migrate`, `generate` and `etl` containers exit with code
0; that is expected. API docs are at <http://localhost:8000/docs>.

To run all the tests, use [`scripts/verify.ps1`](scripts/verify.ps1):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

It runs the Python tests against a temporary PostgreSQL database, then the frontend tests and build,
then smoke checks.

Dataset parameters are in [`config/synthetic.json`](config/synthetic.json). Rebuild the images after
changing them, because the file is copied in at build time.

To stop, run `docker compose down`. Add `--volumes` to delete the local database as well.

## Repository structure

| Path | Contents |
|---|---|
| [`apps/api`](apps/api), [`apps/frontend`](apps/frontend) | Application code, tests and Dockerfiles |
| [`pipelines/`](pipelines) | Synthetic data generator and ETL |
| [`warehouse/`](warehouse) | SQL migrations and the planned dbt contract |
| [`config/`](config) | Synthetic dataset parameters |
| [`infra/terraform/`](infra/terraform) | Terraform roots and modules |
| [`gitops/`](gitops) | Argo CD root, platform Applications and the FinSight Helm chart |
| [`.github/workflows/`](.github/workflows) | Terraform, application, GitOps-validation and workflow-policy pipelines |
| [`scripts/`](scripts) | Validation, CI helpers and operator scripts |
| [`tests/`](tests) | PostgreSQL integration tests and offline GitOps tests |
| [`compose.yaml`](compose.yaml) | Local stack: PostgreSQL, migrations, data generation, ETL, API, frontend and a test service |
| [`docs/architecture/`](docs/architecture) | Diagram source and exports, decision index |
| [`docs/infrastructure/`](docs/infrastructure) | Runbook and design notes for each platform component |
| [`docs/evidence/`](docs/evidence), [`docs/screenshots/`](docs/screenshots/README.md) | Command-output notes and screenshots from the deployment |

## Limitations and future improvements

The deployment (16–20 October 2026) had these limits:
- **Cost-conscious, not highly available.**
  - There was one NAT gateway.
  - The API, the frontend and PostgreSQL each ran one replica, with no PodDisruptionBudgets.
  - Losing a node, or eu-west-2a, would have interrupted the service.
- **No automated backups.** There was no recurring backup service for the in-cluster database; the
  data is synthetic and can be regenerated. Before the teardown I took a PostgreSQL custom-format
  backup and restore-tested it
  ([teardown record](docs/evidence/2026-10-20-platform-teardown.md#database-backup)).
- **No pod-level network policies.**
  - No Kubernetes NetworkPolicy was applied, and VPC CNI network-policy enforcement was not enabled,
    so traffic between pods was not restricted.
  - The database and monitoring were reachable only through ClusterIP Services, and inbound traffic
    only through the NLB and its security group.
- **Secrets created by hand.** The Kubernetes Secrets came from
  [`scripts/new-cluster-secrets.ps1`](scripts/new-cluster-secrets.ps1), not from a secrets manager.
- **One database role in Kubernetes.** The separate writer and reader roles are used locally and in
  CI, but not yet in the FinSight chart
  ([database roles](docs/infrastructure/database-roles.md#where-it-runs)).
- **Alerts were not delivered.** Prometheus evaluated the alert rules, but there was no Alertmanager.
  Metrics were kept on node storage (`emptyDir`), with no persistent volume.
- **First provisioning by hand.** Bootstrap, foundation and the first platform plan were applied from
  my workstation, from reviewed saved plans. Later platform changes went through the approval-gated
  CI apply.
- **Data pipeline.**
  - The data bucket and an ETL Pod Identity role exist, but the ETL loads straight into PostgreSQL;
    staging through S3 is planned.
  - The dbt ELT path has not been started; only its contract in
    [`warehouse/dbt`](warehouse/dbt/README.md) exists.

Future improvements:
- two NAT gateways and two or more replicas per application, with PodDisruptionBudgets;
- Amazon RDS with automated backups, in place of the in-cluster database;
- External Secrets with AWS Secrets Manager;
- NetworkPolicies with VPC CNI enforcement enabled;
- Alertmanager with a real receiver, and persistent Prometheus storage;
- the separate database roles in the FinSight chart.

## Further documentation

- **Design and operation:** [docs/infrastructure](docs/infrastructure) has the
  [runbook](docs/infrastructure/runbook.md) and a design note for each platform component.
  [docs/architecture/decisions.md](docs/architecture/decisions.md) records the design decisions.
- **Deployment evidence:** command-output notes are in [docs/evidence](docs/evidence), and
  screenshots in the [evidence index](docs/screenshots/README.md).
- **Planning:** the work was planned and tracked as
  [GitHub Issues](https://github.com/Fer-as/finsight-eks-data-platform/issues) on the
  [project board](https://github.com/users/Fer-as/projects/2).

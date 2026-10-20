# Architecture diagram verification (G09, R2), 19 October 2026

Checks run on 19 October 2026 against
[`docs/architecture/finsight-architecture.drawio`](../../architecture/finsight-architecture.drawio) at
commit `c63f003`.

## Opens and is editable (G09.1, R2.1)

- draw.io desktop 1.73, run headless and offline, opened the source and exported all three pages.
- Each exported PNG is pixel-identical to the committed export:
  [overview](../../architecture/finsight-architecture.png),
  [Kubernetes](../../architecture/finsight-architecture-kubernetes.png) and
  [CI/CD and IAM](../../architecture/finsight-architecture-cicd.png).
- The file is uncompressed mxGraph XML with unique IDs, and every connector has a valid source and
  target.

| Page | Shapes | From the AWS / Kubernetes libraries | Connectors | Layers |
|---|---:|---|---:|---:|
| 1. Overview | 91 | 22 / 8 | 32 | 8 |
| 2. Kubernetes platform | 62 | 0 / 19 | 23 | 5 |
| 3. CI/CD, IAM and data | 50 | 13 / 2 | 19 | 4 |

## Labels match Terraform (G09.2, R2.2)

Every network value in `infra/terraform/config/defaults.json` appears in the diagram:
- Region eu-west-2, and AZs eu-west-2a and eu-west-2b;
- VPC 10.42.0.0/16;
- public subnets 10.42.0.0/24 and 10.42.1.0/24;
- private subnets 10.42.16.0/20 and 10.42.32.0/20.

The internet gateway, the single NAT gateway, the routes and the S3 gateway endpoint are drawn.

Node type:
- **Committed default:** `infra/terraform/config/defaults.json` sets `m7i.large`.
- **Deployed:** the node group runs `m7i-flex.large`, set by an override in the git-ignored local
  configuration.

The diagram shows the deployed `m7i-flex.large`. The two types have the same CPU, memory and network
limits; see `docs/infrastructure/compatibility.md`.

## Components present (G09.3, G09.4, R2.3)

The diagram contains:
- EKS, the F5 NGINX Ingress Controller and the NLB;
- Route 53, ExternalDNS, cert-manager and Let's Encrypt;
- the cluster, node and Pod Identity IAM roles, the GitHub OIDC provider and roles, and both pipelines;
- ECR, Argo CD, Prometheus and Grafana.

The status banner records the deployment verified on 16–17 October 2026. ETL to S3 and dbt are the only
items marked planned.

## Flows with a legend (G09.5, R2.4)

The legend lists seven numbered flows, each on its own layer. Each traces to code or manifests:

| Flow | Traces to |
|---|---|
| 1 User request | Route 53 → NLB → NGINX → frontend or API; `gitops/apps/finsight/templates/ingress.yaml` |
| 2 Outbound via NAT | `infra/terraform/modules/network` routes |
| 3 Application CI/CD and GitOps | `.github/workflows/app.yml` → ECR → `image-tags.yaml` → Argo CD |
| 4 Infrastructure CI, including GitHub OIDC trust | `.github/workflows/terraform.yml`, `terraform-apply.yml`, `modules/github-oidc` |
| 5 Data / ETL | S3 raw/ and curated/ drawn as **planned**; the PostgreSQL initialisation Job is deployed |
| 6 DNS and TLS automation | `gitops/platform/external-dns`, `cert-manager`, `cluster-issuers` |
| 7 Metrics scraping | ServiceMonitors in `gitops/apps/finsight/templates/monitoring.yaml` and `gitops/platform/monitoring` |

Known cosmetic issue: on page 3, two flow labels, "4 OIDC AssumeRoleWithWebIdentity" and "4 approved
apply", overlap.

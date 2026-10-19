# Evidence

Evidence from the live FinSight deployment in eu-west-2 and its GitHub Actions runs, captured on 14–19
October 2026. It has two forms:
- screenshots;
- command-output notes (`*.md`), which record the exact commands and their results.

The **Type** column marks each item as one of:
- **Deployment**: the system working as intended.
- **Safety control**: a guard such as an approval gate, a rejected login, or reverted drift.

Requirement IDs refer to the [reviewer checklist](../reviewer-acceptance-checklist.md).

**Redactions.** Some details are hidden with flattened grey boxes or crops:
- the AWS account ID (in URIs and ARNs) and the console account menu;
- the EKS API endpoint, OIDC and certificate-authority values;
- subnet IDs and the load balancer hostname;
- local Windows paths and browser tracking parameters.

Nothing else was edited.

## G01 Project management

| Evidence | Demonstrates | Type |
|---|---|---|
| [github-project-board-current.png](board/github-project-board-current.png) | The [project board](https://github.com/users/Fer-as/projects/2) as it was on 17 October 2026, with Backlog, Todo, In Progress, Review and Done columns and PR-linked cards | Deployment |

This screenshot shows the board exactly as it was on 17 October 2026, with some card statuses not yet
updated. It is a single snapshot, not a finished board or a series showing progress over time. Dated start,
middle and end snapshots (G01.5) were not captured.

## G02 Terraform and EKS

| Evidence | Demonstrates | Type |
|---|---|---|
| [eks-cluster-active.png](eks/eks-cluster-active.png) | Cluster `finsight-dev` Active on Kubernetes 1.36 with standard support; 1 node group, 5 add-ons, no health issues | Deployment |
| [eks-node-group-details.png](eks/eks-node-group-details.png) | Managed node group Active: `m7i-flex.large`, 2 nodes (min 2, max 3), on-demand, remote access off | Deployment |
| [eks-five-addons-active.png](eks/eks-five-addons-active.png) | EBS CSI driver, Pod Identity Agent, VPC CNI, CoreDNS and kube-proxy all Active | Deployment |
| [2026-10-16-eks-deployment.md](eks/2026-10-16-eks-deployment.md) | Terraform apply of the platform root (68 resources); `kubectl` shows two nodes Ready in eu-west-2a and eu-west-2b | Deployment |
| [2026-10-18-network-iam-security-verification.md](eks/2026-10-18-network-iam-security-verification.md) | Read-only live checks (18 October 2026): subnets, routes, NAT, S3 endpoint and flow logs; private nodes without public IPs, IMDSv2 and encrypted gp3 volumes; IAM roles with policy names, boundaries and trust (statements not compared line by line); every security-group rule | Deployment |

## G03 NGINX Ingress

| Evidence | Demonstrates | Type |
|---|---|---|
| [http-redirect-and-404.png](app/http-redirect-and-404.png) | HTTP returns `301` to HTTPS from NGINX; unknown frontend and API paths return `404` | Safety control |
| [2026-10-16-nlb-verification.md](app/2026-10-16-nlb-verification.md) | Application reached through the internet-facing NLB and NGINX Ingress Controller | Deployment |
| [2026-10-18-network-iam-security-verification.md](eks/2026-10-18-network-iam-security-verification.md#g032-load-balancer-and-workload-placement) | NLB in exactly the two public subnets, IP targets healthy; FinSight and NGINX pods on private nodes | Deployment |

## G04 cert-manager and ExternalDNS

| Evidence | Demonstrates | Type |
|---|---|---|
| [route53-externaldns-records.png](app/route53-externaldns-records.png) | Route 53 A and AAAA alias records for `eks.feras-dev.co.uk`, with the ExternalDNS TXT ownership records | Deployment |
| [finsight-cert-manager-ready.png](app/finsight-cert-manager-ready.png) | `finsight-tls-production` Certificate Ready; staging and production ClusterIssuers Ready | Deployment |
| [finsight-https-certificate.png](app/finsight-https-certificate.png) | Browser trusts the Let's Encrypt certificate for `eks.feras-dev.co.uk`, valid until 14 January 2027 | Deployment |
| [2026-10-16-tls.md](app/2026-10-16-tls.md), [2026-10-16-dns-and-http.md](app/2026-10-16-dns-and-http.md) | Issuance from staging, then production; DNS resolution and HTTP checks | Deployment |

## G05 Monitoring

| Evidence | Demonstrates | Type |
|---|---|---|
| [finsight-grafana-dashboard.png](monitoring/finsight-grafana-dashboard.png) | FinSight dashboard with live data: API requests and latency by route, NGINX status codes and latency, pod CPU and memory | Deployment |
| [prometheus-nginx-targets.png](monitoring/prometheus-nginx-targets.png) | Prometheus targets UP: NGINX controller, node-exporter, kube-state-metrics | Deployment |
| [prometheus-targets-2026-10-16.png](monitoring/prometheus-targets-2026-10-16.png) | Prometheus *Target health*: the FinSight API target (`serviceMonitor/finsight/finsight-api`) 1/1 UP, with the Grafana, API server (2/2) and CoreDNS (2/2) targets UP. Endpoint addresses and `instance` labels are redacted | Deployment |
| [grafana-default-login-rejected.png](monitoring/grafana-default-login-rejected.png) | Grafana rejects the default `admin` password; credentials come from a Kubernetes Secret, and Grafana is reachable only by port-forward | Safety control |
| [2026-10-16-g05-verification.md](monitoring/2026-10-16-g05-verification.md), [2026-10-16-prometheus-targets.md](monitoring/2026-10-16-prometheus-targets.md) | Install, target and alert-rule verification | Deployment |
| [2026-10-18-g05-metrics-verification.md](monitoring/2026-10-18-g05-metrics-verification.md) | Prometheus queries (18 October 2026): 20 of 20 targets up; non-empty node, namespace and pod CPU and memory series | Deployment |
| [g05-node-cpu-memory-2026-10-19.png](monitoring/g05-node-cpu-memory-2026-10-19.png) | *Node Exporter / Nodes*, last hour (UTC): CPU usage, load average, memory and disk for one worker node. The node's private address is redacted | Deployment |
| [g05-cluster-cpu-memory-2026-10-19.png](monitoring/g05-cluster-cpu-memory-2026-10-19.png) | *Kubernetes / Compute Resources / Cluster*: cluster CPU and memory utilisation and commitments, with CPU and memory by namespace | Deployment |
| [g05-finsight-pod-cpu-memory-2026-10-19.png](monitoring/g05-finsight-pod-cpu-memory-2026-10-19.png) | *Kubernetes / Compute Resources / Namespace (Pods)* for `finsight`: CPU and memory per pod (API, frontend, PostgreSQL) against requests and limits | Deployment |
| [g05-finsight-service-overview-2026-10-19.png](monitoring/g05-finsight-service-overview-2026-10-19.png) | *FinSight / Service overview*: API requests by route and p95 latency, ingress requests per second by Service, pod CPU and memory. The *API 5xx ratio* panel shows "No data" and the *Ingress p95 upstream latency by Service* panel is empty, so this screenshot does not show error rates or complete upstream latency | Deployment |
| [2026-10-19-grafana-oom-recovery.md](monitoring/2026-10-19-grafana-oom-recovery.md) | Grafana OOMKilled restarts fixed by a GitOps memory change (PR #57) and the rollout verified | Deployment |

## G06 Terraform pipeline

The four `terraform-apply-*` screenshots follow one protected apply,
[run 38901260888](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38901260888), in order.

| Evidence | Demonstrates | Type |
|---|---|---|
| [terraform-pr53-plan-success.png](cicd/terraform-pr53-plan-success.png) | PR #53 checks: fmt, validate, test and Checkov, then a plan with the plan-only role, after `dev-infrastructure` approval ([run 38896532913](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38896532913)) | Safety control |
| [terraform-apply-01-plan-approval-gate.png](cicd/terraform-apply-01-plan-approval-gate.png) | Apply workflow started manually on `main`; planning waits for `dev-infrastructure` approval | Safety control |
| [terraform-apply-02-plan-summary-apply-gate.png](cicd/terraform-apply-02-plan-summary-apply-gate.png) | Saved plan: 0 create, 1 update, 0 delete. The apply job waits for `dev-infrastructure-apply` approval | Safety control |
| [terraform-apply-03-review-digests.png](cicd/terraform-apply-03-review-digests.png) | Values checked against the decrypted review copy before approval: commit, state key, plan and changes SHA-256, encrypted file hashes, `allow_destroy: false` | Safety control |
| [terraform-apply-04-success.png](cicd/terraform-apply-04-success.png) | Both jobs succeeded; exactly the reviewed plan was applied | Deployment |
| [cloudwatch-changeevidence-tag.png](cicd/cloudwatch-changeevidence-tag.png) | The applied change in AWS: the flow-log group carries `ChangeEvidence = g06-protected-apply` | Deployment |
| [2026-10-16-g06-terraform-ci-audit.md](cicd/2026-10-16-g06-terraform-ci-audit.md) | Workflow, environment and drift audit, written before the apply was run | Deployment |

> **"Delete 1" in `terraform-pr53-plan-success.png` is simulated test data.** The table under
> *fmt, validate, test and Checkov* has `Delete = 1`, commit `1111…` and a `/tmp/plan-protection-tests-…`
> path. It comes from `scripts/ci/tests/plan-protection.tests.ps1`, which feeds a synthetic plan to the
> safety gate to prove that destructive changes are refused. It is not a real plan, and nothing in AWS
> was deleted.

## G07 Application pipeline

| Evidence | Demonstrates | Type |
|---|---|---|
| [github-actions-ecr-publish-success.png](cicd/github-actions-ecr-publish-success.png) | [Run 38761479287](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38761479287) on `main`: Python and frontend tests, Checkov, three image builds with Trivy, ECR publish through OIDC, and the GitOps PR | Deployment |
| [ecr-immutable-repositories.png](cicd/ecr-immutable-repositories.png) | Three ECR repositories with immutable tags and AES-256 encryption | Safety control |
| [ecr-api-image.png](cicd/ecr-api-image.png) | API image tagged with commit SHA `6e77c47…` and stored with its digest | Deployment |
| [gitops-image-pr-merged.png](cicd/gitops-image-pr-merged.png) | PR #46, opened by `github-actions`, pins the published digests and is merged | Deployment |
| [2026-10-16-g07-deployed-digests.md](cicd/2026-10-16-g07-deployed-digests.md) | The digests running on EKS match the digests published to ECR | Deployment |

## G08 Argo CD

| Evidence | Demonstrates | Type |
|---|---|---|
| [argocd-8-applications-synced-healthy.png](argocd/argocd-8-applications-synced-healthy.png) | All eight Applications Synced and Healthy, with pinned chart versions | Deployment |
| [argocd-automatic-sync-history.png](argocd/argocd-automatic-sync-history.png) | Merges to `main` (PRs #47, #50, #51) deployed by the automated sync policy | Deployment |
| [argocd-self-healing-events.png](argocd/argocd-self-healing-events.png), [2026-10-16-self-heal.md](argocd/2026-10-16-self-heal.md) | Controlled drift on the frontend Deployment, reverted to the Git state | Safety control |
| [2026-10-16-argocd-install.md](argocd/2026-10-16-argocd-install.md), [2026-10-16-gitops-deployment.md](argocd/2026-10-16-gitops-deployment.md) | Pinned install, then root and child Applications deployed by sync wave | Deployment |

## G09 Architecture

- Editable source: [finsight-architecture.drawio](../architecture/finsight-architecture.drawio)
- PNG exports: [overview](../architecture/finsight-architecture.png),
  [Kubernetes](../architecture/finsight-architecture-kubernetes.png) and
  [CI/CD and IAM](../architecture/finsight-architecture-cicd.png)

The diagram's status banner records the deployment verified on 16–17 October 2026. ETL to S3 and
dbt are shown as planned.

## Not yet evidenced

- **G01.5:** dated board snapshots at the start, middle and end of the work.
- **G04.3:** a demonstrated certificate renewal. cert-manager has scheduled renewal for 15 December
  2026, but a renewal has not been forced.
- **G04.5:** DNS records updated or removed when the Ingress changes (before and after listings).
- **G06.6:** a deliberate failing Terraform run, such as a rejected destructive plan. One unplanned
  failure is on record: [run 38887295294](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38887295294)
  failed at `terraform init` because of a configuration encoding problem, which was then fixed.
- **G02.3:** a line-by-line comparison of the IAM policy statements with the documented scope.
- **G07.8:** failing application runs, where a failing test and a security finding each stop publishing.
- **R3.1-R3.3:** the final demo video.
- **R12:** platform teardown and the actual cost record.

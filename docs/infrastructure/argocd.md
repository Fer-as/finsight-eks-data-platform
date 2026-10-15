# Argo CD GitOps (G08)

Status, 15 October 2026: **implemented and validated locally; not installed.** No cluster
currently exists. Nothing below has been run against EKS. Live evidence is listed at the end.

## Versions

| Component | Pin | Why |
|---|---|---|
| Argo CD | chart `argo-cd` **10.9.7** (https://argoproj.github.io/argo-helm), app **v3.5.4** | Argo CD 3.5 is tested on Kubernetes 1.33–1.36. v3.5.4 (6 October) is the first 3.5 release with the October security fixes: CRITICAL Kustomize and Helm command execution in the repo-server, Jsonnet file read and hook AppProject bypass, plus HIGH login rate-limit and SSH proxy issues. The root Application uses Kustomize. The older v3.5.3 (chart 10.9.6) was rejected for that reason, so this pin is 8 days old, not the usual two weeks. v3.5.5 has bug fixes only; it is a later upgrade |
| Argo CD's bundled tools | kustomize 5.8.1, Helm 4.2.1 | The tests use the same kustomize. Charts are rendered locally with Helm 3.22.0 |
| AWS Load Balancer Controller | chart and app **3.6.0** | As decided in [load-balancer-controller.md](load-balancer-controller.md) |

The pins for NGINX, cert-manager and ExternalDNS are unchanged; see [ingress.md](ingress.md) and
[dns-and-certificates.md](dns-and-certificates.md).

## Layout

| Path | Purpose |
|---|---|
| `gitops/argocd/values.yaml` | Argo CD Helm values. Installed once with Helm; Argo CD does not manage itself |
| `gitops/argocd/root-application.yaml` | Root Application (app of apps), applied once after rendering |
| `gitops/kustomization.yaml` | The child Applications the root manages |
| `gitops/platform/*/application.yaml`, `gitops/apps/finsight/application.yaml` | One Application per component, each with its sync wave and sync policy |
| `scripts/render-argocd-root.ps1` | Fills the root Application with this account's values into an ignored file |
| `scripts/validate-gitops.ps1`, `tests/gitops/test_argocd.py` | Offline validation |

## Design

**Install.**
- Non-HA, one replica of each component, with requests sized for two m7i-flex.large workers: about
  0.5 vCPU and 1 GiB of requests in total.
- Dex, notifications and Ingress are disabled, and exec is off.
- Access is through `kubectl port-forward` only, so Argo CD has no public endpoint. Git is polled
  every 120 s plus up to 60 s of jitter, because GitHub cannot reach an in-cluster webhook.
- The public F5 NGINX chart is an OCI artifact, so it is declared as a Helm repository with
  `enableOCI`. It needs no credentials, and neither does the Git repository, which is public.

**App of apps.** `finsight-root` renders `gitops/kustomization.yaml`, which lists the existing child
Application files unchanged. The waves enforce the dependencies. Argo CD's values add the upstream
health check for Applications, so each wave waits until the previous children are **Healthy**, not
merely applied.

| Wave | Application | Waits for |
|---|---|---|
| 0 | cert-manager | Nothing; installs its CRDs (`ServerSideApply`) |
| 1 | aws-load-balancer-controller | cert-manager, which issues its webhook certificate (`enableCertManager`). A render-time certificate would differ on every render: permanently OutOfSync, and rotated by self-heal |
| 1 | cluster-issuers | cert-manager CRDs; the Issuers are Ready only after ACME registration |
| 1 | monitoring (G05) | cert-manager, which issues the operator webhook certificate. Its CRDs (ServiceMonitor, PrometheusRule) must exist before NGINX and FinSight create theirs. Needs the `grafana-admin` Secret; see [monitoring.md](monitoring.md) |
| 2 | nginx-ingress | The load balancer controller, so the NLB is created by it with the Terraform security group. The Service is Healthy only once the NLB has an address |
| 3 | external-dns | NGINX has published the NLB address in Ingress status |
| 4 | finsight | Everything above. Also needs published images and the `finsight-database` Secret |

**Account-specific values are never committed.** The children keep their `REPLACE_WITH_*`
placeholders. The root Application holds Kustomize JSON patches that replace them in the cluster:
- the VPC ID
- the hosted zone ID, used twice
- the public ingress security group
- the two ECR repository URLs

Each patch first `test`s the parameter's name and placeholder. If a child file is edited so the
patch would hit the wrong field, the build fails rather than misconfigures. The renderer checks
each value's format and writes the result only to an ignored path.

**Image updates (G07).**
1. The `finsight` Application renders the chart with `values.yaml`, then `image-tags.yaml`, then the
   repository parameters, in increasing precedence.
2. The pipeline's only deployment action is a pull request that changes `image-tags.yaml`
   (commit-SHA tag plus digest).
3. Merging it moves `main`, and Argo CD rolls out `repository@digest`.

There is no `kubectl` in CI. `image-tags.yaml` is excluded from the workflow's path filters, so the
merge does not trigger another build and publish.

## Pruning and deletion (intentional)

- **`prune: true` and `selfHeal: true` on every Application**
  - A resource removed from Git is deleted at the next sync.
  - Live edits are reverted.
  - `PruneLast` deletes only after everything else in the sync is healthy.
  - Argo CD refuses a sync that would render nothing (`allowEmpty` is false), so a broken path
    cannot delete a whole application.
- **Removing the NGINX Service from Git deletes the NLB.** This is the expected way to remove it.
- **ExternalDNS never deletes records** (`policy: upsert-only`). Records are removed only as
  described in [dns-and-certificates.md](dns-and-certificates.md).
- **No child has a resources finalizer.**
  - Removing a child from `gitops/kustomization.yaml` deletes the Application only. The root prunes
    it, but its workloads keep running unmanaged.
  - `argocd app delete <app>` without `--cascade` behaves the same way.
  - Deleting workloads is always an explicit `argocd app delete <app> --cascade`.
- **Teardown before `terraform destroy`** (extends [runbook.md](runbook.md) "Pause CI and ArgoCD
  reconciliation"):
  1. `argocd app delete finsight-root --cascade=false` stops management.
  2. Run `argocd app delete <app> --cascade` for `finsight`, `external-dns`, `nginx-ingress` (wait
     until the NLB is gone), `cluster-issuers`, `cert-manager` and finally
     `aws-load-balancer-controller`. The controller must still be running when the NGINX Service
     is deleted.
  3. Run `helm uninstall argocd -n argocd`. The Argo CD CRDs are kept (`crds.keep`); delete them
     explicitly if wanted.

## Bootstrap during a deployment window

**Before starting**, all of the following must be true:
- The platform is applied (EKS 1.36, m7i-flex.large workers) and `kubectl` points at
  `finsight-dev`.
- The Pod Identity associations exist (Terraform).
- At least one image pull request from the pipeline has been merged, so `image-tags.yaml` has
  digests. The renderer refuses to continue otherwise: FinSight cannot render, and an unrenderable
  final wave keeps the root sync waiting.

**Bootstrap safety (TLS and DNS).**
- FinSight starts with `ingress.tls.enabled: false`. Once it is enabled, the first certificate uses
  `letsencrypt-staging`. Production issuance needs a reviewed Git change.
- ExternalDNS is limited to `eks.feras-dev.co.uk`, A and AAAA records only, with its own TXT
  ownership, and runs `upsert-only`. It cannot alter or delete any other record in the zone.

**Steps**

1. **Secrets.** Create the Grafana admin Secret as in [monitoring.md](monitoring.md) step 1. Then create the database Secret outside Git (values from the database task; never committed or
   printed):

   ```sh
   kubectl create namespace finsight
   kubectl -n finsight create secret generic finsight-database \
     --from-literal=PGHOST=... --from-literal=PGPORT=5432 --from-literal=PGDATABASE=... \
     --from-literal=PGUSER=... --from-literal=PGPASSWORD=...
   ```

2. **Install Argo CD** from the repository root:

   ```sh
   helm repo add argo https://argoproj.github.io/argo-helm
   helm upgrade --install argocd argo/argo-cd --version 10.9.7 \
     --namespace argocd --create-namespace -f gitops/argocd/values.yaml --wait
   kubectl -n argocd get pods
   ```

3. **Open the UI and CLI** in a separate terminal:

   ```sh
   kubectl -n argocd port-forward svc/argocd-server 8080:443
   ```

   Use https://localhost:8080. The certificate is self-signed, so the CLI needs `--insecure`.

4. **Rotate the initial admin password** (G08.1, R8.5):

   ```sh
   argocd admin initial-password -n argocd      # one-time password; do not save it anywhere
   argocd login localhost:8080 --username admin --insecure
   argocd account update-password                # new password goes to the owner's password manager
   kubectl -n argocd delete secret argocd-initial-admin-secret
   ```

5. **Render and apply the root Application.** In PowerShell from the repository root, with
   Terraform outputs read from state. This is read-only and prints nothing:

   ```powershell
   $tf = ".\.cache\terraform\terraform.exe"
   $network = & $tf "-chdir=infra/terraform/environments/dev/platform" output -json network | ConvertFrom-Json
   $repos = & $tf "-chdir=infra/terraform/environments/dev/foundation" output -json repository_urls | ConvertFrom-Json
   $zone = (Get-Content -Raw infra/terraform/config/local.json | ConvertFrom-Json).dns.zone_id
   .\scripts\render-argocd-root.ps1 -VpcId $network.vpc_id -HostedZoneId $zone `
     -PublicIngressSecurityGroupId $network.public_ingress_security_group_id `
     -ApiRepositoryUrl $repos.api -FrontendRepositoryUrl $repos.frontend
   kubectl apply -f .cache/argocd/root-application.yaml
   ```

   Re-render and re-apply whenever the network is recreated. The security group ID changes with it.

6. **Watch the waves** until every Application is `Synced` and `Healthy`:

   ```sh
   argocd app list
   argocd app get finsight-root
   ```

   Expected time is about 5–10 minutes. NLB provisioning dominates.

## Assessment demonstrations (live; not yet run)

| Criterion | Demonstration | Evidence |
|---|---|---|
| G08.1, R8.5 | `kubectl -n argocd get pods`; `helm list -n argocd` shows chart 10.9.7; `kubectl -n argocd get secret argocd-initial-admin-secret` returns NotFound | `docs/screenshots/argocd/` |
| G08.2, R8.1 | `argocd app get finsight-root` resource tree shows the seven children. Use `argocd app list` and check that every workload namespace is owned by an Application | Screenshot of the UI tree |
| G08.3 | PR changing `frontend.replicas` from 1 to 2 in `gitops/apps/finsight/values.yaml`. After merge, within 3 minutes (or `argocd app get finsight --refresh`), the new revision syncs: `argocd app get finsight`, `kubectl -n finsight get deploy finsight-frontend` | PR link, sync history |
| G08.4, R4.2 | `argocd app list`: every Application Synced and Healthy | UI screenshot |
| G08.5, R8.4 | Harmless drift: `kubectl -n finsight scale deploy/finsight-frontend --replicas=3`. Self-heal returns it to the Git value within seconds: `kubectl -n finsight get deploy finsight-frontend -w`, `argocd app get finsight` | Before and after output in `docs/evidence/` |
| History and rollback | `argocd app history finsight` lists each deployed revision. Roll back with `git revert` of the change (for example the image PR) and merge; Argo CD syncs the earlier state. `argocd app rollback` is refused while automated sync is on, and the root would restore the child's policy, so Git is the rollback path | History output; revert PR |
| G07.6 | Merge the pipeline's image PR. The running pod's image digest equals the ECR digest: `kubectl -n finsight get pod -l app.kubernetes.io/name=finsight-api -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'` | Screenshot |

## Local validation (15 October 2026)

`scripts/validate-gitops.ps1` passed: 27 tests for G08, 41 since G05 added its monitoring tests. It runs pytest in the pinned Python 3.12 image with
helm 3.22.0, kustomize 5.8.1 and kubeconform 0.8.0. Kubernetes 1.36.0 schemas are used, plus the
CRDs catalog for Argo CD, cert-manager and load balancer controller resources; missing schemas fail.

- **Renderer**
  - The sample renders.
  - It refuses a placeholder security group, a `/hostedzone/` zone ID and a swapped repository
    URL.
  - It refuses to run while `image-tags.yaml` has no digests.
- **Layout and references**
  - Every `application.yaml` is listed in the kustomization.
  - Each Application uses namespace `argocd`, project `default`, the in-cluster destination,
    automated prune and self-heal, and no finalizer.
  - Chart versions are exact pins.
  - Every `$values/` and path value file exists, and Git sources use this repository at `main`.
- **Ordering**
  - Every sync-wave dependency in the table above holds. A mutation test (NGINX moved to wave 1) failed as
    expected.
  - The Application health check is configured.
- **Root build**
  - kustomize build with the root patches yields the seven children.
  - No placeholder or token is left.
  - Each injected value is at the intended parameter, and nothing else in the child changes.
  - A child with reordered parameters makes the build fail at the `test` operation.
- **Schemas**
  - The root and children validate as Argo CD Applications.
- **Rendering**
  - Each Application renders exactly as Argo CD would: the chart, its value files and the injected
    parameters.
  - All seven pass kubeconform. Both repository charts pass `helm lint --strict`.
- **image-tags.yaml**
  - The Application reads `values.yaml` then `image-tags.yaml`.
  - A digest there renders `repository@digest`, and a tag alone renders `repository:tag`.
  - The committed empty file is refused.
  - The workflow writes that path, contains no `kubectl`, and its path filters exclude it.
- **Argo CD install**
  - The chart is 10.9.7 / v3.5.4 and renders and validates for Kubernetes 1.36.
  - No Dex, notifications or Ingress; the server Service is ClusterIP.
  - The health check is in `argocd-cm`, and the OCI repository Secret is present.
  - Every workload has one replica and every container has requests.
- **Load balancer controller**
  - The cert-manager Certificate and Issuer are present, and no webhook has a render-time
    `caBundle`.
  - No IngressClass and no Service mutating webhook.
  - Cluster name, Region and VPC are passed as arguments.
- **ruff** (`check` and `format --check`, as in CI) is clean.

**Not testable locally**
- The real Argo CD sync, health and waves.
- Polling of GitHub.
- Self-heal.
- Webhook certificates from cert-manager.
- NLB creation.
- ACME registration.
- Rendering with Argo CD's own Helm 4.2.1 rather than the Helm 3.22.0 used here.

## Live evidence outstanding

- Argo CD pods Running and the initial secret deleted (G08.1).
- The tree of the seven children (G08.2).
- A Git change reconciled (G08.3).
- All Applications Synced and Healthy (G08.4).
- Drift reverted (G08.5).
- History and a Git rollback.
- The image PR rolled out by digest (G07.6).

These need:
- a platform redeploy
- a published image and its merged GitOps pull request (G07 owner prerequisites)
- the `finsight-database` Secret

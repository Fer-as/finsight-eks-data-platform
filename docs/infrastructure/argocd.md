# Argo CD GitOps (G08)

Status: **installed on 16 October 2026** and verified live: eight Applications Synced and
Healthy, automated sync from merges and a self-heal demonstration
([evidence](../screenshots/README.md#g08-argo-cd)). The design notes below are unchanged.

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
| `scripts/validate-gitops.ps1`, `tests/gitops/test_argocd.py` | Offline validation, also run on pull requests by `.github/workflows/gitops.yml` |

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
| 4 | finsight | Everything above. Needs the `finsight-database` Secret. Inside the Application: StorageClass (wave -2), PostgreSQL StatefulSet and Service (-1), database init Job as a Sync hook (0), API (1); see "In-cluster database" below |

**Account-specific values are never committed.** The children keep their `REPLACE_WITH_*`
placeholders. The root Application holds Kustomize JSON patches that replace them in the cluster:
- the VPC ID
- the hosted zone ID, used twice
- the public ingress security group
- the three ECR repository URLs (api, frontend, etl)

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
- `image-tags.yaml` on `main` has published digests for api, frontend and etl (true since PR #46).
  The renderer refuses to continue otherwise: FinSight cannot render, and an unrenderable final
  wave keeps the root sync waiting.

**Bootstrap safety (TLS and DNS).**
- FinSight starts with `ingress.tls.enabled: false`. Once it is enabled, the first certificate uses
  `letsencrypt-staging`. Production issuance needs a reviewed Git change.
- ExternalDNS is limited to `eks.feras-dev.co.uk`, A and AAAA records only, with its own TXT
  ownership, and runs `upsert-only`. It cannot alter or delete any other record in the zone.

**Steps**

1. **Secrets** (before step 5; never in Git). With `kubectl` pointing at the cluster, from the
   repository root in Windows PowerShell:

   ```powershell
   .\scripts\new-cluster-secrets.ps1
   ```

   It creates the namespaces if needed, then asks twice (hidden) for each password. Take both from
   the password manager, at least 16 characters; the script never generates, prints or stores them.

   | Secret | Namespace | Keys | Used by |
   |---|---|---|---|
   | `finsight-database` | `finsight` | `PGDATABASE` (default `finsight`), `PGUSER` (default `finsight`), `PGPASSWORD` | PostgreSQL (initial database and user), the init Job and the API. `PGHOST`/`PGPORT` are set by the chart |
   | `grafana-admin` | `monitoring` | `admin-user` (default `finsight-admin`), `admin-password` | Grafana |

   Each Secret goes to `kubectl create -f -` on standard input, so no credential appears in a
   command line, a file or the `last-applied` annotation. It refuses to overwrite an existing
   Secret. Missing Secrets block their waves: PostgreSQL cannot start (FinSight stays Progressing),
   and neither can Grafana (monitoring, wave 1, never becomes Healthy).

   Check with `kubectl -n finsight get secret finsight-database` and
   `kubectl -n monitoring get secret grafana-admin`. The PostgreSQL password only takes effect
   when the database volume is first initialised. To change it later, recreate the volume
   (delete the `finsight` Application with `--cascade` and let Argo CD resync), or use
   `ALTER ROLE` inside the database.

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
     -ApiRepositoryUrl $repos.api -FrontendRepositoryUrl $repos.frontend -EtlRepositoryUrl $repos.etl
   kubectl apply -f .cache/argocd/root-application.yaml
   ```

   Re-render and re-apply whenever the network is recreated. The security group ID changes with it.

6. **Watch the waves** until every Application is `Synced` and `Healthy`:

   ```sh
   argocd app list
   argocd app get finsight-root
   ```

   Expected time is about 5–10 minutes. NLB provisioning dominates.

## Assessment demonstrations

Status, 17 October 2026: G08.1, G08.2, G08.4 and G08.5 were demonstrated live. G08.3 is
evidenced by the automated syncs of merged PRs #47, #50 and #51 rather than the replicas change
described below. See the [evidence index](../screenshots/README.md#g08-argo-cd).

| Criterion | Demonstration | Evidence |
|---|---|---|
| G08.1, R8.5 | `kubectl -n argocd get pods`; `helm list -n argocd` shows chart 10.9.7; `kubectl -n argocd get secret argocd-initial-admin-secret` returns NotFound | `docs/screenshots/argocd/` |
| G08.2, R8.1 | `argocd app get finsight-root` resource tree shows the seven children. Use `argocd app list` and check that every workload namespace is owned by an Application | Screenshot of the UI tree |
| G08.3 | PR changing `frontend.replicas` from 1 to 2 in `gitops/apps/finsight/values.yaml`. After merge, within 3 minutes (or `argocd app get finsight --refresh`), the new revision syncs: `argocd app get finsight`, `kubectl -n finsight get deploy finsight-frontend` | PR link, sync history |
| G08.4, R4.2 | `argocd app list`: every Application Synced and Healthy | UI screenshot |
| G08.5, R8.4 | Harmless drift: `kubectl -n finsight scale deploy/finsight-frontend --replicas=3`. Self-heal returns it to the Git value within seconds: `kubectl -n finsight get deploy finsight-frontend -w`, `argocd app get finsight` | Before and after output in `docs/evidence/` |
| History and rollback | `argocd app history finsight` lists each deployed revision. Roll back with `git revert` of the change (for example the image PR) and merge; Argo CD syncs the earlier state. `argocd app rollback` is refused while automated sync is on, and the root would restore the child's policy, so Git is the rollback path | History output; revert PR |
| G07.6 | Merge the pipeline's image PR. The running pod's image digest equals the ECR digest: `kubectl -n finsight get pod -l app.kubernetes.io/name=finsight-api -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'` | Screenshot |

## In-cluster database

PostgreSQL 17 runs inside the `finsight` Application (`gitops/apps/finsight/templates/database.yaml`).
There is no RDS and no operator. Every component in the chart uses the single role from Secret
`finsight-database`. The separate writer and reader roles used locally are not yet applied here; see
[database roles](database-roles.md#where-it-runs).

- **Storage.** StatefulSet `finsight-postgres` has one replica. It uses a 5 GiB encrypted gp3 volume
  from StorageClass `finsight-gp3` (`ebs.csi.aws.com`, `WaitForFirstConsumer`). The EBS CSI add-on
  already has its Pod Identity role.
- **Image and security.** The image is `postgres:17-alpine`, pinned to the same digest as CI. It runs
  as UID 10070 with a read-only root filesystem and all capabilities dropped. Data is in
  `PGDATA=/var/lib/postgresql/data/pgdata`.
- **Access.** It is reachable only through the ClusterIP Service `finsight-postgres:5432`. The Ingress
  never routes to it.
- **Initialisation.** Job `finsight-db-init` uses the published ETL image (`etl` digest in
  `image-tags.yaml`). It runs `scripts/migrate.py`, then the deterministic synthetic generator, then
  the ETL load.
  - It is an Argo CD Sync hook in wave 0, so it runs after PostgreSQL is Ready (wave -1) and before
    the API (wave 1).
  - It re-runs on every sync. That is safe: migrations are checksummed and skipped once applied, and
    the ETL replaces the curated snapshot in one transaction.
- **Ordering and outages.** The API starts only after the Job has succeeded. Its readiness probe
  (`/api/health/ready`) checks the database on every probe.
- **Single replica.** The volume is zonal, so a pod moved to the other AZ cannot attach it until the
  node in its original AZ returns. This is an assessment compromise, not HA.

### Writable paths under the read-only root filesystem

Every FinSight container runs with `readOnlyRootFilesystem: true`. These are the only writable
mounts, and why each exists:

| Container | Writable mount | Reason |
|---|---|---|
| `frontend` (`nginx-unprivileged`) | `/tmp` (emptyDir) | The unprivileged NGINX image keeps its PID file and its client-body and proxy temporary files under `/tmp`, so NGINX cannot start without it |
| `api` | `/tmp` (emptyDir) | Precautionary scratch space for the Python runtime and libraries; the API code itself writes no files |
| `postgres` | `PGDATA` on the encrypted gp3 volume; `/var/run/postgresql` and `/tmp` (emptyDir) | Database files; the Unix socket and lock file; temporary files |
| `db-init` (Job) | `/app/data` and `/tmp` (emptyDir) | The generator and ETL write raw CSV, curated Parquet and rejection files under `data/` before loading PostgreSQL; temporary files |
- **Teardown.** `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete` with `reclaimPolicy: Delete`:
  `argocd app delete finsight --cascade` removes the claim and the EBS volume. Confirm that
  `kubectl get pv` shows nothing left before `terraform destroy`.
- **No automated backups.** There is no recurring backup service; the data is synthetic and
  reproducible. Before the teardown on 20 October 2026, a custom-format `pg_dump` was taken and
  restore-tested in a separate database (F6;
  [teardown evidence](../evidence/2026-10-20-platform-teardown.md#database-backup)).

Verified locally with Docker, with the same security settings:
- PostgreSQL initialises and restarts on its existing data.
- The init command, run twice: migration applied, then skipped; 10,000 transactions both times;
  2 successful pipeline runs.
- The API returns `/api/health/ready`, `/api/departments` and `/api/dashboard` (`has_data: true`).

## Local validation (15 October 2026)

`scripts/validate-gitops.ps1` passed: 27 tests for G08, 41 after G05, 50 with the in-cluster database tests. It runs pytest in the pinned Python 3.12 image with
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

Captured on 16-17 October 2026: Argo CD running with the initial secret deleted (G08.1), the
seven child Applications (G08.2), Git changes reconciled (G08.3), all Applications Synced and
Healthy (G08.4), drift reverted (G08.5) and the image PR rolled out by digest (G07.6).

Still outstanding:
- History and a Git rollback.

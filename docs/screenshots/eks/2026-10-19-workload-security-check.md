# FinSight workload security and resources (R5, R8.5), 19 October 2026

Read-only `kubectl get pods -n finsight -o json`, run against the live `finsight-dev` cluster on
19 October 2026. The values are shown as Kubernetes reports them; no IP addresses are included.

| Container | Pod state | runAsNonRoot / UID | allowPrivilegeEscalation | Capabilities | readOnlyRootFilesystem | seccomp | Requests (CPU / memory) | Limits (CPU / memory) | Readiness / liveness |
|---|---|---|---|---|---|---|---|---|---|
| `api` | Running | true / 10001 | false | drop ALL | true | RuntimeDefault | 100m / 128Mi | 500m / 512Mi | yes / yes |
| `frontend` | Running | true / 10101 | false | drop ALL | true | RuntimeDefault | 50m / 64Mi | 200m / 128Mi | yes / yes |
| `postgres` | Running | true / 10070 | false | drop ALL | true | RuntimeDefault | 100m / 256Mi | 1 / 512Mi | yes / yes |
| `db-init` (Job) | Succeeded | true / 10001 | false | drop ALL | true | RuntimeDefault | 100m / 256Mi | 1 / 1Gi | n/a (run-once Job) |

Writable mounts, all emptyDir unless stated:
- `api`: `/tmp`
- `frontend`: `/tmp`
- `postgres`: the data volume (PVC), `/var/run/postgresql`, `/tmp`
- `db-init`: `/app/data`, `/tmp`

The reasons for each are in [argocd.md](../../infrastructure/argocd.md#writable-paths-under-the-read-only-root-filesystem).

Database credentials reach the containers only through the Secret `finsight-database`, which the
manifests reference by name. Its values are not shown.

`kubectl -n argocd get secret argocd-initial-admin-secret` returned `NotFound`: the initial Argo CD
admin password was removed after setup (R8.5).

Not covered by this check:
- a probe-failure demonstration (R5.4);
- a rolling update (R5.5: the API and frontend Deployments have only revision 1 and use the default
  25%/25% strategy).

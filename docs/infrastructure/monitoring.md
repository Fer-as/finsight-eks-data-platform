# Monitoring: Prometheus and Grafana (G05)

Status: **installed on 16 October 2026** and verified live: targets UP (including the FinSight
API and NGINX), the FinSight dashboard shows live data, and the default Grafana login is rejected
([evidence](../screenshots/README.md#g05-monitoring)).

## Versions

| Component | Pin | Notes |
|---|---|---|
| kube-prometheus-stack | chart **91.8.2** (https://prometheus-community.github.io/helm-charts), Prometheus Operator v0.94.1 | Released 29 September 2026. Chart `kubeVersion >=1.25.0-0`; rendered and schema-checked for Kubernetes 1.36 |
| Prometheus | v3.15.0 (chart default) | `promtool` 3.15.0 is used for the rule checks |
| Grafana | image **13.2.4**, overriding the chart default 13.2.3 | 13.2.4 (13 October) fixes four CVEs |
| kube-state-metrics, node-exporter | subcharts 8.6.0 and 4.59.0 (chart defaults) | |
| API instrumentation | `prometheus-client` 0.26.0 | Added to `pyproject.toml` and both lockfiles; nothing else changed in them |

## What is collected and where it is shown

| Requirement | Source | Shown in |
|---|---|---|
| Node CPU, memory, disk and network (G05.2) | node-exporter DaemonSet, kubelet/cAdvisor | Grafana *Node Exporter / Nodes*, *Kubernetes / Compute Resources / Node (Pods)* |
| Pod, namespace and workload CPU and memory (G05.2) | kubelet/cAdvisor, kube-state-metrics | *Kubernetes / Compute Resources / Cluster*, */ Namespace (Pods)*, */ Pod*; *FinSight / Service overview* (FinSight pods) |
| Service and network metrics (G05.2) | cAdvisor network, kube-state-metrics | *Kubernetes / Networking / Namespace (Pods)*; ingress traffic per Service on the FinSight dashboard |
| NGINX requests, status codes and latency (G05.3) | F5 NGINX metrics on 9113: `nginx_ingress_controller_upstream_server_response_latency_ms` (labels `code`, `service`, `resource_namespace`, …) and `nginx_ingress_nginx_http_requests_total` | *FinSight / Service overview*: requests by status code, p95 latency by Service, requests by Service |
| FinSight API metrics (G05.4) | `/metrics` on the API: `finsight_api_requests_total{method,route,status}` and `finsight_api_request_duration_seconds` | *FinSight / Service overview*: requests by route and status, p95 latency by route, 5xx ratio |
| Alerts | Chart default rules (EKS-incompatible ones disabled), plus `FinSightApiDown` and `FinSightApiHighErrorRate` | Prometheus *Alerts* page |

The FinSight chart owns its monitoring objects (`gitops/apps/finsight/templates/monitoring.yaml`):
- the ServiceMonitor
- the PrometheusRule
- the dashboard ConfigMap, built from `dashboards/finsight.json`

Grafana's sidecar loads dashboards from every namespace, and Prometheus selects every
ServiceMonitor and rule.

## Design

**One Argo CD Application at wave 1** (`gitops/platform/monitoring`).
- It comes after cert-manager, which issues the operator's webhook certificate in place of
  install-time hook Jobs.
- It comes before NGINX (wave 2) and FinSight (wave 4), because their ServiceMonitors need its
  CRDs.
- It uses `ServerSideApply` for the large CRDs.

**EKS specifics.**
- The control plane (etcd, scheduler, controller manager) cannot be scraped.
- The kube-proxy add-on serves metrics on localhost only.
- Their targets and default rules are therefore disabled. Otherwise they would only ever show as
  down.

**Storage.**
- Prometheus keeps 2 days of data (capped at 3 GB) on an `emptyDir` limited to 4 GiB.
- Grafana has no persistence; its dashboards are provisioned from ConfigMaps.
- There are no EBS volumes and no extra IAM.
- Trade-off: data is lost if a pod is rescheduled. That is acceptable for a short assessment
  window.

**No Alertmanager.** There is no receiver in this environment. Alerts are evaluated and visible in
Prometheus.

**Access and security.**
- Every Service is ClusterIP. There is no Ingress, and NGINX's metrics Service is not on the NLB.
- The API's `/metrics` is not routed by the Ingress, which sends only `/api` to the API.
- Grafana takes its admin user and password from the Secret `grafana-admin`, created outside Git.
  The chart's default password (`prom-operator`) is never rendered.
- Anonymous access and sign-up are disabled.
- Access is through `kubectl port-forward` only.

**Sizing (G05.1).** Requests across every GitOps workload plus Argo CD come to:

| Scope | CPU | Memory | Pods |
|---|---|---|---|
| Rendered total (computed by the test) | 1.43 vCPU | 3.6 GiB | 21 |
| Monitoring share | 0.39 vCPU | 1.3 GiB | 6 |
| EKS add-ons (estimated) | 0.6 vCPU | 0.75 GiB | 12 |
| Allocatable on two m7i-flex.large workers | ~3.9 vCPU | ~14.6 GiB | 58 |

The test fails above 85% of allocatable. Limits are set on memory only: CPU is throttled rather
than killed, and the requests guarantee scheduling.

## Deployment and verification (deployment window)

1. **Before the root Application is applied**, create Secret `monitoring/grafana-admin` (keys
   `admin-user`, `admin-password`) together with `finsight/finsight-database`. Use
   `.\scripts\new-cluster-secrets.ps1`, as in [argocd.md](argocd.md) step 1. It prompts for the
   password (hidden, from the password manager) and never generates, prints or passes it on a
   command line.

   If the Secret is missing, Grafana cannot start and wave 1 never becomes Healthy.

2. Bootstrap as in [argocd.md](argocd.md). Then check that the monitoring stack is up:

   ```sh
   argocd app get monitoring
   kubectl -n monitoring get pods -o wide
   kubectl top nodes        # if metrics-server is present; otherwise use the node dashboard
   ```

3. **Prometheus targets (R4.3).** Run `kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090`,
   then:

   ```sh
   curl -s 'http://localhost:9090/api/v1/targets?state=active' \
     | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)"' | sort | uniq -c
   curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=up{job=~"finsight-api|nginx-ingress.*"}' | jq '.data.result[] | {job: .metric.job, value: .value[1]}'
   ```

   Every job should report `up`, including `finsight-api`, the NGINX metrics job, `kubelet`,
   `node-exporter`, `kube-state-metrics` and `apiserver`. Take a screenshot of
   http://localhost:9090/targets.

4. **Grafana (R4.4, G05.5).** Run `kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80`
   and open http://localhost:3000.
   - Show that `admin` / `prom-operator` is rejected (the screenshot is the evidence).
   - Log in with the `grafana-admin` credentials.

5. **Generate traffic** through the public hostname so that ingress and API panels move:

   ```sh
   for i in $(seq 1 200); do
     curl -s -o /dev/null https://eks.feras-dev.co.uk/api/dashboard
     curl -s -o /dev/null https://eks.feras-dev.co.uk/api/does-not-exist
     curl -s -o /dev/null https://eks.feras-dev.co.uk/
   done
   ```

   Use `http://` until TLS is enabled.

6. **Capture the dashboards** with the time range inside the deployment window, into
   `docs/screenshots/monitoring/`:
   - *FinSight / Service overview*: API requests by route and status (200 and 404 visible), p95
     latency, ingress requests by status code and by upstream (FinSight backend).
   - *Node Exporter / Nodes*: both workers.
   - *Kubernetes / Compute Resources / Namespace (Pods)* for `finsight`.
   - *Kubernetes / Networking / Namespace (Pods)*.

7. **Alerts (optional).** Prometheus *Alerts* lists `FinSightApiDown` and
   `FinSightApiHighErrorRate` as inactive. Firing is proven offline by promtool unit tests. A live
   firing would need the API down for 2 minutes, which Argo CD self-heal prevents for scaling
   changes.

## Local validation (15 October 2026)

Unless noted, these ran through `scripts/validate-gitops.ps1`: 41 tests, the 27 from G08 plus 14
for G05.

- **Render.**
  - The monitoring Application renders exactly as Argo CD would.
  - All objects pass kubeconform for Kubernetes 1.36, using the CRD catalog for ServiceMonitor,
    PrometheusRule, Prometheus and Certificate.
- **Stack shape.**
  - Grafana, kube-state-metrics, the node-exporter DaemonSet, the operator and one Prometheus are
    present.
  - There is no Alertmanager, no Ingress and no hook Job. Every Service is ClusterIP.
  - The webhook certificate is a cert-manager Certificate.
- **Prometheus.**
  - Empty selectors, so every monitor and rule is selected.
  - Retention 2d / 3GB, emptyDir capped at 4Gi, and the requests above.
  - No etcd, scheduler, controller-manager or kube-proxy monitors or alerts. The kubelet,
    apiserver, kube-state-metrics and node-exporter monitors are present.
- **Grafana.**
  - Admin user and password come from `grafana-admin` via `secretKeyRef`.
  - `prom-operator` and the chart's generated Secret are absent.
  - Anonymous access and sign-up are off, and the image is 13.2.4.
  - The sidecar uses label `grafana_dashboard` across ALL namespaces.
  - The cluster, namespace, pod, node, node-exporter and networking dashboards are present.
- **FinSight.**
  - The ServiceMonitor selects the API Service on its `http` port at `/metrics`.
  - `/metrics` is not an Ingress path.
  - The dashboard ConfigMap is labelled and its JSON parses.
- **NGINX.**
  - Arguments `-enable-prometheus-metrics=true`, `-enable-latency-metrics=true` and port 9113.
  - The ServiceMonitor matches exactly one ClusterIP metrics Service on 9113.
  - The LoadBalancer Service does not expose 9113.
- **Rules.**
  - `promtool check rules` passes for every rendered PrometheusRule (chart defaults and FinSight).
  - `promtool test rules`: `FinSightApiDown` fires after 2 minutes down and stays silent when up.
    `FinSightApiHighErrorRate` fires at a 10% 5xx ratio, with the exact rendered annotations.
- **Dashboard.**
  - Every panel query is valid PromQL (checked with promtool).
  - Every metric used is produced by the API code, verified in the NGINX controller v5.6.3 source,
    or is a standard cAdvisor or `up` series.
- **Sizing.** The whole-cluster requests check passed (table above).
- **API tests** (pytest; ruff check and format clean across the repository): 16 passed, 3 of them
  new. The new tests cover counts by route template, `unmatched` for unknown paths (raw paths and
  query values never appear), Prometheus text format and `/metrics` not counting itself.
- **API image.** The image builds, and `/metrics` is served with a read-only root filesystem.
- **CI steps reproduced locally.**
  - Checkov, as in CI: Kubernetes 182 passed / 0 failed / 3 documented skips; Dockerfiles
    197 / 0.
  - The Trivy gate passes: 0 fixable HIGH/CRITICAL.

**Not testable locally**
- Real scrapes and target health.
- Grafana rendering with data.
- Pod network reachability from Prometheus to NGINX 9113 and the API on 8000. Both are
  node-to-node traffic inside the cluster security group.
- Actual memory use under load.

## Live evidence

Captured on 16-17 October 2026 ([evidence](../screenshots/README.md#g05-monitoring)): monitoring
pods Running (G05.1), targets UP including FinSight and NGINX (R4.3), NGINX and API panels with
live data (G05.3, G05.4), and the failed default login (G05.5).

Captured on 19 October 2026, after the Grafana memory fix in PR #57: node, cluster and namespace,
FinSight pod and service-overview dashboards with live data (G05.2, R4.4). Some service-overview
panels show "No data"; see the [evidence index](../screenshots/README.md#g05-monitoring).

### Dashboard corrections after teardown (20 October 2026)

Two problems seen in the recorded dashboards were corrected in the dashboard definition after the
platform was removed. They are checked offline by promtool and the GitOps tests, but have **not**
been seen on a live cluster. The screenshots above show the dashboard as it was.
- **API 5xx ratio.** With no 5xx responses, no 5xx series exists, so the ratio had no result and the
  panel showed "No data". The numerator now defaults to zero (`… or vector(0)`), so healthy traffic
  shows 0. If the API is not scraped, the denominator has no series, so the panel still shows "No
  data" rather than a false zero. A promtool unit test covers three cases: no errors (0), errors
  (the true ratio) and no API series (no result).
- **Ingress panels by backend.** Prometheus Operator sets a `service` label to the scraped metrics
  Service. That overrides NGINX's own `service` label, so the "by Service" panels showed
  `nginx-ingress-prometheus-service` (recorded on 16 October 2026) instead of the FinSight backends.
  They now group by NGINX's `upstream` label, which the scrape does not override. The exact upstream
  names have not been observed on a live cluster.

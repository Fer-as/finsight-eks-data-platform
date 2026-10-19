# G05.2 live metrics verification (Prometheus queries)

Captured 2026-10-18 from the live `finsight-dev` cluster. The queries ran through the Kubernetes API
service proxy, read-only, without Grafana credentials. Values are instant samples at query time,
and node identifiers are replaced with `node-a` and `node-b`.

## Health

```
Prometheus 3.15.0: 20 active targets, 20 up
Grafana 13.2.4: /api/health database ok
```

## Series

| Metric | Query (abbreviated) | Series | Non-zero |
|---|---|---:|---:|
| Node CPU in use | `sum by (instance) (rate(node_cpu_seconds_total{mode!="idle"}[5m]))` | 2 | 2 (about 0.07 cores each) |
| Node memory used | `node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes` | 2 | 2 (about 1.9 and 2.1 GB) |
| Namespace CPU | `sum by (namespace) (rate(container_cpu_usage_seconds_total[5m]))` | 7 | 7 |
| Namespace memory | `sum by (namespace) (container_memory_working_set_bytes)` | 7 | 7 (finsight about 96 MB) |
| FinSight pod CPU | the same, filtered to `namespace="finsight"`, by pod | 3 | 3 |
| FinSight pod memory | the same, filtered to `namespace="finsight"`, by pod | 3 | 3 (API about 49 MB, PostgreSQL about 43 MB) |
| Requests by Service (NGINX upstream) | `sum by (service) (rate(nginx_ingress_controller_upstream_server_response_latency_ms_count[15m]))` | 1 | 0: no user traffic in the window |
| API requests by route | `sum by (route) (rate(finsight_api_requests_total[15m]))` | 7 | 2 (health probes) |
| Services known to kube-state-metrics | `count by (namespace) (kube_service_info)` | 8 | 8 |

## Dashboards provisioned in Grafana

These are relevant to G05.2:
- Kubernetes / Compute Resources / Nodes Overview
- Kubernetes / Compute Resources / Node (Pods)
- Node Exporter / Nodes
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / Compute Resources / Pod
- Kubernetes / Networking / Namespace (Pods)
- FinSight / Service overview

G05.2 also requires dashboard screenshots with timestamps. Those are captured manually and are not
part of this note.

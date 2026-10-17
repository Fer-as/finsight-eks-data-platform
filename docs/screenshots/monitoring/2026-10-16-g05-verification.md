# G05 monitoring verification (live)

Captured 2026-10-16 08:36:35Z via the Kubernetes API proxy to Prometheus (no credentials used). Traffic: 480 HTTPS requests to https://eks.feras-dev.co.uk over 94 s (verified TLS) shortly before capture.

## Components
```
NAME                                                   READY   STATUS    RESTARTS   AGE
monitoring-grafana-5569c68477-vqxvw                    3/3     Running   0          115m
monitoring-kube-prometheus-operator-58d779fb9b-gpp25   1/1     Running   0          115m
monitoring-kube-state-metrics-fb6768fcf-bc68f          1/1     Running   0          115m
monitoring-prometheus-node-exporter-2bxtc              1/1     Running   0          115m
monitoring-prometheus-node-exporter-skd2r              1/1     Running   0          115m
prometheus-monitoring-kube-prometheus-prometheus-0     2/2     Running   0          115m

NAME                                    VERSION              RETENTION
monitoring-kube-prometheus-prometheus   v3.15.0-distroless   2d

ServiceMonitors: finsight/finsight-api, monitoring/monitoring-grafana, monitoring/monitoring-kube-prometheus-apiserver, monitoring/monitoring-kube-prometheus-coredns, monitoring/monitoring-kube-prometheus-kubelet, monitoring/monitoring-kube-prometheus-operator, monitoring/monitoring-kube-prometheus-prometheus, monitoring/monitoring-kube-state-metrics, monitoring/monitoring-prometheus-node-exporter, nginx-ingress/nginx-ingress-controller
Grafana dashboards provisioned: 25 (finsight.json, k8s-resources-cluster/namespace/node/pod/workload, namespace-by-pod, ...)
```

## Targets
```
active targets up: 20/20
apiserver                              2/2 up
coredns                                2/2 up
finsight-api                           1/1 up
kubelet                                6/6 up
kube-state-metrics                     1/1 up
monitoring-grafana                     1/1 up
monitoring-kube-prometheus-operator    1/1 up
monitoring-kube-prometheus-prometheus  2/2 up
nginx-ingress-prometheus-service       2/2 up
node-exporter                          2/2 up
```

## FinSight dashboard queries (evaluated at capture time, 5m windows)
```
API /api/health/live     200 0.1 req/s
API /api/health/ready    200 0.322 req/s
API /api/departments     200 0.222 req/s
API /api/dashboard       200 0.222 req/s
API /api/config          200 0.222 req/s
API /api/transactions    200 0.222 req/s
API /api/dashboard       422 0.214 req/s
API p95 /api/health/ready    0.0177 s
API p95 /api/departments     0.0099 s
API p95 /api/dashboard       0.0238 s
API p95 /api/config          0.0048 s
API p95 /api/transactions    0.0242 s
API p95 /api/health/live     0.0048 s
NGINX upstream code 200 1.287 req/s
NGINX upstream code 404 0 req/s
NGINX upstream code 304 0 req/s
NGINX upstream code 422 0.158 req/s
NGINX p95 upstream latency nginx-ingress-prometheus-service 19.2 ms
pod memory finsight-postgres-0 41.7 MiB
pod memory finsight-frontend-<hash> 3.2 MiB
pod memory finsight-api-<hash> 46.6 MiB
API 5xx ratio: no series (no 5xx responses; panel shows 'No data')
```

## Alert rules
```
alert groups 16, alerting rules 136 (health ok 136); recording rules 86
FinSightApiDown            inactive severity=critical for=120s
FinSightApiHighErrorRate   inactive severity=warning for=300s
firing: Watchdog (always, by design); PrometheusNotConnectedToAlertmanagers (Alertmanager intentionally disabled); KubeCPUOvercommit (2 nodes cannot absorb the loss of one node)
```

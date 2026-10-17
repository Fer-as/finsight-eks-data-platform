# Monitoring evidence (G05.1, R4.3)

Captured 2026-10-16 06:48:42Z via the Kubernetes API proxy (no port-forward). Grafana admin credentials come from secretKeyRef grafana-admin (values not read).

```
NAME                                                   READY   STATUS    RESTARTS   AGE
monitoring-grafana-5569c68477-vqxvw                    3/3     Running   0          7m35s
monitoring-kube-prometheus-operator-58d779fb9b-gpp25   1/1     Running   0          7m35s
monitoring-kube-state-metrics-fb6768fcf-bc68f          1/1     Running   0          7m35s
monitoring-prometheus-node-exporter-2bxtc              1/1     Running   0          7m35s
monitoring-prometheus-node-exporter-skd2r              1/1     Running   0          7m34s
prometheus-monitoring-kube-prometheus-prometheus-0     2/2     Running   0          7m20s

target apiserver                              up 2/2
target coredns                                up 2/2
target finsight-api                           up 1/1
target kubelet                                up 6/6
target kube-state-metrics                     up 1/1
target monitoring-grafana                     up 1/1
target monitoring-kube-prometheus-operator    up 1/1
target monitoring-kube-prometheus-prometheus  up 2/2
target nginx-ingress-prometheus-service       up 2/2
target node-exporter                          up 2/2
```

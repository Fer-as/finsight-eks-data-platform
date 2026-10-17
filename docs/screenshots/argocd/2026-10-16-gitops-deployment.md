# GitOps deployment evidence (G08.2, G08.4, G03, G05, F6)

Captured 2026-10-16 06:48:42Z on cluster finsight-dev (eu-west-2). Root Application applied 2026-10-16 06:40:47Z from main 0f20872. Identifiers redacted.

## Argo CD Applications
```
NAME                           WAVE     SYNC     HEALTH    REVISION
aws-load-balancer-controller   1        Synced   Healthy   <none>
cert-manager                   0        Synced   Healthy   <none>
cluster-issuers                1        Synced   Healthy   0f208720febeee0d6b655cc552004839bb6d6cba
external-dns                   3        Synced   Healthy   <none>
finsight                       4        Synced   Healthy   0f208720febeee0d6b655cc552004839bb6d6cba
finsight-root                  <none>   Synced   Healthy   0f208720febeee0d6b655cc552004839bb6d6cba
monitoring                     1        Synced   Healthy   <none>
nginx-ingress                  2        Synced   Healthy   <none>
```

## Platform workloads
```
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           7m43s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
cert-manager              1/1     1            1           7m50s
cert-manager-cainjector   1/1     1            1           7m50s
cert-manager-webhook      1/1     1            1           7m50s

NAME                     READY   AGE
letsencrypt-production   True    7m23s
letsencrypt-staging      True    7m23s

NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx-ingress-controller   2/2     2            2           6m38s

NAME                                       TYPE           CLUSTER-IP      EXTERNAL-IP                                                                     PORT(S)          AGE
service/nginx-ingress-controller           LoadBalancer   <ip>   k8s-nginxing-nginxing-<redacted>.elb.eu-west-2.amazonaws.com   80/TCP,443/TCP   6m38s
service/nginx-ingress-prometheus-service   ClusterIP      None            <none>                                                                          9113/TCP         6m38s

NAME           READY   UP-TO-DATE   AVAILABLE   AGE
external-dns   1/1     1            1           6m32s
```

## FinSight (in-cluster PostgreSQL, init Job, API, frontend)
```
NAME                                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-finsight-postgres-0   Bound    pvc-<id>   5Gi        RWO            finsight-gp3   <unset>                 6m15s

NAME                                 READY   AGE
statefulset.apps/finsight-postgres   1/1     6m15s

NAME                         STATUS     COMPLETIONS   DURATION   AGE
job.batch/finsight-db-init   Complete   1/1           13s        5m58s

NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/finsight-api        1/1     1            1           5m45s
deployment.apps/finsight-frontend   1/1     1            1           5m58s

NAME                                     READY   STATUS      RESTARTS   AGE
pod/finsight-api-<id>-f5fg8         1/1     Running     0          5m45s
pod/finsight-db-init-kzmcv               0/1     Completed   0          5m58s
pod/finsight-frontend-54576c7855-jhzxq   1/1     Running     0          5m58s
pod/finsight-postgres-0                  1/1     Running     0          6m15s

NAME                        TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/finsight-api        ClusterIP   <ip>   <none>        80/TCP     5m58s
service/finsight-frontend   ClusterIP   <ip>    <none>        80/TCP     5m58s
service/finsight-postgres   ClusterIP   <ip>     <none>        5432/TCP   6m15s

NAME                                 CLASS   HOSTS                 ADDRESS                                                                         PORTS   AGE
ingress.networking.k8s.io/finsight   nginx   eks.feras-dev.co.uk   k8s-nginxing-nginxing-<redacted>.elb.eu-west-2.amazonaws.com   80      5m58s
```

Known issue: ExternalDNS v0.23.0 skips the parent zone feras-dev.co.uk because --aws-zone-match-parent is not set; no eks.feras-dev.co.uk record was created (fix pending approval).

# Argo CD installation evidence (G08.1)

Captured 2026-10-16 06:16:11Z on cluster finsight-dev (eu-west-2). No passwords, tokens or account identifiers are included.

## Helm
```
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.9.7 --namespace argocd --create-namespace -f gitops/argocd/values.yaml --wait --timeout 10m
NAME: argocd | NAMESPACE: argocd | STATUS: deployed | REVISION: 1 | chart argo-cd 10.9.7 (Argo CD v3.5.4)
```

## Workloads
```
NAME                                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/argocd-applicationset-controller   1/1     1            1           82s
deployment.apps/argocd-redis                       1/1     1            1           82s
deployment.apps/argocd-repo-server                 1/1     1            1           82s
deployment.apps/argocd-server                      1/1     1            1           82s

NAME                                             READY   AGE
statefulset.apps/argocd-application-controller   1/1     81s

NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          82s
argocd-applicationset-controller-76f774b57c-xrpxm   1/1     Running   0          82s
argocd-redis-8bcf9d6fd-zxr8t                        1/1     Running   0          83s
argocd-repo-server-7dc5685585-hjc4m                 1/1     Running   0          82s
argocd-server-dbcb79ccf-xtkng                       1/1     Running   0          82s

NAME                               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
argocd-applicationset-controller   ClusterIP   <cluster-ip>    <none>        7000/TCP         84s
argocd-redis                       ClusterIP   <cluster-ip>   <none>        6379/TCP         84s
argocd-repo-server                 ClusterIP   <cluster-ip>    <none>        8081/TCP         84s
argocd-server                      ClusterIP   <cluster-ip>    <none>        80/TCP,443/TCP   84s
```

## Configuration checks
```
images: quay.io/argoproj/argocd:v3.5.4, ecr-public.aws.com/docker/library/redis:8.6.4-alpine
ingress objects: none (port-forward access only); dex and notifications: disabled
argocd-cm: admin.enabled=true, exec.enabled=false, Application health customization present
repository secrets: argocd-repo-nginx-charts (public OCI Helm repository, no credentials)
applications: none (root Application not yet applied); appprojects: default
```

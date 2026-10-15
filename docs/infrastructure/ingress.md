# Ingress: F5 NGINX Ingress Controller (G03, issue #20)

Status, 15 October 2026: **implemented locally and validated offline; not deployed.** The
EKS platform is currently destroyed, so there is no live evidence yet.

## Versions

| Item | Pin | Source |
|---|---|---|
| Ingress controller | F5 NGINX Ingress Controller **5.6.3**, NGINX Open Source (`nginx/nginx-ingress:5.6.3`) | GitHub release `v5.6.3`, 16 September 2026 |
| Helm chart | `nginx-ingress` **2.7.3**, from `oci://ghcr.io/nginx/charts/nginx-ingress` | Chart `kubeVersion: ">= 1.25.0-0"`, so Kubernetes 1.36 is in range |

This is not the retired community `ingress-nginx`. 5.6.3 is the release whose ports (80, 443,
readiness 8081) the Terraform security-group rules were verified against. v5.7.0, published on
14 October 2026, was not chosen because it is too new.

## Files

| Path | Purpose |
|---|---|
| `gitops/platform/nginx-ingress/values.yaml` | Controller values |
| `gitops/platform/nginx-ingress/application.yaml` | Argo CD Application (chart 2.7.3 plus these values). Applied once Argo CD exists (G05) |
| `gitops/apps/finsight/` | Minimal FinSight chart: API and frontend Deployments and Services, and the Ingress |

## Design

**Controller**
- Two replicas, preferably on different nodes, with a PodDisruptionBudget of `minAvailable: 1`.
- Requests of 100m CPU and 256Mi memory, with a 512Mi memory limit. This fits the two
  m7i-flex.large workers (2 vCPU, 8 GiB each).
- IngressClass `nginx` (`nginx.org/ingress-controller`), not the default class.
- Custom resources and snippets disabled; `server-tokens` off.

**Service and load balancer**
- `type: LoadBalancer` with `loadBalancerClass: service.k8s.aws/nlb`, so the AWS Load Balancer
  Controller v3.6.0 (already planned, Pod Identity role in Terraform) creates an
  **internet-facing NLB in the public subnets** with **IP targets** on the NGINX pods in the
  private subnets.
- `allocateLoadBalancerNodePorts: false` and `externalTrafficPolicy: Cluster`.
- The annotations are those in [network-security.md](network-security.md): health checks on
  8081 at `/nginx-ready`, and backend security-group rules left to Terraform.
- The **security group annotation is supplied at install time** from the platform output
  `network.public_ingress_security_group_id`. It must be present when the Service is first
  created, because AWS cannot add security groups to an existing NLB.

**Routing** (host `eks.feras-dev.co.uk`)
- `/api` (Prefix) goes to `finsight-api:80`, which targets port 8000. FastAPI's routes already
  start with `/api`, so nothing is rewritten.
- `/` (Exact) and `/assets` (Prefix) go to `finsight-frontend:80`, which targets port 8080. The
  frontend has no client-side routes.
- Every other path, and every other host, gets NGINX's own 404 (G03.4).

**TLS preparation (G04)**
- `ingress.tls.enabled=true` adds `tls` for the host with secret `finsight-tls`, and the
  annotation `cert-manager.io/cluster-issuer` (default `letsencrypt-staging`).
- cert-manager issues the certificate by DNS-01
  ([dns-and-certificates.md](dns-and-certificates.md)).
- Once the Ingress has TLS, F5 NGINX redirects HTTP to HTTPS (301) by default, through the
  ConfigMap key `ssl-redirect`.

**App pods:** non-root, read-only root filesystem, all capabilities dropped, RuntimeDefault
seccomp, and no service-account token. The API probes are `/api/health/ready` and
`/api/health/live`.

## Dependencies (not fabricated)

- **Production images (G07).** `apps/frontend/Dockerfile` target `production` serves the built assets on 8080 as UID 101, and `apps/api/Dockerfile` target `api` serves on 8000 as UID 10001. The API reads its `PG*` settings from the Secret named by `api.databaseSecretName` (default `finsight-database`), which is created with the database.
- **Images in ECR.** The image repositories and tags are required values; the chart refuses to
  render without them. Their URLs come from the foundation output `repository_urls`.
- **AWS Load Balancer Controller.** It must be running before NGINX is installed. Its values
  are in [load-balancer-controller.md](load-balancer-controller.md).
- **Argo CD (G05)** for the managed install that G03.1 asks for. Until then, `helm` installs
  the same pinned chart and values.

## Deployment sequence (later, needs the platform deployed and approval)

```powershell
# 0. Platform applied by a human; kubectl context = finsight-dev via the eks-admin role.
$sg = terraform -chdir=infra/terraform/environments/dev/platform output -json network | ConvertFrom-Json
# 1. AWS Load Balancer Controller 3.6.0 (values in load-balancer-controller.md), then wait for it.
# 2. NGINX Ingress Controller.
helm upgrade --install nginx-ingress oci://ghcr.io/nginx/charts/nginx-ingress --version 2.7.3 `
  --namespace nginx-ingress --create-namespace -f gitops/platform/nginx-ingress/values.yaml `
  --set-string "controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-security-groups=$($sg.public_ingress_security_group_id)"
# 3. FinSight (after the production images are pushed).
helm upgrade --install finsight gitops/apps/finsight --namespace finsight --create-namespace `
  --set api.image.repository=<api repo URL> --set api.image.tag=<tag> `
  --set frontend.image.repository=<frontend repo URL> --set frontend.image.tag=<tag>
```

## Verification (G03 evidence)

```powershell
kubectl -n nginx-ingress get pods,svc,pdb -o wide          # 2/2 Running; EXTERNAL-IP = NLB DNS name
helm -n nginx-ingress list                                   # chart nginx-ingress-2.7.3, app 5.6.3
aws elbv2 describe-load-balancers --region eu-west-2 --query "LoadBalancers[?starts_with(LoadBalancerName,'k8s-')].[Scheme,Type,AvailabilityZones[].SubnetId]"   # internet-facing, network, public subnets
aws elbv2 describe-target-health --region eu-west-2 --target-group-arn <arn>   # pod IPs healthy on 8081
kubectl -n finsight get ingress finsight                     # class nginx, host, ADDRESS = NLB
$nlb = kubectl -n nginx-ingress get svc nginx-ingress-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
curl.exe -s -o NUL -w "%{http_code}`n" -H "Host: eks.feras-dev.co.uk" "http://$nlb/"                 # 200 frontend
curl.exe -s -H "Host: eks.feras-dev.co.uk" "http://$nlb/api/health/live"                              # API response
curl.exe -s -o NUL -w "%{http_code}`n" -H "Host: eks.feras-dev.co.uk" "http://$nlb/not-a-route"       # 404 (NGINX)
curl.exe -s -o NUL -w "%{http_code}`n" -H "Host: wrong.example" "http://$nlb/"                        # 404 (NGINX)
# After G04 (TLS on): http:// returns 301 to https://; https://eks.feras-dev.co.uk/ returns 200.
```

## Local validation, 15 October 2026

- **Helm v3.22.0** (container): `helm pull` of chart 2.7.3; `helm lint` passes for both charts;
  `helm template` renders 12 controller objects and 5 app objects, with TLS on and off.
- **Missing image:** the app chart refuses to render without one.
- **kubeconform v0.8.0, strict, Kubernetes 1.36.0 schemas:** 23 of 23 resources valid,
  including the Argo CD Application through the CRD catalog.
- **Checked in the rendered output:**
  - every NLB annotation, plus the load-balancer class
  - no NodePorts
  - readiness on 8081 at `/nginx-ready`
  - two replicas with the disruption budget
  - IngressClass `nginx`
  - the host and the three paths, and that every backend Service exists
  - the TLS block and cert-manager annotation when enabled

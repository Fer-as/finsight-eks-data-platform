# Network security groups and traffic flows

Decision record, 14 October 2026 (issue #7), written when the rules were defined in Terraform
and tested offline. They were **applied** with the platform root on 16 October 2026 and
**confirmed in AWS on 18 October 2026** with read-only `describe-security-groups` checks: the
deployed rules match this design
([evidence](../screenshots/eks/2026-10-18-network-iam-security-verification.md#g024-security-groups-every-group-in-the-vpc)).

## Design in one paragraph

The cluster keeps the **EKS-created cluster security group**, which EKS attaches to the
control-plane network interfaces and to managed nodes. Because the VPC CNI gives pods
addresses on the node interfaces, pods share it too. Everything inside the cluster talks over
that group. The only way in from outside is a separate, Terraform-owned **public ingress
security group** for the internet-facing NLB. It accepts 80 and 443 from the internet and may
send only to the ingress controller's pod ports in the private subnets. One Terraform-owned
rule on the cluster group lets that NLB group reach those pod ports. Nodes have no public IP
addresses, no SSH and no public NodePorts.

## Security groups

| Group | Owner | Attached to | Purpose |
|---|---|---|---|
| EKS cluster security group | EKS (rules below), plus one Terraform rule set | Control-plane ENIs, managed nodes, pods | Control plane ↔ kubelet, node registration, pod-to-pod, CoreDNS, add-ons |
| `finsight-dev-public-ingress` | Terraform (`modules/network`) | The NLB, by the AWS Load Balancer Controller from the Service annotation | The only internet-facing entry point |
| VPC default security group | Terraform (`aws_default_security_group`) | Nothing | Kept with no rules so nothing can accidentally use it |

No custom node security group is added. If the launch template named its own groups, EKS
would stop attaching the cluster group to nodes and every control-plane and add-on path would
have to be rebuilt by hand. The AWS Load Balancer Controller also expects exactly one
security group per node interface carrying the `kubernetes.io/cluster/<name>` tag. Keeping the
cluster group avoids both risks.

## Rules

### EKS cluster security group (EKS-managed)

| Direction | Source / destination | Ports | Why |
|---|---|---|---|
| Inbound | The cluster security group itself | All | Control plane → kubelet (10250) and webhooks; node ↔ node and pod ↔ pod traffic; CoreDNS (53); add-on and metrics traffic. EKS creates this rule. |
| Outbound | 0.0.0.0/0 | All | Nodes and pods reach the EKS API, ECR, S3 (gateway endpoint), STS and EKS Auth (Pod Identity), and through the NAT gateway public registries, Let's Encrypt and Route 53. EKS creates this rule. Restricting it is deferred; see "Known limits". |

Nothing outside the group can reach it, except through the rule below.

### Terraform rule added to the cluster security group

| Direction | Source | Ports | Why |
|---|---|---|---|
| Inbound | `finsight-dev-public-ingress` (security-group reference) | TCP 80, 443, 8081 | The NLB sends client traffic to F5 NGINX on its container ports 80 and 443, and health checks to its readiness port 8081 (`/nginx-ready`). Traffic goes straight to pod IPs (NLB IP target mode). |

Defined in the platform root as `aws_vpc_security_group_ingress_rule.nlb_to_ingress_pods`.
The ports come from `modules/network` (`ingress_target_ports`).

### Public ingress security group (NLB)

| Direction | Source / destination | Ports | Why |
|---|---|---|---|
| Inbound | 0.0.0.0/0 | TCP 443 | Public HTTPS to the application hostname. This is intentional public access. |
| Inbound | 0.0.0.0/0 | TCP 80 | Only so NGINX can redirect HTTP to HTTPS (G03.4). No content is served over HTTP. |
| Outbound | Each private subnet CIDR | TCP 80, 443, 8081 | NLB to ingress pods and their health checks; six rules (two subnets × three ports). |

Terraform removes AWS's default allow-all egress from this group, so it has no other outbound
path. Module validations reject any public listener port other than 80 or 443, and reject
22 and 3389 as target ports.

## Traffic flows

| Flow | Path | Allowed by |
|---|---|---|
| User → application | Internet → NLB (public subnets, 443) → NGINX pod (private subnets, 443) → app Service | Public ingress group inbound 443 and outbound; cluster group rule from the NLB group |
| HTTP redirect | Internet → NLB (80) → NGINX pod (80) → 301 to HTTPS | Same, port 80 |
| NLB health checks | NLB nodes → NGINX pod 8081 | Public ingress group outbound 8081; cluster group rule |
| NGINX → API / frontend pods | Pod to pod inside the cluster | Cluster group self-reference |
| API → PostgreSQL | Pod to pod (5432) inside the cluster | Cluster group self-reference; never exposed by any load balancer |
| Control plane → nodes | EKS ENIs → kubelet 10250, webhooks | Cluster group self-reference |
| Nodes → control plane | Private endpoint (443) | Cluster group self-reference |
| Operator → Kubernetes API | Public endpoint, only from the configured /32, or the private endpoint | EKS endpoint CIDR allow-list (not a security group) |
| Pods → AWS APIs, registries, Let's Encrypt | Private subnet → NAT gateway or S3 gateway endpoint | Cluster group outbound |
| DNS | Pods → CoreDNS → VPC resolver | Cluster group self-reference; the Amazon-provided resolver is not filtered by security groups |
| Prometheus scraping | Pod to pod (e.g. 9100, 9113, 8080) | Cluster group self-reference |

## What is deliberately not reachable

- **Worker nodes:** private subnets, no public IP (`map_public_ip_on_launch = false`), no SSH
  key and no `remote_access` on the node group, IMDSv2 required with hop limit 1. Tested in
  `modules/eks/tests` and `modules/network/tests`.
- **NodePorts:** the NLB uses IP targets, and nothing outside the cluster group can reach a
  node port. When NGINX is installed (#20), set `allocateLoadBalancerNodePorts: false` on its
  Service so no NodePorts are allocated at all.
- **PostgreSQL, Argo CD, Grafana, Prometheus:** cluster-internal only. Argo CD and Grafana are
  reached through `kubectl port-forward` or an authenticated NGINX route, never their own
  load balancer.
- **SSH and RDP:** never opened; no bastion host.

## Settings the later installs must use

For the F5 NGINX Service (#20), with the AWS Load Balancer Controller (#34; controller values and
identity in [load-balancer-controller.md](load-balancer-controller.md)):

```yaml
service.beta.kubernetes.io/aws-load-balancer-type: external
service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
service.beta.kubernetes.io/aws-load-balancer-security-groups: <public_ingress_security_group_id output>
service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules: "false"
service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "8081"
service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: /nginx-ready
service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: http
```

Verified against the AWS Load Balancer Controller v3.6.0 service-annotation documentation:
when a frontend security group is supplied, the controller does not add backend rules unless
told to, so the Terraform rule above is the single owner of that access. Port 80, 443 and
8081 defaults were verified against the F5 NGINX Ingress Controller v5.6.3 Helm chart. If a
different chart version changes these ports, update `ingress_target_ports` first.

The platform output `network.public_ingress_security_group_id` supplies the group ID. The
annotation must be present when the Service is first created: AWS can only give an NLB
security groups at creation time, so an NLB created without them would have to be replaced.

## Known limits and uncertainty

- **Cluster group egress stays open (0.0.0.0/0).** It is EKS-managed, and pods need several
  AWS endpoints, public registries and Let's Encrypt through the NAT gateway. Narrowing it
  without VPC interface endpoints would break image pulls or certificate issuance. Revisit
  together with Kubernetes NetworkPolicies.
- **Pod-to-pod traffic is not segmented by security groups.** All pods share the cluster
  group. Segmentation belongs in Kubernetes NetworkPolicies (VPC CNI network policy support),
  planned with the hardened manifests (#17).
- **Client IP preservation stays off** (the default for IP targets). Pods see the NLB's
  private address as the source, which is what the security-group reference matches. If the
  real client IP is needed, use proxy protocol v2, not client IP preservation, and re-test.
- **Observed in AWS on 18 October 2026.** The EKS-managed rules matched AWS's documented
  defaults (inbound from the group itself, all outbound), plus the Terraform rule from the NLB
  group.

## Post-deployment verification

```powershell
$sg = & $tf "-chdir=$platform" output -json network | ConvertFrom-Json
aws ec2 describe-security-groups --region eu-west-2 --group-ids $sg.cluster_security_group_id $sg.public_ingress_security_group_id
aws ec2 describe-security-group-rules --region eu-west-2 --filters Name=group-id,Values=$($sg.public_ingress_security_group_id)
```

Record in `docs/evidence/` (redacted): the cluster group's self-reference and the three NLB
rules; the public group's two inbound and six outbound rules; no other inbound source.

Carried out on 18 October 2026, and recorded in
[docs/screenshots/eks](../screenshots/eks/2026-10-18-network-iam-security-verification.md#g024-security-groups-every-group-in-the-vpc).
The cluster group had the self-reference plus the NLB group's TCP 80, 443 and 8081 rules. The public
group had TCP 80 and 443 from 0.0.0.0/0, and TCP 80, 443 and 8081 to the two private subnets only
(six outbound rules). The VPC default group had no rules.

## Checkov

`CKV2_AWS_5` (security group not attached to a resource) is skipped on the public ingress
group only, because the controller attaches it outside Terraform. A test scan without the
skip produced exactly this one failure. Checkov did not flag public port 80
(`CKV_AWS_260`) because it cannot resolve the port through `for_each`; the public port 80
decision is recorded here instead of being suppressed.

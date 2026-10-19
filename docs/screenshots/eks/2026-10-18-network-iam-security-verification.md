# G02 and G03.2 live verification: network, nodes, IAM, security groups and NLB

Captured 2026-10-18 from the live `finsight-dev` platform in eu-west-2. The checks used only
read-only AWS CLI calls (`describe-*`, `list-*`, `get-*`) and `kubectl get`.

Account IDs, resource IDs, IP addresses, the API endpoint, the OIDC issuer, the NLB hostname and
IAM user names are replaced with labels such as `public-a` or `<acct>`.

## G02.1 Network

```
VPC 10.42.0.0/16
public-a   eu-west-2a 10.42.0.0/24   mapPublicIpOnLaunch=False  0.0.0.0/0 -> igw-1 (active)   elb tag
public-b   eu-west-2b 10.42.1.0/24   mapPublicIpOnLaunch=False  0.0.0.0/0 -> igw-1 (active)   elb tag
private-a  eu-west-2a 10.42.16.0/20  mapPublicIpOnLaunch=False  0.0.0.0/0 -> nat-1 (active)   S3 endpoint route  internal-elb tag
private-b  eu-west-2b 10.42.32.0/20  mapPublicIpOnLaunch=False  0.0.0.0/0 -> nat-1 (active)   S3 endpoint route  internal-elb tag
Internet gateways attached: 1    NAT gateways available: 1 (nat-1 in public-a, with a public IP)
VPC endpoint: Gateway com.amazonaws.eu-west-2.s3, available, on both private route tables
Flow log: ACTIVE, traffic ALL -> CloudWatch Logs /finsight/finsight-dev/vpc-flow
```

## G02.2 Cluster and managed node group

```
Cluster finsight-dev: ACTIVE, Kubernetes 1.36, platform eks.15, support STANDARD
API endpoint: public + private; public access limited to 1 CIDR (0.0.0.0/0 not allowed)
Node group finsight-dev-workers: ACTIVE, m7i-flex.large, ON_DEMAND, min 2 / desired 2 / max 3,
  AL2023_x86_64_STANDARD 1.36.4-20261003, subnets private-a + private-b only, remote access (SSH) none
Launch template: HttpTokens=required, hop limit 1; root /dev/xvda gp3 30 GiB Encrypted=true; no custom SGs
node-a  m7i-flex.large  eu-west-2a  private-a  public IP none  ENIs with a public IP: 0/3  IMDS tokens=required  SG sg-eks-cluster
node-b  m7i-flex.large  eu-west-2b  private-b  public IP none  ENIs with a public IP: 0/3  IMDS tokens=required  SG sg-eks-cluster
Root volumes: gp3 30 GiB, encrypted, on both nodes
PostgreSQL PVC finsight/data-finsight-postgres-0: gp3 5 GiB, encrypted, in-use
kubectl: node-a Ready (eu-west-2a), node-b Ready (eu-west-2b); neither has an ExternalIP
Add-ons ACTIVE with 0 health issues: aws-ebs-csi-driver v1.66.0-eksbuild.1, coredns v1.14.7-eksbuild.10,
  eks-pod-identity-agent v1.3.10-eksbuild.3, kube-proxy v1.36.0-eksbuild.25, vpc-cni v1.22.4-eksbuild.3
```

## G02.3 IAM roles

No role has `AdministratorAccess`, `PowerUserAccess` or `IAMFullAccess`. No inline or customer-managed
policy allows `*` on `*`.

```
finsight-dev-cluster             EKS cluster      AmazonEKSClusterPolicy                               boundary  trust eks.amazonaws.com
finsight-dev-node                node group       AmazonEKSWorkerNodePolicy, AmazonEC2ContainerRegistryPullOnly  boundary  trust ec2.amazonaws.com
finsight-dev-vpc-cni             kube-system/aws-node                      AmazonEKS_CNI_Policy        boundary  trust pods.eks.amazonaws.com
finsight-dev-ebs-csi             kube-system/ebs-csi-controller-sa         AmazonEBSCSIDriverPolicyV2  boundary  trust pods.eks.amazonaws.com
finsight-dev-aws-load-balancer-controller  kube-system/aws-load-balancer-controller  inline workload  boundary  trust pods.eks.amazonaws.com
finsight-dev-external-dns        external-dns/external-dns                 inline workload             boundary  trust pods.eks.amazonaws.com
finsight-dev-cert-manager        cert-manager/cert-manager                 inline workload             boundary  trust pods.eks.amazonaws.com
finsight-dev-etl                 finsight/finsight-etl                     inline workload             boundary  trust pods.eks.amazonaws.com
finsight-dev-flow-logs           VPC flow logs                             inline write-flow-logs      boundary  trust vpc-flow-logs.amazonaws.com
finsight-dev-github-infra-plan   GitHub OIDC                               inline read-platform-for-plan          trust GitHub OIDC provider
finsight-dev-github-infra-apply  GitHub OIDC                               4 scoped managed policies + inline platform-state-only  trust GitHub OIDC provider
finsight-dev-github-images       GitHub OIDC                               inline publish-application-images      trust GitHub OIDC provider
finsight-dev-eks-admin           operator                                  inline describe-cluster                trust <iam-user>
```

The roles and their attachments match the roles documented in `docs/infrastructure/terraform-ci.md`,
`dns-and-certificates.md` and `load-balancer-controller.md`. Policy statements were not compared
line by line here. The PR plan (run 38896532913) and the protected apply plan (run 38901260888)
refreshed these resources and proposed only the flow-log tag change. That shows the live IAM matched
the Terraform definitions, whose policy scopes are covered by `terraform test`.

## G02.4 Security groups (every group in the VPC)

```
sg-default                      inbound 0 rules, outbound 0 rules
sg-eks-cluster (EKS-managed)    in  all            from sg-eks-cluster (EKS default: control plane, nodes, pods)
                                in  tcp/80,443,8081 from sg-finsight-dev-public-ingress (Terraform rule: NLB to ingress pods + health check)
                                out all            to 0.0.0.0/0 (EKS default, documented)
sg-finsight-dev-public-ingress  in  tcp/80, tcp/443 from 0.0.0.0/0 (public NLB listeners)
                                out tcp/80,443,8081 to 10.42.16.0/20 and 10.42.32.0/20 only
Inbound rules open to 0.0.0.0/0: only tcp/80 and tcp/443 on sg-finsight-dev-public-ingress
EKS API public access: 1 explicit CIDR
```

Every inbound rule has a named source. This matches `docs/infrastructure/network-security.md`.

## G03.2 Load balancer and workload placement

```
NLB: network, internet-facing, active, IPv4; subnets public-a + public-b (== the Terraform public subnets); SG sg-finsight-dev-public-ingress
Listeners: TCP 80, TCP 443; target groups type ip, health check HTTP 8081 /nginx-ready, all targets healthy
Service nginx-ingress/nginx-ingress-controller: LoadBalancer, class service.k8s.aws/nlb, internet-facing, target type ip, SG annotation set
Pods: finsight-api, finsight-frontend, finsight-postgres-0 Running on node-a (private-a); db-init Succeeded;
      nginx-ingress-controller x2 Running on node-a and node-b (private subnets)
```

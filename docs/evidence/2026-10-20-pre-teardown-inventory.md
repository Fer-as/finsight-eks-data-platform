# Pre-teardown inventory (R12.1, R12.2), 20 October 2026

A read-only inventory of the FinSight platform in eu-west-2, taken before teardown. It used only
describe, list and get calls, `kubectl get`, a read-only `SELECT`, and `terraform state list`. The raw
output is kept privately. Here, IDs, the account and the hosted zone are omitted.

## Platform (to be removed)

| Area | State on 20 October 2026 |
|---|---|
| EKS | `finsight-dev`, Kubernetes 1.36, ACTIVE; 5 add-ons; 6 Pod Identity associations; 3 access entries |
| Nodes | Managed group `finsight-dev-workers`: 2 × `m7i-flex.large` on demand, one in each AZ, both Ready |
| Network | 1 VPC (10.42.0.0/16), 4 subnets, 4 route tables, 1 internet gateway, 1 NAT gateway with 1 Elastic IP, 1 S3 gateway endpoint, 1 flow log |
| Load balancing | 1 internet-facing NLB created by the AWS Load Balancer Controller, TCP 80 and 443, 2 IP target groups with healthy targets |
| Storage | 3 encrypted gp3 volumes: 2 × 30 GiB node root volumes (deleted with the instances) and 1 × 5 GiB PostgreSQL volume; no snapshots |
| DNS | 4 records created by ExternalDNS: `eks` A and AAAA aliases to the NLB, and the `a-eks` and `aaaa-eks` TXT ownership records |
| Logs | `/aws/eks/finsight-dev/cluster` and `/finsight/finsight-dev/vpc-flow`, 7-day retention |
| IAM | 9 platform roles |
| Terraform | Platform state holds 68 resources |
| Database | `curated` tables: 3 departments, 288 entries, 36 budgets, 10,000 transactions (the deterministic dataset); 3 ETL audit rows; 9.8 MB |

## Not in Terraform state

| Resource | Created by | Removed by |
|---|---|---|
| NLB, its 2 listeners and 2 target groups | AWS Load Balancer Controller | Deleting the NGINX `LoadBalancer` Service while the controller runs |
| 4 Route 53 records | ExternalDNS (`upsert-only`, so it never deletes them) | Explicit removal of exactly those records |
| 5 GiB PostgreSQL EBS volume | EBS CSI driver, from PVC `data-finsight-postgres-0` (reclaim policy `Delete`) | Deleting the PVC while the driver runs |
| EKS cluster security group, node launch template and the CNI and control-plane network interfaces | EKS | EKS, when the cluster and node group are deleted |

## Retained

- **S3:** the state bucket, the access-log bucket and the data bucket.
- **ECR:** the three immutable repositories, with one image each (about 230 MB in total).
- **Foundation IAM:** the GitHub plan, apply and image roles, the workload boundary and the apply
  policies.
- **Outside Terraform:** the `finsight-dev-eks-admin` role, the GitHub OIDC provider and the hosted
  zone.

## Cost

Usage from 17 to 19 October 2026 was about USD 10 a day. Credits offset the month-to-date total. The
largest items were EC2 instances, the EKS control plane, the NAT gateway and EBS, then load
balancing.

# IAM policy statement review (G02.3), 20 October 2026

On 20 October 2026 I reviewed the trust policy, permissions boundary, attached policies and inline
policies of all 13 FinSight IAM roles, statement by statement. The source was a read-only capture taken
on 18 October 2026 (`iam get-role`, `list-attached-role-policies`, `list-role-policies`,
`get-role-policy`, and `get-policy-version` for each customer-managed policy). I compared each
statement with the Terraform that defines it and with
[Terraform CI](../../infrastructure/terraform-ci.md) and
[DNS and certificates](../../infrastructure/dns-and-certificates.md).

The capture is kept privately. Here, account IDs, the hosted zone ID, the bucket suffix, the GitHub
numeric owner and repository IDs, and the administrator's IAM user name are replaced with placeholders.

## Result by role

85 statements in the inline and customer-managed policies were reviewed. The boundary and the
AWS-managed policies are covered [below](#boundary-and-aws-managed-policies-read-20-october-2026).

| Role | Boundary | Trust | Permissions (statements reviewed) |
|---|---|---|---|
| `finsight-dev-cluster` | workload boundary | `eks.amazonaws.com` | AWS-managed `AmazonEKSClusterPolicy` only |
| `finsight-dev-node` | workload boundary | `ec2.amazonaws.com` | AWS-managed `AmazonEKSWorkerNodePolicy` and `AmazonEC2ContainerRegistryPullOnly` only |
| `finsight-dev-vpc-cni` | workload boundary | Pod Identity: `kube-system/aws-node`, cluster source ARN | AWS-managed `AmazonEKS_CNI_Policy` only |
| `finsight-dev-ebs-csi` | workload boundary | Pod Identity: `kube-system/ebs-csi-controller-sa`, cluster source ARN | AWS-managed `AmazonEBSCSIDriverPolicyV2` only |
| `finsight-dev-aws-load-balancer-controller` | workload boundary | Pod Identity: `kube-system/aws-load-balancer-controller`, cluster source ARN | Inline, 16 statements: the upstream v3.6.0 policy. Writes are limited to `k8s-*` load balancers and target groups, security groups in the account and Region, and the FinSight VPC; reads are on `*`; `CreateServiceLinkedRole` only for Elastic Load Balancing |
| `finsight-dev-cert-manager` | workload boundary | Pod Identity: `cert-manager/cert-manager`, cluster source ARN | Inline, 3 statements: `ChangeResourceRecordSets` in the FinSight zone only for TXT records named `_acme-challenge.eks.feras-dev.co.uk`; list records in that zone; `GetChange` |
| `finsight-dev-external-dns` | workload boundary | Pod Identity: `external-dns/external-dns`, cluster source ARN | Inline, 3 statements: `ChangeResourceRecordSets` in the FinSight zone only for A, AAAA and TXT records named `eks`, `a-eks` and `aaaa-eks`; list records in that zone; `ListHostedZones` on `*`, which Route 53 does not scope |
| `finsight-dev-etl` | workload boundary | Pod Identity: `finsight/finsight-etl`, cluster source ARN | Inline, 2 statements: list the data bucket; get, put and abort uploads under `raw/` and `curated/` only |
| `finsight-dev-flow-logs` | workload boundary | `vpc-flow-logs.amazonaws.com`, source ARN in this account and Region | Inline, 2 statements: write only to `/finsight/finsight-dev/vpc-flow`; `DescribeLogGroups` |
| `finsight-dev-eks-admin` | none | One IAM user, MFA required | Inline, 1 statement: `eks:DescribeCluster` on `finsight-dev`. Kubernetes access comes from its EKS access entry |
| `finsight-dev-github-images` | none | GitHub OIDC: exact `dev-images` environment subject, audience `sts.amazonaws.com` | Inline, 2 statements: push and read the three FinSight ECR repositories only; `GetAuthorizationToken` on `*`, which ECR does not scope |
| `finsight-dev-github-infra-plan` | none | GitHub OIDC: exact `dev-infrastructure` environment subject | Inline, 9 statements: read the platform state, write only its lock object; describe and list EC2, EKS, IAM (`finsight-dev-*` roles), logs and the zone. No create, update or delete action |
| `finsight-dev-github-infra-apply` | none | GitHub OIDC: exact `dev-infrastructure-apply` environment subject | 4 customer-managed policies and 1 inline policy, 47 statements, described below |

The OIDC subjects use GitHub's immutable form, `repo:Fer-as@<id>/finsight-eks-data-platform@<id>:environment:<name>`,
so a renamed or recreated repository cannot match them.

### `finsight-dev-github-infra-apply`

- **Guardrails** (9 Deny statements): no removing permissions boundaries; no policy authoring; no
  change to the GitHub roles, `eks-admin` or the OIDC and SAML providers; no users, groups, access
  keys or instance profiles; no role chaining or federation; no access to the bootstrap or foundation
  state; no resource policies; no EKS access entries outside the identity policy's statement.
- **Network** (18 statements):
  - Reads on `*`, in eu-west-2 only.
  - Each create action needs the `Project=finsight` request tag, or a parent resource that carries it.
  - Tags can be set only at creation, with `Project=finsight`.
  - Changes and deletes (32 actions) need the `Project=finsight` resource tag in eu-west-2.
  - Two statements have no condition:
    - `CreateVpcEndpoint` on AWS endpoint services;
    - security-group rule changes on rule resources. The group itself must still be tagged, or be the
      `finsight-dev` cluster security group.
- **Roles** (8 statements):
  - Create and policy changes only for the nine named platform roles, and only with the workload
    boundary.
  - A Deny on attaching any managed policy except the five approved AWS-managed policies.
  - `PassRole` only for those roles, and only to EKS, Pod Identity and VPC flow logs.
  - Service-linked roles only for four named services.
  - No removal of the `Project` tag.
  - IAM reads on `*`.
- **Identity** (9 statements): platform state and lock only; the `finsight-dev` cluster, its node
  groups, add-ons and Pod Identity associations; access entries on that cluster; the two FinSight log
  group paths; reads of the FinSight zone.
- **Inline `platform-state-only`** (3 statements): the same state and lock access as the identity
  policy. It is redundant but grants nothing extra.

## Findings

- Every trust policy names one service, one Pod Identity service account on the `finsight-dev`
  cluster, one MFA-protected user, or one exact GitHub environment subject.
- Every `Resource: "*"` statement is either a read or list action, or has a condition limiting the
  service name, the request tag and Region, or the record names.
- No statement grants `iam:*`, `s3:*` or `*:*` as an Allow.
- The roles created by the platform root carry the workload boundary. The GitHub roles and
  `eks-admin` are created by the foundation root, which does not apply it, as documented.

## Boundary and AWS-managed policies (read 20 October 2026)

After a new AWS session on 20 October 2026, I read the documents the 18 October capture did not contain:
- **`finsight-dev-workload-boundary`** (version v1, used as the boundary of 9 roles): 12 statements, the
  same Sids and actions as `modules/terraform-ci-policies/main.tf`.
  - EC2, Elastic Load Balancing and Auto Scaling are allowed only in eu-west-2.
  - Route 53 changes are allowed only in the FinSight zone; S3 only on the data bucket, with object
    access under `raw/` and `curated/`.
  - KMS use is allowed only through EC2 in eu-west-2.
  - The only IAM actions are read-only server-certificate lookups and `CreateServiceLinkedRole` for
    four named services. There is no `PassRole`, `AssumeRole` or IAM write, so no bounded role can
    escalate beyond this ceiling.
- **AWS-managed policies:**

  | Policy | Version | Statements | Notes |
  |---|---|---:|---|
  | `AmazonEKSClusterPolicy` | v10 | 3 | Only IAM action: `CreateServiceLinkedRole` |
  | `AmazonEKSWorkerNodePolicy` | v3 | 1 | No IAM actions |
  | `AmazonEC2ContainerRegistryPullOnly` | v1 | 1 | Image pull only |
  | `AmazonEKS_CNI_Policy` | v6 | 2 | No IAM actions |
  | `AmazonEBSCSIDriverPolicyV2` | v1 | 13 | No IAM actions |

  None of them allows `*`, `iam:*`, `s3:*` or `ec2:*`. For every platform role, the boundary also caps
  what these policies can grant.

The same session re-read every trust policy, boundary setting, inline policy and customer-managed
policy version. All 26 documents were identical to the 18 October capture. No Terraform apply has run
since 16 October 2026.

G02.3 is verified: every trust policy, boundary, attached policy and inline statement of the 13 roles
has been reviewed against Terraform and the documented scope.

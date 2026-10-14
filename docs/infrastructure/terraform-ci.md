# Terraform CI identities and approval gate

Decision record, 14 October 2026 (issue #8, Option A approved by the owner; independently
reviewed and hardened the same day). Defined in Terraform and tested offline; **nothing applied**.
The GitHub environments are not configured yet and there is no workflow (#10, #11).

## Roles

All three GitHub roles trust only the existing GitHub OIDC provider. That provider is shared and
owned by another project's Terraform state; FinSight references it by ARN (`create_provider =
false`) and never creates, replaces or deletes it. Each trust policy is a single `StringEquals`
on audience `sts.amazonaws.com` and on the repository's exact immutable subject plus one
environment, with no wildcards and one-hour sessions. The repository's OIDC template was
re-read on 14 October 2026: `use_immutable_subject = true`, and its `sub_claim_prefix` equals
the configured `subject_prefix` (`repo:OWNER@ID/REPO@ID`).

| Role | GitHub environment | Permissions |
|---|---|---|
| `finsight-dev-github-infra-plan` | `dev-infrastructure` | Unchanged: read platform state, its own lock object, read-only describes |
| `finsight-dev-github-images` | `dev-images` | Unchanged: push and pull the three FinSight ECR repositories |
| `finsight-dev-github-infra-apply` | `dev-infrastructure-apply` | Platform state and lock, plus the four managed policies below |

## Permissions model (Option A)

### Workload permissions boundary

`finsight-dev-workload-boundary` (managed policy, foundation root). **Every IAM role the
platform root creates must carry it**: the `pod-role`, `eks` and `network` modules take a
required `permissions_boundary` input that must end in `-workload-boundary`, and their tests
check it is set. That covers the cluster, node and flow-log roles and every Pod Identity role
(VPC CNI, EBS CSI, ETL, ExternalDNS, cert-manager, AWS Load Balancer Controller).

The boundary is the ceiling of what those roles can ever do; their own policies still apply
within it. It allows what the platform's roles need (derived from the attached AWS-managed
policies and the repository's inline policies):

| Allowed | Why |
|---|---|
| `ec2:*`, `elasticloadbalancing:*`, `autoscaling:*` in eu-west-2 only | EKS cluster role, VPC CNI, EBS CSI, load balancer controller |
| `eks:DescribeCluster`, `eks-auth:AssumeRoleForPodIdentity` | Nodes and the Pod Identity agent |
| ECR image pull | Nodes |
| CloudWatch Logs stream writes in eu-west-2 | VPC flow logs |
| Route 53 changes and reads on the one hosted zone; zone discovery and `GetChange` | ExternalDNS, cert-manager |
| S3 list on the data bucket; get/put on `raw/` and `curated/` | ETL |
| ACM, Cognito, WAF and Shield reads; IAM server-certificate reads | Load balancer controller lookups |
| `iam:CreateServiceLinkedRole` for EKS, node groups, Auto Scaling, ELB only | Cluster and controller |
| KMS grant and data-key actions only via EC2 in eu-west-2; `kms:DescribeKey` | Encrypted EBS volumes |

It never allows creating or changing IAM roles or policies, passing roles, assuming roles,
or reaching the Terraform state bucket. Every action in the roles' current identity policies
falls inside it (checked statement by statement during the review); the load balancer
controller's WAF and Shield write actions were already removed from its own policy.

### CI apply role

Four managed policies built by `modules/terraform-ci-policies` and attached to
`finsight-dev-github-infra-apply` (plus the existing inline platform-state policy):

- **roles:** The apply role can manage only the nine platform roles, named exactly:
  `finsight-dev-` followed by `cluster`, `node`, `flow-logs`, `vpc-cni`, `ebs-csi`,
  `aws-load-balancer-controller`, `etl`, `external-dns` or `cert-manager`. Other roles that
  merely share the prefix are not covered. On those nine roles it can:
  - Create roles, change permissions boundaries, and add, remove, attach or detach role policies, **only when the role's boundary is the FinSight boundary** (`iam:PermissionsBoundary`).
  - Update trust, settings and tags, or delete the role, only on those names when tagged `Project=finsight`.
  - Attach only the five approved AWS-managed policies.
  - Pass only those roles with `iam:PassRole`, and only to `eks`, `pods.eks` and `vpc-flow-logs` (`iam:PassedToService`).

  It can also create the service-linked roles for EKS, node groups, Auto Scaling and ELB, and it
  can't remove the `Project` ownership tag.
- **identity:**
  - Platform state and lock only.
  - EKS cluster, node group, add-on and Pod Identity operations only on the `finsight-dev` cluster; access entries and access policies only for the configured administrator role(s) (`eks:principalArn`).
  - Log groups only under `/aws/eks/finsight-dev/` and `/finsight/finsight-dev/`.
  - Read the one hosted zone.
- **network:**
  - EC2 reads in eu-west-2.
  - Each create action is allowed only on the resource type it creates, with the request tag `Project=finsight`. This covers VPCs, subnets, internet and NAT gateways, Elastic IPs, route tables, security groups, launch templates, flow logs and endpoints.
  - **Every existing resource a creation also touches** (the VPC, subnet, Elastic IP, route tables or security groups) must already be tagged `Project=finsight`.
  - Tag only as part of those creations; change or delete only `Project`-tagged resources.
  - Security group rules (ingress and egress) are allowed only where their security group is FinSight-owned or is the EKS cluster security group. EKS identifies that group with its own `aws:eks:cluster-name` tag, and that group gets ingress changes only.
  - **There is no permission to tag an existing untagged resource.**
- **guardrails (explicit denies, which win):**
  - Removing permissions boundaries.
  - Creating or changing any IAM managed policy, including the boundary.
  - Any IAM action on the GitHub roles and the EKS administrator role.
  - Any OIDC or SAML provider action.
  - Creating users, groups, access keys, login profiles or instance profiles.
  - Assuming any role, or getting federation tokens.
  - Any access to bootstrap or foundation state.
  - Resource-based policy changes (bucket policies and ACLs, ECR repository policy, KMS key policy and grants, log resource policy, Lambda, SNS, SQS).
  - Cluster access for any principal other than the administrator role(s).

### Cross-project isolation

`aws:RequestTag` applies to the whole request, so a create action allowed only by a request tag
would also be authorised against *existing* resources named in the same request. For example, it
could create a subnet in another project's VPC, a NAT gateway in a foreign subnet, or a gateway
endpoint that rewrites a foreign route table. The network policy grants the request-tag
permission only on the new resource's ARN type, and requires the ownership tag on every parent.

Tagging is allowed only during creation (`ec2:CreateAction`), and changes need the ownership tag.
So another project's resource cannot be brought under FinSight's control by adding `Project=finsight`.

**Consequence: any apply that creates a VPC is human-run.** AWS creates a VPC's default security
group untagged, and Terraform (`aws_default_security_group`) must tag it and remove its rules. CI
cannot tag untagged groups, so CI cannot complete an apply that creates a VPC.

- **Initial platform deployment (and any VPC replacement):** the administrator applies a reviewed
  saved platform plan with their own credentials, after the foundation (boundary) exists. The
  administrator role can tag the new default group. CI handles later applies, once every
  FinSight network resource is tagged.

  A VPC replacement also contains deletes, so the CI destroy gate would stop it anyway.
- **If a CI apply is ever started for a new VPC by mistake,** it does not stop cleanly. Terraform
  carries on creating every resource that does not depend on the default group, and then fails
  on `aws_default_security_group` with `AccessDenied`. The provider records the group's ID
  before tagging, so the resource is expected to be left **tainted**. To recover:
  1. Confirm in the console or CLI that the group is the `default` group of the new FinSight VPC
     (tagged `Project=finsight`), and tag it `Project=finsight`.
  2. Then either:
     - **Human path (simpler):** apply a fresh reviewed plan yourself.
     - **CI path:** run `terraform untaint module.network.aws_default_security_group.this`
       yourself, then start a new CI plan and apply. Don't re-use the old plan. Without the
       untaint, the new plan shows a replacement, which the destroy gate correctly blocks. For
       this resource, the replacement only removes it from state.

### Escalation paths considered

| Path | Control |
|---|---|
| Create a powerful role | Only the nine named roles; boundary required at creation; boundary forbids IAM, PassRole and AssumeRole |
| Tag, re-trust or delete an unrelated role sharing the prefix | Role permissions name the nine roles exactly (`TagRole` cannot be limited to creation) |
| Remove, replace or edit the boundary | Explicit deny on `DeleteRolePermissionsBoundary` and all policy-version changes; `PutRolePermissionsBoundary` only to the same boundary |
| Attach admin policies | Deny unless the policy is one of the five approved AWS-managed policies (and the boundary still caps it) |
| Modify its own or other GitHub roles, or the OIDC provider | Explicit deny |
| Pass a role to a service that runs arbitrary code | `iam:PassedToService` limited to EKS, Pod Identity and VPC flow logs; only the nine roles |
| Assume a created role (role-session bypass) | Explicit deny on `sts:AssumeRole*` and federation |
| Grant itself Kubernetes admin | Access entries only for the configured administrator role |
| Resource-based policies granting access elsewhere | Explicit denies on the relevant policy actions |
| Adopt or alter another project's network | Request tag only on new resources; parents and changes need the ownership tag; no tagging of existing untagged resources |
| Change foundation or bootstrap (its own governance) | No permission, and an explicit deny on their state |

## Separation of duties

- Bootstrap and foundation (state buckets, GitHub roles and the boundary) are **human-applied
  only**. The apply role cannot read or write their state.
- The plan role is unchanged and read-only apart from its lock object.
- CI applies the **platform root only**, using a saved plan.

## Controls: implemented vs still to configure

| Control | Status |
|---|---|
| Exact immutable OIDC subject per environment, no wildcards | Implemented (Terraform, tested); applied for plan and image roles only |
| Separate plan (read-only) and apply roles | Implemented (Terraform, tested); apply role not applied |
| Apply permissions scoped, boundary mandatory | Implemented (Terraform, synthetic tests); not applied |
| Protected `dev-infrastructure-apply` environment (reviewer, `main` only) | **Not configured**: GitHub setting, below |
| No AWS credentials for untrusted pull requests | GitHub behaviour (fork PRs get no OIDC token) plus workflow rule: never `pull_request_target`; **not built** |
| Saved-plan checksum and commit binding | Workflow rule (#10/#11); **not built** |
| No unapproved destroy or replacement | Workflow rule (#10/#11); **not built**. IAM cannot express it, because the apply role must be able to delete platform resources for replacements |
| Required reviewer and self-review limits | GitHub setting; **not configured** |

## Required GitHub environment setup (for owner approval; not configured)

**Order matters.** GitHub creates an unprotected environment automatically the first time a
workflow names it. So configure `dev-infrastructure-apply` **before** the foundation apply that
creates and empowers the apply role. Until then, any collaborator branch could name the environment
and receive the role with no approval.

Repository **Settings → Environments**:

1. **`dev-infrastructure-apply`**
   - Required reviewers: the owner. If there is only one maintainer, GitHub's "Prevent
     self-review" cannot be satisfied by the person who triggered the run. Either add a second
     trusted reviewer and enable it, or accept self-approval and document that the review is of
     the saved plan, not of the code author.
   - Allow administrators to bypass: **off**.
   - Deployment branches and tags: **Selected branches → `main` only**.
   - Wait timer: optional (for example 5 minutes, to give time to cancel).
   - Secrets and variables: none for AWS. Store only the role ARN as an environment
     **variable**, taken from the foundation output.
2. **`dev-infrastructure`** (plan): no reviewers; the role is read-only. Pull-request plans must
   run on pull-request branches, so leave branch rules open. Only collaborators can trigger it,
   because fork pull requests receive no OIDC token.
3. **`dev-images`**: deployment branches `main` only.
4. Repository **Actions → General**: keep "Require approval for fork pull requests" enabled.
5. Branch protection on `main`: require pull requests and reviews, and disallow force pushes, so
   only reviewed code reaches the apply environment.

## Applying exactly what was approved (workflow rules for #10/#11)

- Never use `pull_request_target` or `workflow_run` triggers with `id-token: write`.
- The plan job runs on `main` after merge, writes `platform.tfplan`, uploads it as a short-lived
  artifact with its SHA-256, and publishes the human-readable plan in the run summary.
- The apply job declares `environment: dev-infrastructure-apply`, runs only on the same
  workflow run (`needs:` the plan job), downloads that artifact, verifies the SHA-256 and that
  `github.sha` is unchanged, then runs `terraform apply platform.tfplan`. Terraform itself
  refuses a saved plan if state changed after planning.
- If the saved plan contains any `delete` action (destroy or replacement), the apply job stops
  unless the run was started with an explicit `allow-destroy` input.
- Per-root concurrency group; no automatic `force-unlock`.

## What is not proven yet (synthetic vs real)

The tests in `modules/terraform-ci-policies/tests` evaluate the policy text with a small model
(Allow and Deny, wildcard actions and ARNs, the condition operators used here, one resource per
request; multi-resource requests are tested one resource at a time). They show that the
platform's operations are allowed. These include:
- bounded role creation
- approved PassRole
- network creation in owned parents
- ingress and egress rules
- EKS operations

They also show that these are denied:
- unbounded or unlisted roles
- boundary changes
- GitHub and OIDC changes
- wrong-service or foreign PassRole
- assume-role
- other states, other projects and other Regions
- foreign parents
- tagging untagged resources

**They are not proof of AWS's authorisation decisions.**

Unverified until the first CI apply (each is a precise fix if it fails, never a reason to widen
permissions):

- **Which resources each EC2 request is authorised against.** In particular, NAT gateway creation (subnet and Elastic IP) and gateway endpoint creation, where the AWS service resource is assumed in `EndpointServices`.
- **Security group rule authorisation.** That rule actions always authorise the parent security group, and that tagging during rule creation behaves as modelled.
- **EKS cluster security group tag.** That the cluster security group carries `aws:eks:cluster-name`.
- **Node group creation.** Whether `CreateNodegroup` with a launch template needs extra caller permissions.
- **Pod Identity PassRole service name.** The exact `iam:PassedToService` value for Pod Identity associations, and for add-on Pod Identity associations.

Residual risks:
- **Outside trust.** A created platform role could trust an outside principal, because IAM cannot
  restrict trust-policy content. Its permissions are still capped by the boundary, and the apply
  role cannot assume it; the saved-plan review is the control.
- **Boundary breadth.** The boundary's EC2, ELB and Auto Scaling allowance is Region-wide, because
  the AWS-managed EKS, CNI and EBS CSI policies use `Resource "*"`. A platform role given a broad
  inline policy, or a compromised controller pod, could therefore reach other projects' EC2
  resources in eu-west-2. Narrowing it to the exact managed-policy action lists is a later
  hardening item.
- **Routes to foreign targets.** `CreateRoute` in a FinSight route table could target another
  project's gateway. AWS authorises only the route table.
- **Visibility.** Read-only describes show other projects' metadata.

## Deployment order and expected changes

1. Configure the `dev-infrastructure-apply` environment protection (above) and approve it.
2. Foundation (human, separately approved) adds **11 resources**:
   - the boundary policy (1)
   - the apply role and its inline state policy (2)
   - four apply managed policies (4)
   - four policy attachments (4)

   Expected plan: about **11 to add**, 0 to change, 0 to destroy. This is an estimate; no plan has
   been run.
3. Only after the boundary exists can any platform plan or apply succeed, because every platform
   role references it.
4. The administrator applies the initial platform deployment from a reviewed saved plan. It
   creates the VPC, so CI cannot (see Cross-project isolation).
5. Build the workflows (#10, #11); CI then applies later platform changes.

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

Status on 14 October 2026.

| Control | Status |
|---|---|
| Exact immutable OIDC subject per environment, no wildcards | Implemented and applied (plan, image and apply roles) |
| Separate plan (read-only) and apply roles | Implemented and applied |
| Apply permissions scoped, boundary mandatory | Applied (foundation, 11 resources); synthetic tests only, no CI apply has run |
| Protected `dev-infrastructure-apply` environment | Configured: reviewer Fer-as, `main` only, administrator bypass off, variable `AWS_ROLE_ARN` |
| Protected `dev-infrastructure` environment | Configured: reviewer Fer-as, `refs/pull/*/merge` only, administrator bypass off, variable `AWS_ROLE_ARN` (plan role), secret `TERRAFORM_CONFIG_JSON` |
| `main` protected | Ruleset: pull request required (0 approvals, single maintainer), no force pushes, no deletion, no bypass |
| No AWS credentials for untrusted pull requests | Pull-request workflow (#10): `pull_request` trigger only, plan job skipped for fork heads, `permissions: {}` by default; **not yet run** |
| Plan output does not leak private values | Pull-request workflow (#10): plan text kept out of logs, values masked, summary shows actions and digests only, no binary plan artifact; **not yet run** |
| Saved-plan, commit and digest binding | Digests produced by `scripts/ci/summarize-terraform-plan.ps1`; enforcement is #11 |
| No unapproved destroy or replacement | Flagged by the plan summary; the apply gate is #11. IAM cannot express it, because the apply role must be able to delete platform resources for replacements |
| Required reviewer and self-review limits | Configured; single-maintainer self-approval, not two-person review |

## Pull-request workflow (`.github/workflows/terraform.yml`, issue #10)

- **Trigger:** `pull_request` to `main`, filtered to Terraform, the check scripts and the workflow
  itself. There is no `pull_request_target`, `workflow_run` or `workflow_dispatch` trigger.
- **`checks` job:** has no AWS access and only `contents: read`. It runs
  `scripts/validate-terraform.ps1`, the same script used locally: `fmt -check`, then `init
  -backend=false` and `validate` for all three roots, then the offline module tests, then Checkov
  from the digest-pinned image. A newer push to the same pull request cancels it. One provider
  download is shared through `TF_PLUGIN_CACHE_DIR`; the lock files carry linux_amd64 hashes for this.
- **`plan` job (platform root only):**
  - Runs after `checks`, and only when the pull request comes from this repository.
  - Uses `environment: dev-infrastructure`, and only `contents: read` and `id-token: write`.
  - Uses `configure-aws-credentials` with `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`. No stored
    keys are involved, and the account ID is masked.
  - A script checks that the session is the FinSight Terraform role in the configured account.
- **Plan steps:**
  1. `init` against the S3 backend, with a read-only lock file.
  2. `plan -lock-timeout=5m -out=platform.tfplan`, with stdout written to a temporary file. The
     plan text holds attribute values, and this public repository's logs are public. Diagnostics
     still reach the log through stderr, after masking.
  3. `scripts/ci/summarize-terraform-plan.ps1` writes the step summary. It contains counts per
     action, resource addresses (account IDs redacted), flags for a destructive plan and for a
     human-run VPC plan, the commit, the binary plan's SHA-256, and a SHA-256 of the canonical
     resource and output changes.
  4. A final step deletes the plan, the configuration and the backend files.
- **Plan concurrency:** the group is `terraform-state-dev-platform`, and `cancel-in-progress` is
  off. A run that may hold the state lock is never cancelled, and no `force-unlock` is attempted.
- **Configuration:** the ignored `config/local.json` comes from the environment secret
  `TERRAFORM_CONFIG_JSON`, through `scripts/ci/write-terraform-ci-config.ps1`.
  - The script first masks the account ID, bucket names, zone ID, administrator role ARNs, the
    operator's API CIDRs and the numeric IDs of the OIDC subject.
  - It then generates `backend.hcl`.
  - If `eks.compatibility_verified` is false, it marks the plan as skipped with a notice, and no
    AWS session is opened.
- **Pull-request plans are never applied.** The binary plan is not uploaded, because artifacts of
  a public repository are publicly downloadable.

## Required GitHub environment setup

**Order matters.** GitHub creates an unprotected environment automatically the first time a
workflow names it. Configure each environment **before** a workflow that names it first runs.

Repository **Settings → Environments**:

1. **`dev-infrastructure-apply`** (configured 14 October 2026):
   - **Required reviewers:** the owner, Fer-as.
   - **Prevent self-review:** off. With one maintainer, this is a self-approval gate: the review is
     of the saved plan, not an independent two-person review.
   - **Allow administrators to bypass:** off.
   - **Deployment branches and tags:** Selected branches, `main` only.
   - **Variable `AWS_ROLE_ARN`:** the apply role's ARN, read from AWS. It is not a secret.
   - **No AWS keys.** #11 will also need the `TERRAFORM_CONFIG_JSON` secret here.
2. **`dev-infrastructure`** (plan; configured 14 October 2026):
   - **Required reviewers:** Fer-as, with Prevent self-review off. Every pull-request plan job
     waits for the owner's approval before it can obtain the plan role. This is a deliberate owner
     choice; the role itself is read-only apart from its lock object.
   - **Allow administrators to bypass:** off.
   - **Deployment branches and tags:** Selected, with the single branch rule `refs/pull/*/merge`.
     GitHub matches the rule against the run's `GITHUB_REF`, which for `pull_request` runs is
     `refs/pull/<number>/merge`, and `*` does not match `/`. Pushes and other branches cannot use
     this environment.
   - **No wait timer.**
   - **Set 14 October 2026:**
     - variable `AWS_ROLE_ARN`: the plan role's ARN (`finsight-dev-github-infra-plan`, the
       foundation output `github_role_arns["infra_plan"]`), read from AWS
     - secret `TERRAFORM_CONFIG_JSON`: the platform subset of the ignored
       `infra/terraform/config/local.json`, with only `account_id`, `state_bucket`, `data_bucket`,
       `eks` and `dns`. `github` and `access_log_bucket` are left out because the platform root
       doesn't use them. It contains no credentials; storing it as a secret keeps private
       identifiers out of the repository and masked in logs. Re-upload it whenever those fields
       change locally, for example when the compatibility gate is passed.
3. **`dev-images`:** `main` only, with `AWS_ROLE_ARN` set to the image role's ARN. Configure it with
   the image workflow.
4. Repository **Actions → General**: keep "Require approval for fork pull requests" enabled.
5. `main`: protected by the repository ruleset described above.

Workflows reference role ARNs only as `${{ vars.AWS_ROLE_ARN }}`, from a job that names its
environment explicitly. They never contain an `arn:aws` literal.

## Applying exactly what was approved (rules for #11)

- Never use `pull_request_target` or `workflow_run` triggers with `id-token: write`.
- **The apply job:**
  - declares `environment: dev-infrastructure-apply` and uses `role-to-assume:
    ${{ vars.AWS_ROLE_ARN }}`
  - shares the `terraform-state-dev-platform` concurrency group
  - runs only for commits on `main`
- **Plan binding without publishing the plan.** Artifacts of this public repository are public, so
  a plaintext binary plan must not be uploaded between jobs. The recommended design:
  1. The plan job on `main` publishes only its summary and digests.
  2. After approval, the apply job re-plans the same commit.
  3. It refuses to continue unless its `changes_sha256` equals the approved one.
  4. It then applies its own saved plan file in the same job.

  The alternative is a plan artifact encrypted with a key held only in the two environments. Either
  way, the commit (`github.sha`) must match, and Terraform refuses a saved plan if state changed.
- **Destructive plans.** If the plan contains any delete or replacement, the apply job stops unless
  the run was started with an explicit `allow-destroy` input.
- **New VPCs.** If the plan creates a VPC, CI never applies it; a human runs that apply.
- **Locking.** Per-root concurrency; no automatic `force-unlock`.
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

## Deployment order and status

1. **Done, 14 October 2026:** the `dev-infrastructure-apply` environment protection was
   configured before the foundation apply.
2. **Done, 14 October 2026:** the foundation was applied from a reviewed saved plan, with exactly
   11 resources added (0 changed, 0 destroyed):
   - the boundary policy
   - the apply role and its inline state policy
   - the four apply managed policies
   - the four attachments

   The post-apply plan showed no changes. `AWS_ROLE_ARN` was then set in the environment.
3. The boundary exists, so platform plans can reference it. A platform plan still needs
   `eks.compatibility_verified`, which is a separate owner decision.
4. **Done, 14 October 2026:** `dev-infrastructure` was protected, and its `AWS_ROLE_ARN` and
   `TERRAFORM_CONFIG_JSON` were set.
5. The administrator applies the initial platform deployment from a reviewed saved plan. It
   creates the VPC, so CI cannot (see Cross-project isolation).
6. #11 builds the approval-gated apply; CI then applies later platform changes.
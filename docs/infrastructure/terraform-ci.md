# Terraform CI identities and approval gate

Decision record, 14 October 2026 (issue #8, Option A approved by the owner; independently
reviewed and hardened the same day). Current state, 17 October 2026:
- The foundation IAM is applied, and both GitHub environments and the `main` ruleset are configured.
- The pull-request workflow (#10) planned the live platform with the plan-only role until the
  20 October 2026 teardown, for example
  [run 38896532913](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38896532913)
  for PR #53.
- The approval-gated apply workflow (#11) has applied one reviewed saved plan: a tag-only update
  in [run 38901260888](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38901260888)
  (0 create, 1 update, 0 delete).
- A deliberate failing run (G06.6) was recorded on 20 October 2026: a formatting error on draft
  PR #64 failed the checks job in
  [run 39387242933](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/39387242933),
  and the plan job was skipped ([evidence](../screenshots/cicd/2026-10-20-deliberate-failing-runs.md)).

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
| Apply permissions scoped, boundary mandatory | Applied (foundation, 11 resources); synthetic policy tests, and one CI apply (run 38901260888) |
| Protected `dev-infrastructure-apply` environment | Configured: reviewer Fer-as, `main` only, administrator bypass off, variable `AWS_ROLE_ARN`, secrets `TERRAFORM_CONFIG_JSON` and `PLAN_DECRYPTION_IDENTITY` |
| Protected `dev-infrastructure` environment | Configured: reviewer Fer-as, `refs/pull/*/merge` and `main`, administrator bypass off, variables `AWS_ROLE_ARN` (plan role), `PLAN_ENCRYPTION_RECIPIENT` and `PLAN_REVIEW_RECIPIENT`, secret `TERRAFORM_CONFIG_JSON` |
| `main` protected | Ruleset: pull request required (0 approvals, single maintainer), no force pushes, no deletion, no bypass |
| No AWS credentials for untrusted pull requests | Pull-request workflow (#10): `pull_request` trigger only, plan job skipped for fork heads, `permissions: {}` by default; runs on PRs #52 and #53 |
| Plan output does not leak private values | Pull-request workflow (#10): plan text kept out of logs, values masked, summary shows actions and digests only, no binary plan artifact; runs on PRs #52 and #53 |
| Saved-plan, commit and digest binding | Apply workflow (#11): encrypted saved plan with commit, run, state, lock, version, ciphertext, plaintext and changes digests checked before apply; synthetic tests, and verified in run 38901260888 |
| No unapproved destroy or replacement | Apply workflow (#11): refused unless `allow_destroy` and reviewer approval; VPC creation or replacement always refused. IAM cannot express it, because the apply role must be able to delete platform resources for replacements |
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
   - **No AWS keys.**
   - **Added for #11 on 14 October 2026:**
     - secret `TERRAFORM_CONFIG_JSON`, built from the same source and with the same code as the
       planning secret; SHA-256 recorded privately. Byte-for-byte equality with the planning
       secret is **not yet proven**. The apply job compares the config digests of both jobs and
       fails closed on a mismatch.
     - secret `PLAN_DECRYPTION_IDENTITY`, the CI age identity. It exists only here.
2. **`dev-infrastructure`** (plan; configured 14 October 2026):
   - **Required reviewers:** Fer-as, with Prevent self-review off. Every pull-request plan job
     waits for the owner's approval before it can obtain the plan role. This is a deliberate owner
     choice; the role itself is read-only apart from its lock object.
   - **Allow administrators to bypass:** off.
   - **Deployment branches and tags:** Selected, with two branch rules: `refs/pull/*/merge` and
     `main`. GitHub matches the rules against the run's `GITHUB_REF`, which for `pull_request`
     runs is `refs/pull/<number>/merge`, and `*` does not match `/`. Other branches cannot use
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
   - **Added for #11 on 14 October 2026:**
     - a second branch rule, `main`, so the manual apply workflow's plan job can run; the reviewer
       requirement stays
     - variable `PLAN_ENCRYPTION_RECIPIENT`, the CI age public key
     - variable `PLAN_REVIEW_RECIPIENT`, the owner's age public key, set by the owner
3. **`dev-images`:** `main` only, with `AWS_ROLE_ARN` set to the image role's ARN. Configure it with
   the image workflow.
4. Repository **Actions → General**: keep "Require approval for fork pull requests" enabled.
5. `main`: protected by the repository ruleset described above.

Workflows reference role ARNs only as `${{ vars.AWS_ROLE_ARN }}`, from a job that names its
environment explicitly. They never contain an `arn:aws` literal.

## Approval-gated apply (`.github/workflows/terraform-apply.yml`, issue #11)

Written, independently reviewed and tested with synthetic fixtures. **First real run:**
[run 38901260888](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/38901260888)
on 16–17 October 2026 applied a reviewed tag-only change after both approvals.

The security regression tests are in `scripts/ci/tests/plan-protection.tests.ps1`: 59 checks using throwaway age keys and synthetic plans, with no AWS. The pull-request `checks` job runs them on every relevant change.

**Trigger**
- `workflow_dispatch` only, and both jobs refuse anything but `refs/heads/main`.
- The single boolean input `allow_destroy` defaults to false.
- `permissions: {}` by default.

**`plan` job** (environment `dev-infrastructure`, `contents: read`, `id-token: write`):
1. Before any AWS session, it fails closed unless:
   - both age recipients are configured, valid and different
   - the CI decryption key is **not** visible to this job, for example as a repository-level
     secret
2. Fails unless `eks.compatibility_verified` is true.
3. Assumes the read-only plan role through `vars.AWS_ROLE_ARN` and checks it is the plan role.
4. Runs `init`, then `plan -lock-timeout=5m -out=platform.tfplan`. The plan text is never
   logged.
5. `scripts/ci/protect-terraform-plan.ps1` classifies every planned action:
   - create, update, delete, replace, forget and import are recognised
   - anything unrecognised counts as destructive
6. It then applies the gates:
   - **Never in CI, even with `allow_destroy`:** any creation, replacement, deletion or forget of
     a **VPC** or the **EKS cluster**, and any **import**. These are human-run. In-place updates,
     such as tags, are allowed.
   - **Only with `allow_destroy` (and then approval):** any delete, replace, forget or
     unrecognised action.
7. It encrypts two copies of the **same saved plan file**:
   - **Binary plan:** to the CI recipient.
   - **Readable `terraform show` copy:** to the reviewer recipient. The copy starts with a header
     of the plan's identity: the run and attempt, commit, state key, plan SHA-256, changes SHA-256
     and counts.
8. It publishes the identity as job outputs and as a table in the run summary:
   - commit, run and attempt
   - SHA-256 of `backend.hcl` (state bucket, key, Region and account)
   - SHA-256 of the private configuration
   - lock-file hash and Terraform version
   - plan, ciphertext and changes digests
   - the CI recipient and `allow_destroy`
9. Uploads the two ciphertexts as one-day artifacts. Plaintext never leaves the runner.

**`apply` job** (environment `dev-infrastructure-apply`; runs only if there are changes):
1. **The approval pause happens here.** GitHub issues the apply role and the
   `PLAN_DECRYPTION_IDENTITY` secret only after the required reviewer approves.
2. Assumes the apply role and checks it is the apply role.
3. Initialises the backend and downloads the plan artifact by its exact name. `download-artifact`
   fails on a digest mismatch.
4. `scripts/ci/unprotect-terraform-plan.ps1` refuses unless all of these match the plan job's
   outputs:
   - commit, both `GITHUB_SHA` and `HEAD`
   - workflow run and attempt
   - state key and backend digest
   - configuration digest
   - lock-file hash and Terraform version
   - ciphertext digest
   - the recipient derived from the identity
5. It decrypts, passing the identity to age on **standard input**: it is never an argument or a
   file. age authenticates the ciphertext.
6. It refuses unless the plaintext SHA-256 and changes digest match and the gates still pass. A
   plan failing any check is deleted.
7. `terraform apply approved.tfplan` applies that file; **nothing is re-planned**. Terraform refuses
   a saved plan whose state changed after planning ("Saved plan is stale"). Only the "Apply
   complete!" line is logged.

**Both jobs**
- Share the `terraform-state-dev-platform` concurrency group with pull-request plans, with
  `cancel-in-progress` off.
- Use a 5-minute lock timeout and never `force-unlock`.
- Have timeouts and failure summaries.
- Always delete plans, decrypted files, configuration and `backend.hcl`.

**Rejection, timeouts and staleness**
- **Rejected approval:** the apply job never starts, so no credentials or key are issued. The
  encrypted artifacts expire after one day.
- **Late approval:**
  - after one day, the artifact download fails
  - after any state change, Terraform rejects the stale plan
  - both fail closed; start a new run
- **Pending timeout:** GitHub allows a deployment to wait up to 30 days. Reject runs you will not
  approve. A waiting apply may also hold the concurrency group and delay pull-request plans.

**Why the applied plan is the reviewed plan**
- The review copy and the binary plan are encrypted from the same file in the same step.
- The review copy's header carries that file's `plan_sha256`, and the run summary shows the same
  value.
- The apply job may only execute a file with that `plan_sha256`, reached through a ciphertext with
  the pinned digest.
- That file must decrypt with the identity only the approved environment holds.
- Its commit, run, backend, configuration, lock file and version must all match.
- Job outputs travel inside the run, not through the public artifact.
- Anyone holding the public CI key can encrypt a different plan, but it cannot match both pinned
  digests.

**Encryption and keys (age v1.3.2, X25519)**
- The pinned release tarballs were verified on 14 October 2026 with `sigsum-verify` v0.13.1:
  - against age's two published Sigsum keys and the `sigsum-generic-2025-1` policy
  - with a negative control that was rejected

  The checksums are:
  - Linux, used by CI: `cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10`
  - Windows, for the reviewer: `f48d8f8f9ebe903ab5027ed067652f2cc1db94bc206976430133b905dcd8e8c7`
- CI checks the Linux SHA-256 before installing, and installs only `age` and `age-keygen`, without
  plugins.

| Key | Where | Purpose |
|---|---|---|
| CI recipient (public) | `dev-infrastructure` variable `PLAN_ENCRYPTION_RECIPIENT` | Plan job encrypts the binary plan |
| CI identity (private) | `dev-infrastructure-apply` secret `PLAN_DECRYPTION_IDENTITY` | Apply job decrypts, only after approval |
| Reviewer recipient (public) | `dev-infrastructure` variable `PLAN_REVIEW_RECIPIENT` | Plan job encrypts the readable copy |
| Reviewer identity (private) | The owner's computer only, never in GitHub | Owner decrypts the review copy |

The CI key cannot read the review copy, and the reviewer key cannot read the binary plan. Missing,
malformed, wrong or misplaced keys all fail closed.

**Other deliberate refusals.** The recorded G06.6 failing run is the formatting error above. These
refusals would also be deliberate, and cost nothing:
- a run while `eks.compatibility_verified` is false
- a run before the keys exist
- a plan with deletions but without `allow_destroy`

### Reviewing a plan before approving (Windows PowerShell)

**One-time setup.** Install [age](https://github.com/FiloSottile/age) so that `age` and
`age-keygen` are on your `PATH`, for example with `winget install FiloSottile.age`. If you use the
v1.3.2 Windows release zip instead, check that its SHA-256 is
`f48d8f8f9ebe903ab5027ed067652f2cc1db94bc206976430133b905dcd8e8c7` before extracting it. Then
create the reviewer identity in a private folder of your choice, never inside the repository:

```powershell
$identity = "<private folder>\finsight-review.key"
age-keygen -o $identity   # prints your public key (age1...)
icacls $identity /inheritance:r /grant:r "${env:USERNAME}:R" | Out-Null
```

`age-keygen` prints "Public key: age1..." and a "world-readable" warning; the warning is expected,
and the `icacls` line then makes the file readable by you only. To replace the key later, first
run `icacls <file> /grant:r "${env:USERNAME}:F"`. Keep the identity file only on your own
computer, and back it up offline. Give only the `age1...` public key for `PLAN_REVIEW_RECIPIENT`.
To check which public key a file holds, run `age-keygen -y <file>`; it prints only the public key.

**For each run waiting for approval:**
1. Open the run. Note the run ID (in the URL) and the attempt, then read the summary table
   "Before approving the apply job".
2. Download and check the encrypted review copy, replacing the two values:

   ```powershell
   $run = "<run id>"; $attempt = "<attempt>"; $dir = "$env:TEMP\finsight-review-$run"
   gh run download $run --repo Fer-as/finsight-eks-data-platform --name "terraform-plan-review-$run-$attempt" --dir $dir
   (Get-FileHash "$dir\platform-plan-review.txt.age" -Algorithm SHA256).Hash.ToLower()   # must equal "Encrypted review copy SHA-256"
   ```
3. Decrypt to the screen only. Nothing in plaintext is written to disk. Set `$identity` to the
   path of your reviewer identity file first:

   ```powershell
   $identity = "<path to your reviewer identity file>"
   age --decrypt --identity $identity "$dir\platform-plan-review.txt.age" | Out-Host -Paging
   ```
4. Check that the header's run, attempt, commit, state key, **plan SHA-256** and changes SHA-256
   equal the summary table. Then review every change.
5. **Approve:** on the run page, choose Review deployments, then `dev-infrastructure-apply`, then
   Approve. **Reject** if anything differs or is unexpected.
6. Delete the download: `Remove-Item -Recurse -Force $dir`.
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
6. #11: the approval-gated apply workflow is written. It needs the age keys, the `main` rule on `dev-infrastructure`, and `TERRAFORM_CONFIG_JSON` in `dev-infrastructure-apply`. It can then apply non-VPC changes after the human-run initial deployment.
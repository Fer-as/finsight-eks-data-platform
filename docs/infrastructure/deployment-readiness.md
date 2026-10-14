# Deployment readiness record

Review date: 13 October 2026, updated 14 October 2026. This record covers the read-only AWS
preflight, a review of the three Terraform roots and the ordered plan procedure. Account IDs,
ARNs, zone and principal names are deliberately omitted from this tracked file.

## Deployment status (14 October 2026)

| Step | Status |
|---|---|
| EKS administrator IAM role | Created and assumed with MFA (owner-approved) |
| Bootstrap root | **Applied**: 15 resources (state bucket and access-log bucket); verified read-only |
| Bootstrap state | **Migrated** from local state to the S3 backend; post-migration plan: no changes |
| Foundation root | **Applied**: 18 resources (data bucket, three ECR repositories, two GitHub OIDC roles); post-apply plan: no changes |
| Platform root (VPC, EKS, nodes) | **Not deployed.** Plan not yet run; needs the open Terraform design items and owner approvals |

Evidence: [bootstrap and foundation record](../evidence/day2-aws-bootstrap-foundation.md).
Nothing billable by the hour is running. This is a short-lived assessment environment;
nothing here claims production readiness.

## Blockers and decisions before any plan

| # | Item | Why it blocks | Resolution |
|---|---|---|---|
| 1 | No EKS administrator IAM role exists | `eks.admin_role_arns` requires at least one existing IAM **role**. The account has only an IAM user for humans and unrelated workload roles. Cluster-creator admin is disabled, so without a role nobody can reach the Kubernetes API. | **Resolved 14 October 2026:** `finsight-dev-eks-admin` created with the MFA-conditioned trust below; assumption with MFA succeeded. |
| 2 | `config/local.json` does not exist | Account ID, three bucket names, API CIDR, admin role, zone and OIDC values have no usable defaults by design. | **Resolved 14 October 2026:** created locally and git-ignored; all values pass the module validation rules. `compatibility_verified` remains `false`. |
| 3 | Monthly spend already near the alert | Unrelated existing workloads had spent about $35 of the month by this date, and the $50 alert is account-wide. | Decide the deployment window with [costs.md](costs.md) in hand. Not a technical blocker. |

Not blockers: the missing EKS, node group and Auto Scaling service-linked roles (AWS creates
them on first use and the deploying identity may create service-linked roles), and the F5
NGINX decision (nothing in these three roots depends on it).

## Read-only AWS preflight results

Run on 13 October 2026 against `eu-west-2` with read-only calls only.

| Check | Result |
|---|---|
| Deploying identity | IAM user with `AdministratorAccess` through a group, MFA device registered, no permissions boundary. Policy simulation allowed every create action sampled across S3, ECR, IAM, EKS, EC2, CloudWatch Logs and Route 53. |
| Availability Zones | `eu-west-2a` and `eu-west-2b` are `available`, standard zones, no opt-in. They match `network.availability_zones`. |
| Elastic IPs | 3 of 5 in use by an unrelated workload. FinSight needs 1, leaving 1 spare. |
| NAT gateways | Quota 5 per AZ; 1 exists in an unrelated VPC. FinSight adds 1. |
| VPCs / internet gateways | 2 of 5 each. FinSight adds 1 of each. Existing CIDRs do not overlap `10.42.0.0/16`. |
| EKS clusters | 0 of 100. |
| m7i.large | x86_64, Nitro, 2 vCPU, 8 GiB, 3 ENIs with 10 IPv4 each (29 pods per node without prefix delegation). |
| AL2023 node AMI | Recommended release for 1.36 is `1.36.4-20261003`: x86_64, available, root device `/dev/xvda`, which matches the launch template. |
| EBS encryption | Account default encryption is off and the default key is the AWS-managed `aws/ebs` key. Node root volumes are encrypted explicitly by the launch template; no customer-managed key is involved. |
| AWS-managed policies | All five referenced policies exist, including `AmazonEBSCSIDriverPolicyV2` (v1). |
| GitHub OIDC provider | One already exists for `token.actions.githubusercontent.com`. Use `create_provider=false` with its ARN; creating a second would fail. |
| OIDC subject format | This repository's GitHub OIDC settings use the immutable subject, so `subject_prefix` is `repo:OWNER@OWNER_ID/REPO@REPO_ID`, read from the repository's OIDC customisation endpoint. Another repository's role in the account uses the classic form, which does not apply here. |
| Route 53 | One public hosted zone; its name servers match public DNS delegation. No `eks.` or `eks.labs.` record exists yet. |
| S3 bucket names | `finsight-dev-tfstate-<ACCOUNT_ID>`, `finsight-dev-data-<ACCOUNT_ID>` and `finsight-dev-access-logs-<ACCOUNT_ID>` all returned 404 (unclaimed). These follow the account's existing naming habit and are a suggestion only. |
| Name collisions | No `finsight` ECR repositories, log groups or IAM roles exist. |
| Budget | A $50 monthly account-wide cost budget exists with one alert at $50 actual spend. |

Pending, cannot be settled read-only: actual instance capacity at launch time, and the
operator's current public IPv4 address for the API allow-list (checked at configuration time).

## Terraform review

**Configuration.** `defaults.json` cannot provision on its own: the config module rejects the
placeholder account ID, and the EKS and GitHub modules reject empty API CIDRs, admin roles,
zone ID and subject prefix. Sections merge one level deep, so `eks.addon_versions` in
`local.json` must keep all five keys.

**Backend order.** Bootstrap starts on local state and creates the state and access-log
buckets; only then can its state migrate to S3. Foundation and platform declare an S3 backend,
so neither can be initialised or planned until bootstrap has been applied. Foundation also
needs the access-log bucket for data-bucket logging. The order bootstrap, foundation, platform
is therefore fixed.

**IAM and GitHub OIDC.** Foundation creates two GitHub roles: plan-only (reads platform state
and describes resources) and image publisher (the three ECR repositories). Neither can apply.
Trust is pinned to the exact repository subject and the `dev-infrastructure` and `dev-images`
environments, which must exist in the GitHub repository before any workflow uses them.
Applies are run by a human. The current deploying identity is a long-lived administrator
user rather than a scoped deployment role; acceptable for a short assessment, but it is the
largest standing privilege in this design.

**Nodes and add-ons.** Two to three `m7i.large` on-demand AL2023 x86_64 nodes in the two
private subnets, IMDSv2 required with hop limit 1, encrypted 30 GB gp3 roots. Create order is
Pod Identity Agent, then VPC CNI and kube-proxy, then nodes, then CoreDNS and EBS CSI. All
five pins are verified for 1.36, `amd64`, EC2 and platform `eks.14`.

**API access.** Private endpoint plus a public endpoint restricted to explicit CIDRs of /24
or narrower; an empty list is rejected. A home or mobile address can change, which would lock
the operator out until the CIDR is updated by another apply.

**DNS.** The platform root only reads the hosted zone and checks it is public, matches
`dns.zone_name`, and that the hostname is `eks.<zone>` or `eks.labs.<zone>`. It creates no
records.

**Retention.** State, data and access-log buckets and the ECR repositories have
`prevent_destroy`, no `force_destroy`/`force_delete`, and versioning on the buckets. Platform
teardown leaves them in place by design; they keep a small storage cost.

**NGINX controller.** Still planned only, pending the assessor's acceptance of F5 NGINX. It
is a later Helm install and does not affect these plans. Recheck the support matrix for 1.36
when it is pinned.

**Deployment-time risks.** Pod Identity credential delivery, AL2023 bootstrap, add-on health
and instance capacity are proven only by deploying. A failed apply can leave billable partial
resources. Later StorageClasses must set `encrypted: "true"` because account default EBS
encryption is off.

## Administrator role

Procedure finalised on 14 October 2026. **Prepared only; nothing below has been executed.**
Explicit approval is required for creating this role, attaching its inline policy and testing
assumption. That approval does not authorise Terraform apply, backend migration or EKS
deployment. No further MFA-device inventory is required.

The existing browser-based `aws login` profile remains the source identity. Trust allows only
that exact IAM user (including its path), with `sts:AssumeRole` and the positive condition
`Bool: aws:MultiFactorAuthPresent = true`. Missing or false MFA context cannot pass this
Allow. No long-lived keys, `mfa_serial`, alternate principals or MFA bypass are introduced.
The role has a one-hour maximum session and one inline permission: `eks:DescribeCluster`
on `finsight-dev` in London. Terraform later grants full Kubernetes administration through
its EKS access entry; the role is not an AWS deployment role.

Run the blocks sequentially from the repository root **only after approval**. The sole source
profile is the currently selected `AWS_PROFILE`, or `default` when none is selected; use the
existing named login profile instead if that is how the operator normally invokes the CLI.
Identity verification here is necessary to bind the new trust correctly, not a repeat of
the completed regional preflight. Never publish raw account-specific output.

### A. Prepare the exact trust and permission documents

```powershell
$ErrorActionPreference = 'Stop'
$sourceProfile = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { 'default' }
$roleName = 'finsight-dev-eks-admin'
$clusterName = 'finsight-dev' # Must match the approved project/environment configuration.
$repoRoot = (Get-Location).Path
if ((Split-Path $repoRoot -Leaf) -ne 'finsight-eks-data-platform') {
    throw 'Run from the FinSight repository root.'
}
$reviewDir = Join-Path $repoRoot '.cache/eks-admin-role'
git check-ignore -q -- .cache/eks-admin-role/trust.json
if ($LASTEXITCODE -ne 0) { throw 'Private review directory must be Git-ignored.' }
$null = New-Item -ItemType Directory -Force -Path $reviewDir
$errorFile = Join-Path $reviewDir 'last-aws-error.txt'

# Capture errors privately and stop on every failed native command, including on PowerShell 5.1.
function Invoke-FinSightAws {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $raw = & aws @Arguments --profile $sourceProfile --region eu-west-2 `
        --output json --no-cli-pager --no-cli-auto-prompt 2> $errorFile
    $awsExitCode = $LASTEXITCODE
    if ($awsExitCode -ne 0) {
        $detail = Get-Content -LiteralPath $errorFile -Raw
        $safeDetail = $detail -replace 'arn:aws:[^\s,]+', '<ARN>' -replace '\b\d{12}\b', '<ACCOUNT_ID>'
        throw "AWS $($Arguments[0]) $($Arguments[1]) failed (exit $awsExitCode): $safeDetail"
    }
    if ($raw) { ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop }
}

# READ: identify the existing browser-login principal, without printing its identifiers.
$identity = Invoke-FinSightAws -Arguments @('sts', 'get-caller-identity')
if ($identity.Account -notmatch '^\d{12}$' -or
    $identity.Arn -notmatch "^arn:aws:iam::$($identity.Account):user/.+$") {
    throw 'Expected the reviewed IAM user; stop rather than trusting a root or role session.'
}
# LOCAL: this reads only the non-secret login_session configuration field.
$loginIdentity = & aws configure get login_session --profile $sourceProfile 2> $errorFile
if ($LASTEXITCODE -ne 0 -or $loginIdentity -ne $identity.Arn) {
    throw 'Selected profile is not the expected IAM-user browser-login profile. Stop for review.'
}
$account = $identity.Account
$roleArn = "arn:aws:iam::${account}:role/$roleName"
$clusterArn = "arn:aws:eks:eu-west-2:${account}:cluster/$clusterName"
$trust = @{
    Version = '2012-10-17'
    Statement = @(@{
        Effect = 'Allow'; Principal = @{ AWS = $identity.Arn }; Action = 'sts:AssumeRole'
        Condition = @{ Bool = @{ 'aws:MultiFactorAuthPresent' = 'true' } }
    })
}
$policy = @{
    Version = '2012-10-17'
    Statement = @(@{ Effect = 'Allow'; Action = 'eks:DescribeCluster'; Resource = $clusterArn })
}
$trustPath = Join-Path $reviewDir 'trust.json'
$policyPath = Join-Path $reviewDir 'describe-cluster.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($trustPath, ($trust | ConvertTo-Json -Depth 8), $utf8)
[System.IO.File]::WriteAllText($policyPath, ($policy | ConvertTo-Json -Depth 8), $utf8)
```

Privately confirm the resolved user/account matches the already reviewed deploying identity.
The login_session field confirms the intended profile configuration; it does not prove MFA
context or rule out all credential-precedence problems. The strict assumption test is required.

### B. Create only the FinSight administrator role

```powershell
# WRITES: only the approved role and its one inline policy.
$createdRole = Invoke-FinSightAws -Arguments @(
    'iam', 'create-role', '--role-name', $roleName,
    '--assume-role-policy-document', "file://$trustPath",
    '--max-session-duration', '3600',
    '--description', 'FinSight human EKS administrator; browser login with MFA required'
)
if ($createdRole.Role.Arn -ne $roleArn) { throw 'Unexpected created role; stop for review.' }
Invoke-FinSightAws -Arguments @(
    'iam', 'put-role-policy', '--role-name', $roleName,
    '--policy-name', 'describe-cluster', '--policy-document', "file://$policyPath"
)
```

If creation returns `EntityAlreadyExists` or any other error, **stop**; never proceed to
put-role-policy against a pre-existing role. If a later step fails, retain the partial result
and report it. Do not delete, replace or update trust automatically. No retry of the write
blocks is authorised merely because a verification step fails.

### C. Read back and test assumption through the existing login profile

```powershell
# READ: capture for private comparison with the exact documents from section A.
$actualRole = Invoke-FinSightAws -Arguments @('iam', 'get-role', '--role-name', $roleName)
$actualPolicy = Invoke-FinSightAws -Arguments @(
    'iam', 'get-role-policy', '--role-name', $roleName, '--policy-name', 'describe-cluster'
)
$attached = Invoke-FinSightAws -Arguments @('iam', 'list-attached-role-policies', '--role-name', $roleName)
$inline = Invoke-FinSightAws -Arguments @('iam', 'list-role-policies', '--role-name', $roleName)
if (@($attached.AttachedPolicies).Count -ne 0 -or
    @($inline.PolicyNames).Count -ne 1 -or $inline.PolicyNames[0] -ne 'describe-cluster') {
    throw 'Unexpected policies attached to the role; stop for review.'
}
```

Before testing, compare `actualRole.Role.AssumeRolePolicyDocument` with the exact user,
single Allow, `sts:AssumeRole` and strict MFA condition above; require MaxSessionDuration
3600. Compare `actualPolicy.PolicyDocument` with the single cluster-specific DescribeCluster
statement. Stop if either differs. Do not print these private objects into shared logs.

```powershell
# AUTHENTICATION TEST: issues a temporary session, but does not change AWS resources.
# Query only the assumed-role ARN; never emit or persist the returned Credentials object.
$assumedArn = Invoke-FinSightAws -Arguments @(
    'sts', 'assume-role', '--role-arn', $roleArn,
    '--role-session-name', 'finsight-readiness', '--duration-seconds', '3600',
    '--query', 'AssumedRoleUser.Arn'
)
if ($assumedArn -ne "arn:aws:sts::${account}:assumed-role/$roleName/finsight-readiness") {
    throw 'Unexpected assumed identity; stop for review.'
}
# Save only the persistent role ARN for the later ignored Terraform override.
[System.IO.File]::WriteAllText((Join-Path $reviewDir 'role-arn.txt'), $roleArn, $utf8)
Write-Output 'FinSight administrator-role assumption succeeded; no EKS resources deployed.'
```

Success proves assumption with this browser-login session against the reviewed MFA trust;
it does not prove Kubernetes access before the cluster/access entry exists. No permanent
CLI profile edits or long-lived access keys are needed for this test.

**Failure handling:** stop and retain the original AWS error privately; report its exact
error code/message with identifiers redacted. A generic `AccessDenied` alone does not prove
MFA was the cause. Distinguish expired login, wrong principal/profile, IAM propagation,
explicit denies, MFA context and any specifically reported source-identity permission issue.
If the cause is ambiguous, say so and propose only the narrow diagnostic needed. A short
retry of reads/assumption may resolve propagation; never retry creation. Any correction to
trust or permissions requires a new reviewed proposal and approval. Never substitute
`BoolIfExists`, remove MFA, add wildcard trust or grant broader access silently.

After success, use the persistent ARN from `.cache/eks-admin-role/role-arn.txt` as an element
of `eks.admin_role_arns` in ignored `infra/terraform/config/local.json`. Do not use an STS
session ARN. Keep `eks.compatibility_verified=false` until readiness is explicitly approved.
Role approval does not approve EKS deployment or its cost window. The next milestone is local
configuration and the bootstrap **plan**, followed by plan review; no apply or migration.
The administrator role is an external prerequisite and has no hourly infrastructure charge.

References: [CreateRole](https://docs.aws.amazon.com/cli/latest/reference/iam/create-role.html),
[AssumeRole](https://docs.aws.amazon.com/cli/latest/reference/sts/assume-role.html),
[MFA condition semantics](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-multifactorauthpresent),
[browser login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html).

## Plan procedure

Run from the repository root in PowerShell. Each step is marked **LOCAL** (files on this
machine only), **READ** (reads AWS, creates nothing) or **WRITE** (creates or changes AWS
resources or remote state). Stop at every WRITE step for approval. Check `$LASTEXITCODE`
after each Terraform command and stop on failure.

Quote every `-flag=value` argument, as below. Windows PowerShell 5.1 splits an unquoted
`-out=bootstrap.tfplan` at the dot, and Terraform then fails with "Too many command line
arguments". Run `init -migrate-state` in an interactive terminal and answer its prompt
yourself; piping `yes` into it failed on Windows with `Error asking for confirmation: EOF`.

```powershell
$tf = (Resolve-Path .\.cache\terraform\terraform.exe).Path
$bootstrap = "infra/terraform/bootstrap"
$foundation = "infra/terraform/environments/dev/foundation"
$platform = "infra/terraform/environments/dev/platform"
```

### 1. Local account-specific configuration

```powershell
# READ: collect the values
aws sts get-caller-identity --query Account --output text
aws route53 list-hosted-zones --query "HostedZones[].[Id,Name]" --output text
aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[].Arn" --output text
(Invoke-RestMethod https://checkip.amazonaws.com).Trim()

# LOCAL: create and edit the ignored override file
Copy-Item infra/terraform/config/local.json.example infra/terraform/config/local.json
notepad infra/terraform/config/local.json
```

Set in `local.json`:

| Key | Value |
|---|---|
| `account_id` | The 12-digit account ID |
| `state_bucket`, `data_bucket`, `access_log_bucket` | Three distinct unclaimed names |
| `eks.public_access_cidrs` | The address printed above, as `x.x.x.x/32` |
| `eks.admin_role_arns` | The administrator role ARN |
| `eks.ami_release_version` | Optional: `1.36.4-20261003` for a repeatable node image |
| `eks.addon_versions` | Leave the five pins from the example unchanged |
| `eks.compatibility_verified` | Keep `false` until readiness is explicitly approved; reviewing the compatibility record alone is not approval. It always stays `false` in tracked files. |
| `dns.zone_id` | The zone ID without the `/hostedzone/` prefix |
| `dns.zone_name`, `dns.application_hostname` | The zone name, and `eks.<zone>` or `eks.labs.<zone>` |
| `github.create_provider` | `false` |
| `github.existing_provider_arn` | The existing provider ARN |
| `github.subject_prefix` | The exact `sub_claim_prefix` from `GET /repos/OWNER/REPO/actions/oidc/customization/sub`: `repo:OWNER@OWNER_ID/REPO@REPO_ID` when immutable subjects are on, `repo:OWNER/REPO` only when they are off. Never a wildcard. |

```powershell
# LOCAL: generate the three ignored backend.hcl files, then validate offline
powershell -NoProfile -File .\scripts\new-terraform-backend-config.ps1
powershell -NoProfile -File .\scripts\validate-terraform.ps1 -TerraformPath $tf
git status --short   # local.json and backend.hcl must not appear
```

### 2. Bootstrap state resources

`bootstrap/backend.tf` must not exist yet, so this root uses local state.

```powershell
& $tf "-chdir=$bootstrap" init "-input=false"                      # LOCAL
& $tf "-chdir=$bootstrap" plan "-input=false" "-out=bootstrap.tfplan" # READ; writes a local plan file
& $tf "-chdir=$bootstrap" show bootstrap.tfplan                   # LOCAL
```

Expected: 15 to add, 0 to change, 0 to destroy (state bucket and access-log bucket with their
settings). **Stop for approval.**

```powershell
# WRITE: creates the two S3 buckets
& $tf "-chdir=$bootstrap" apply bootstrap.tfplan
# LOCAL: back up the local state outside the repository before migrating
Copy-Item "$bootstrap/terraform.tfstate" "$env:USERPROFILE\finsight-bootstrap-state-backup.tfstate"
# WRITE: moves bootstrap state into the new bucket
Copy-Item "$bootstrap/backend.tf.example" "$bootstrap/backend.tf"
& $tf "-chdir=$bootstrap" init -migrate-state "-backend-config=backend.hcl"
& $tf "-chdir=$bootstrap" plan "-input=false"                       # READ; expect no changes
```

### 3. Foundation initialisation and plan

Possible only after step 2, because the backend bucket must exist.

```powershell
& $tf "-chdir=$foundation" init "-backend-config=backend.hcl" "-input=false" # READ of the state bucket
& $tf "-chdir=$foundation" plan "-input=false" "-out=foundation.tfplan"      # READ; takes and releases an S3 lock object
& $tf "-chdir=$foundation" show foundation.tfplan                        # LOCAL
```

Expected: 18 to add (data bucket, three ECR repositories with lifecycle policies, two GitHub
roles with policies), 0 to change, 0 to destroy. **Stop for approval.**

```powershell
# WRITE: creates the retained data bucket, ECR repositories and GitHub roles
& $tf "-chdir=$foundation" apply foundation.tfplan
```

### 4. Platform initialisation and plan

```powershell
& $tf "-chdir=$platform" init "-backend-config=backend.hcl" "-input=false" # READ of the state bucket
& $tf "-chdir=$platform" plan "-input=false" "-out=platform.tfplan"        # READ; takes and releases an S3 lock object
& $tf "-chdir=$platform" show platform.tfplan                          # LOCAL
```

Expected with one administrator role: 47 to add (24 network, 20 EKS, 3 ETL identity),
0 to change, 0 to destroy. **Stop for approval of the plan and the running-cost window.**
The platform apply is the step that starts hourly charges; it is in the [runbook](runbook.md).

The expected counts were derived by reading the modules, not from a real plan. Treat any
difference as something to explain before approving.

### 5. Review counts, IAM changes and cost

Saved plan files can contain sensitive values. They are git-ignored; do not export them to
other files. Repeat for each root by changing the path and plan file.

```powershell
$plan = & $tf "-chdir=$platform" show -json platform.tfplan | ConvertFrom-Json
$changes = $plan.resource_changes | Where-Object { $_.mode -eq "managed" -and $_.change.actions -notcontains "no-op" }

# Counts by action and by resource type
$changes | Group-Object { $_.change.actions -join "," } | Format-Table Count, Name
$changes | Group-Object type | Sort-Object Count -Descending | Format-Table Count, Name

# Anything replaced or destroyed: expect none
$changes | Where-Object { $_.change.actions -contains "delete" } | ForEach-Object address

# IAM and access changes
$changes | Where-Object { $_.type -like "aws_iam_*" -or $_.type -like "aws_eks_access_*" -or $_.type -eq "aws_eks_pod_identity_association" } |
    ForEach-Object { "{0}  {1}" -f ($_.change.actions -join ","), $_.address }

# Billable resources to check against costs.md
$changes | Where-Object { $_.type -in "aws_eks_cluster", "aws_eks_node_group", "aws_nat_gateway", "aws_eip", "aws_launch_template", "aws_cloudwatch_log_group", "aws_flow_log" } |
    ForEach-Object address
```

Confirm in the platform plan: one cluster on 1.36, one node group of `m7i.large` with desired
size 2, exactly one NAT gateway and one Elastic IP, the public access CIDR list equal to the
intended /32, the administrator role in the access entry, and the five add-on versions equal
to the pins. Terraform does not price a plan; multiply the hours you approve by the rates in
[costs.md](costs.md).

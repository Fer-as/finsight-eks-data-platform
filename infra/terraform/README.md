# FinSight infrastructure (Day 2)

Local implementation only. No AWS resources have been provisioned. The working Day 1
application is unchanged. See [validation evidence](../../docs/evidence/day2-terraform-validation.md).

## Structure and ownership

| Root | Owns | Lifecycle |
|---|---|---|
| `bootstrap/` | Encrypted, versioned, private state bucket and separate S3 access-log destination | Retain; initially local state, then migrate |
| `environments/dev/foundation/` | Data bucket, ECR repositories, GitHub OIDC roles/provider if explicitly requested | Retain across EKS rebuilds |
| `environments/dev/platform/` | VPC, NAT, endpoint, flow logs, EKS, nodes, add-ons, workload identities | Disposable after approved teardown |
| `modules/` | Eight reusable, repository-owned modules | Versioned with the Git commit |

No Kubernetes/Helm providers, application manifests, GitOps configuration, DNS records,
hosted zone creation or CI workflows are included. Separate roots do not read each other's
state. Shared names come from one configuration; deploy them in the documented order.

## Configure safely

`config/defaults.json` centralises project, environment, Region, tags, CIDRs/AZs, node sizing,
domain, zone and repository names. Copy `config/local.json.example` to ignored
`config/local.json` and supply actual values only when preparing an approved deployment.
No secrets belong in either file. Account identifiers and admin role ARNs are local overrides.
Supply three distinct globally unique names: state_bucket, data_bucket and access_log_bucket.
The access-log destination is created in bootstrap before source logging is enabled.

Top-level values replace defaults. Within `network`, `eks`, `dns`, `github`, `storage`
and `tags`, individual fields override defaults. Arrays and deeper objects, including the
entire `eks.addon_versions` map, replace as a unit. Preserve all five add-on keys.
The reserved Project/Environment/ManagedBy tags cannot be overridden.

Defaults deliberately cannot provision: account, names, API CIDRs, administrator roles,
OIDC subject/provider and hosted zone need explicit configuration. All five add-on pins
default to the London 1.36 defaults recorded in the compatibility record.
`compatibility_verified=false` blocks platform planning until the approved regional checks
are recorded. It is an operator attestation, not an AWS verification performed by Terraform.
Do not set it merely to bypass a validation error.

Backend HCL cannot reference Terraform variables. The offline
`scripts/new-terraform-backend-config.ps1` generates the three ignored backend files from
the central configuration and refuses to overwrite existing files. Tracked examples show
the exact state keys, encryption, account restriction and native S3 locking.

## Local review

Requires Terraform **1.16.2**. The reviewed AWS provider is **6.59.0**, pinned exactly in all
three roots with checksum lock files. Module dependency ranges accept this version; local
modules have no mutable external source. Upgrade pins and locks together in a reviewed change.

From the repository root in PowerShell:

```powershell
git status --short --branch
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-terraform.ps1
git diff --check
git diff --stat
git ls-files --others --exclude-standard
```

The validation script checks formatting, initializes each root with `-backend=false` and
`-lockfile=readonly`, validates, runs the nine provider-free/mocked tests, and runs the pinned
Checkov Docker scanner. Docker Desktop and the cached image from `infra/checkov-image.txt`
are required; a missing scanner now fails validation instead of silently skipping security.
Pass `-Format` to apply formatting. It uses Terraform on PATH or the
repo-local `.cache/terraform/terraform.exe`. Public registry access can be required even
with a populated cache. Do not run a real `plan` during this local-only review: it can
read AWS and state. [Evidence](../../docs/evidence/day2-terraform-validation.md) distinguishes
static validation from deployed verification.

Run the scanner alone with `powershell -NoProfile -ExecutionPolicy Bypass -File
.\scripts\scan-terraform.ps1`. It uses a read-only Terraform mount, no container network,
no credentials and no automatic image pull. It saves JSON to ignored `.cache/checkov/latest.json`.
The first public image download, if needed, can be performed separately:

```powershell
New-Item -ItemType Directory -Force .cache/checkov/docker-config | Out-Null
'{}' | Set-Content .cache/checkov/docker-config/config.json -Encoding ascii
$image = (Get-Content infra/checkov-image.txt -Raw).Trim()
docker --config .cache/checkov/docker-config pull $image
```

Current result: 130 passed, 0 failed, **15 resource-scoped exceptions**, not 15 remediated
controls. Review the [finding dispositions](../../docs/evidence/day2-terraform-validation.md)
before provisioning, extending the assessment or changing data classification. No global
check exclusions or soft-fail options are configured.

## Security and deliberate tradeoffs

- S3: bucket-owner-enforced ownership, public-access blocking, versioning, SSE-S3, TLS-only
  policy, no automatic object/version expiry. Incomplete multipart uploads expire after
  seven days. Raw and curated are object prefixes, not fake folder-marker resources.
  Both buckets deliver best-effort access logs to the private bootstrap-owned log bucket
  under separate state/ and data/ prefixes. Current/noncurrent logs each expire after
  90 days by default (up to approximately 180 days plus processing delay).
- State is sensitive. Do not commit state, saved plans, backend files, local config or raw
  plan JSON. Native lock objects need Get/Put/Delete; state writers need Get/Put but no
  Delete. No DynamoDB locking table is needed.
- Data/state/log buckets and ECR repositories have `prevent_destroy`; force deletion is off.
  Tagged images persist; only untagged images expire. Removing resource configuration can
  remove Terraform lifecycle protection: it is not a substitute for IAM controls/backups.
- Workers use private subnets, encrypted gp3 roots and IMDSv2 with hop limit 1; no SSH key or
  public worker address. API access is private plus explicit public IPv4 /24-or-narrower
  ranges (/32 preferred). EKS API access entries grant only explicitly supplied admin roles.
- All five control-plane log types and VPC flow logs are enabled with seven-day retention.
  CloudWatch service encryption and EKS default AWS-owned-key encryption are used; no extra
  customer-managed KMS key/cost is introduced.
- The EKS-managed cluster security group carries control-plane, node and pod traffic; the only
  outside access is the public NLB's Terraform-owned group reaching the ingress pod ports. See
  [network-security.md](../../docs/infrastructure/network-security.md).
  NAT permits outbound AWS/HTTPS access, including EKS Auth for Pod Identity. Workload
  NetworkPolicies and ingress-specific hardening belong to the later Kubernetes phase.
- Pod Identity binds CNI, EBS CSI, the future ETL, ExternalDNS and cert-manager to specific
  service accounts/cluster. The two DNS roles can change only named records in the one hosted
  zone and never each other's; see [dns-and-certificates.md](../../docs/infrastructure/dns-and-certificates.md).
  The node role has worker and ECR-pull policies, not S3 or CNI permissions. AWS-managed
  CNI/CSI policies have necessary broader EC2 rights and can evolve independently of provider pins.
- GitHub trust uses exact audience and repository/environment subjects, never wildcard
  repository trust. Configure protected GitHub environments and branch restrictions later.
  Verify the actual OIDC subject format, including immutable IDs where applicable.
- The infrastructure CI role can **plan only**, with narrowly scoped state/lock access and
  read-only discovery. EC2 Describe and some catalog/log listing actions require resource
  `*`. The image role writes only the configured repositories. Neither can apply Terraform,
  modify IAM, change DNS, or delete state. A future automated apply role requires a separate
  reviewed permissions design; it is not silently granted AdministratorAccess.
- One NAT gateway is a cost-conscious **non-HA** compromise and may incur cross-AZ traffic.
  Two workers in a multi-AZ node group are **not guaranteed one per AZ**.
  Future single-replica PostgreSQL on zonal EBS is also **not HA**; backups and restore
  testing will be required. No PostgreSQL resources are deployed by this Terraform.

Read the [architecture](../../docs/architecture/day2-aws.md),
[compatibility record](../../docs/infrastructure/compatibility.md),
[cost estimate](../../docs/infrastructure/costs.md) and
[bootstrap/deployment/teardown runbook](../../docs/infrastructure/runbook.md).

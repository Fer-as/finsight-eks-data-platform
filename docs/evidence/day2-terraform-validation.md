# Day 2 local validation evidence

Date: 13 October 2026. Branch: `feat/day2-terraform-infrastructure`.
Scope: local Terraform source, public dependency downloads and documentation.

| Check | Actual result |
|---|---|
| Repository/branch inspection | Clean Day 2 branch before implementation |
| Terraform CLI | 1.16.2 Windows AMD64; downloaded into ignored repo cache; SHA-256 matched official SHA256SUMS |
| Provider | hashicorp/aws 6.59.0, signed by HashiCorp; lock files generated in all three roots |
| `terraform fmt -recursive` / final `fmt -check -recursive` | Passed |
| Bootstrap `init -backend=false` and `validate` | Passed |
| Foundation `init -backend=false` and `validate` | Passed |
| Platform `init -backend=false` and `validate` | Passed |
| Provider-free configuration tests | 4 passed, 0 failed: merging/reserved tags, missing account, wrong Region, same state/data bucket |
| Mock-provider network tests | 5 passed, 0 failed: valid network, overlap, subnet outside VPC, duplicate AZ, wrong-Region AZ |
| Backend generator PowerShell parser | Passed; generator not run against real configuration |
| Backend generator synthetic fixture | Passed: three distinct keys, encryption, native locking, account restriction and refusal to overwrite |
| Ignore rules and whitespace | Local override/backend paths confirmed ignored; final `git diff --check` passed |
| Application change review | No diff in apps, pipelines, warehouse, Compose, application config/dependencies, tests or Day 1 verification script |
| Checkov baseline reproduction | 3.3.27 in pinned Docker image: 114 passed, 13 failed, 0 skipped, 0 parsing errors |
| Checkov after remediation | 130 passed, 0 failed, 15 resource-scoped exceptions, 0 parsing errors; exit 0 |
| AWS regional compatibility/catalog checks | NOT RUN: live AWS operations prohibited |
| Real Terraform plan/apply/destroy/backend migration | NOT RUN: prohibited |
| Kubernetes/Helm/application deployment | NOT RUN: outside scope |
| Day 1 application tests | Not rerun; application sources/configuration/dependencies unchanged |

Initial CLI/provider download attempts in the network-restricted sandbox failed before
contacting the public hosts. Retrying with authorized public-download network access succeeded.
No credentials were opened and no AWS account API calls or backend connections were made.
The complete validation script subsequently passed with public registry access. Network-test
initialization also needed permission to copy the cached provider binary; its lock file was
then populated with official signed checksums using `terraform providers lock`.
The generator fixture stayed under ignored `.cache/backend-generator-test` and used a
fictional account ID. Direct script invocation was initially blocked by PowerShell execution
policy; the explicit `powershell -NoProfile -ExecutionPolicy Bypass -File` invocation passed
without changing the machine's persistent policy.

Terraform ZIP SHA-256:
`6ef140ce1d399dc43b8315194176ddc2dfb5c21d607968e82ef20a55cfff40d0`.

The configuration tests use `command = plan` in a **provider-free, resource-free module**,
with synthetic fixtures. Network tests use `command = plan` with `mock_provider "aws"`,
including a mocked caller identity. Terraform's generic test output says "tearing down";
no real AWS provider operations, infrastructure apply or destroy were run.

Local validation proves HCL/provider-schema consistency and the tested configuration guards,
not IAM authorization, service readiness, regional version availability or successful deployment.
CSI and Pod Identity Agent pins remain deliberately unset, and compatibility attestation remains
false. Public pins for the other three add-ons are documented in the compatibility record.

Reproduce from repo root with
`powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-terraform.ps1`.
The initial implementation did not run Checkov because a host executable was unavailable.
The subsequent security review reproduced the user's Docker scan and supersedes that earlier
scan status. The validation script now requires the pinned Docker scanner and fails if it
cannot run. Scan-only command: `powershell -NoProfile -ExecutionPolicy Bypass -File
.\scripts\scan-terraform.ps1`.

## Security review and remediation

The unchanged initial scan reproduced **114 passed / 13 failed / 0 skipped** exactly.
After remediation: **130 passed / 0 failed / 15 skipped**, zero parsing errors in both.
Both original CKV_AWS_18 findings now **pass**; they were not suppressed. The 15 skips
comprise 11 original exceptions plus four specific to the new access-log destination.
A zero-failure scan with exceptions is not a claim that every Checkov policy is satisfied.

Scanner: Checkov **3.3.27**,
`bridgecrew/checkov@sha256:19ab1e9a08bf76f78391ca6fa46bb62fd08737e4e66466b16a82aa2d1337e153`.
The existing image was used without pulling a mutable tag. Docker runs with no network,
a read-only `infra/terraform` mount and an empty local Docker configuration; no credentials
are mounted. `--skip-download` prevents downloading external check metadata, not executing
checks. No global check exclusions, soft-fail flags or repository-wide suppression exist.
Only resource-local `#checkov:skip=<exact ID>:<reason>` annotations are present.

The full reports remain in ignored `.cache/checkov-before.json` and
`.cache/checkov/latest.json`. A sanitized [result manifest](day2-checkov-results.json)
records summaries and finding addresses without code excerpts or account values.
Checkov counts the ECR resource definition once; its for_each creates api/frontend/etl
repositories eventually. These counts do not prove provisioned resource counts.

### Original 13 findings: exact disposition

Categories: **Genuine** = security gap remediated; **Trade-off** = intentional assessment
choice with residual risk; **Static** = policy does not recognize the applicable AWS behavior.

| # | Policy ID | Exact Checkov resource address | Category / disposition | Controls and residual risk |
|---|---|---|---|---|
| 1 | CKV_AWS_136 | module.images.aws_ecr_repository.this | Trade-off; targeted exception ECR-KMS | Explicit AES256, immutable tags, scan-on-push, scoped publisher IAM. No independent KMS key authorization/revocation or per-key audit. |
| 2 | CKV_AWS_158 | module.eks.aws_cloudwatch_log_group.cluster | Trade-off; targeted exception LOGS-KMS | CloudWatch default AES-GCM; IAM authorization, seven-day retention, all five EKS log types. No independent customer key boundary; short incident-investigation window. |
| 3 | CKV_AWS_158 | module.network.aws_cloudwatch_log_group.flow | Trade-off; targeted exception LOGS-KMS | Default AES-GCM; scoped log writer, IAM reads, seven-day flow logs. Same key-control and retention limitations. |
| 4 | CKV_AWS_39 | module.eks.aws_eks_cluster.this | Trade-off; targeted exception EKS-ENDPOINT | Private endpoint plus explicit public CIDRs /24 or narrower, /32 recommended; explicit admin access entries, audit logging, no implicit creator admin. Public reachability remains for allowed addresses; compromised allowed hosts/credentials remain a risk. |
| 5 | CKV_AWS_58 | module.eks.aws_eks_cluster.this | Static; targeted exception EKS-SECRETS | Version constrained to 1.36; AWS-owned-key KMS v2 envelope encryption is automatic. No customer key control; this protects Kubernetes API data, not node disks. Node roots remain separately encrypted. |
| 6 | CKV2_AWS_62 | module.state.aws_s3_bucket.this | Trade-off; targeted exception S3-EVENTS | No state-event consumer is required; native lock files coordinate state writers. Versioning, TLS, IAM and newly configured access logs remain. No event-triggered alert/automation is provided. |
| 7 | CKV2_AWS_62 | module.data.aws_s3_bucket.this | Trade-off; targeted exception S3-EVENTS | ETL is explicitly invoked, not event-driven; encrypted private versioned storage and access logs. No immediate object-event processing or alerting. |
| 8 | CKV_AWS_144 | module.state.aws_s3_bucket.this | Trade-off; targeted exception S3-CRR | Versioning, prevent_destroy, no forced deletion, migration backup procedure. No cross-Region state recovery; a regional outage can block Terraform operations. Backup procedure is required later, not claimed executed. |
| 9 | CKV_AWS_144 | module.data.aws_s3_bucket.this | Trade-off; targeted exception S3-CRR | Deterministic synthetic data, retained versioned bucket, no forced deletion. No regional DR guarantee; artifacts/version history may not be reproducible even where source datasets are. |
| 10 | CKV_AWS_18 | module.state.aws_s3_bucket.this | Genuine audit gap; **fixed, now passes** | Required aws_s3_bucket_logging to separate state/ destination prefix. Source-bucket versioning and EKS/VPC logs never substituted for object-access evidence. Delivery is best effort and unverified until deployment. |
| 11 | CKV_AWS_18 | module.data.aws_s3_bucket.this | Genuine audit gap; **fixed, now passes** | Required aws_s3_bucket_logging to separate data/ prefix. Destination policy restricts exact source/account. Logs are not guaranteed complete, immutable or delivered immediately. |
| 12 | CKV_AWS_145 | module.state.aws_s3_bucket.this | Trade-off; targeted exception S3-KMS | Explicit SSE-S3, TLS-only access, public block, bucket-owner-enforced ownership, scoped state IAM, versioning and access logs. **State is sensitive**, even for synthetic workloads; an authorized/compromised S3 reader is not additionally constrained by a KMS key policy. |
| 13 | CKV_AWS_145 | module.data.aws_s3_bucket.this | Trade-off; targeted exception S3-KMS | Same S3 encryption/access protections; ETL scoped to raw/curated prefixes. No customer key separation/revocation or cryptographic-erasure control. |

The supplied assessment categories do not require customer-managed keys, cross-Region
replication or event notifications. They are not treated as plaintext-encryption defects,
and no production/compliance exemption is inferred. Detailed assessor requirements remain
pending and can supersede these temporary choices.

### EKS-SECRETS: verified service behavior

[AWS documents default envelope encryption](https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html)
for Kubernetes API data, including Secrets, on EKS 1.28 and later. EKS 1.36 therefore uses
KMS v2 and an **AWS-owned KMS key** without an explicit encryption_config or added key fee.
This is distinct from a customer-managed key or an AWS-managed alias such as aws/s3.

The installed Checkov 3.3.27 EKSSecretsEncryption policy was inspected inside the offline
image: it requires `encryption_config/[0]/resources == ["secrets"]` and does not evaluate
the Kubernetes version/default encryption behavior. Adding a customer key solely to satisfy
that test would add lifecycle/availability dependencies and cost. No encryption_config was
added. The version guard remains 1.36. Actual cluster behavior must still be verified after
an authorized deployment, e.g. in the EKS console; no deployed encryption evidence is claimed.

### Encryption exceptions: ECR-KMS, LOGS-KMS and S3-KMS

[AWS ECR encryption documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html)
confirms AES256 is at-rest encryption; KMS provides additional key control, not the only
encrypted option. ECR encryption is selected at repository creation, so reconsider before
first provisioning if the marking criteria require KMS.

[CloudWatch Logs documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html)
confirms default AES-GCM encryption. Customer KMS integration offers extra key-policy control
and also creates a dependency on key availability.

[SSE-S3 documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingServerSideEncryption.html)
confirms managed at-rest encryption without an extra encryption fee. The state bucket is
not dismissed as harmless synthetic data: access restrictions, retention and access logs
matter, and it must never be made public. These five KMS-preference findings are classified
as intentional trade-offs, not as scanner false positives.

### EKS-ENDPOINT: restricted public access preserved

[AWS supports combined private and restricted public endpoints](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html).
The installed CKV_AWS_39 policy checks only that endpoint_public_access is false; it does not
weigh the allowlist, IAM or operational access requirements. It correctly reports divergence
from a private-only policy, so this is a trade-off rather than an encryption-style false positive.

Private-only access via a VPC CloudShell environment is a possible safer future workflow,
not just a paid bastion/VPN option. Account permissions and operator connectivity have not
been verified under this no-AWS-access task. Preserve the approved endpoint configuration
until that workflow is tested and its change approved. Never widen CIDRs to make CI work.

### S3-EVENTS and S3-CRR

[AWS S3 event notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
support event-driven consumers; enabling a notification without a consumer does not provide
a useful audit or security control. State native locking does not rely on notifications.
If later ETL becomes event-driven, implement destinations, IAM, retries and idempotency together.

[AWS replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
is a distinct recovery/copying capability. Single-Region versioning does not replace regional
DR. No RPO/RTO or production HA claim is made; replication and failover require a separately
designed recovery workflow and cost estimate, particularly to avoid divergent Terraform states.

### LOG-DESTINATION: new resource and its four scoped exceptions

New address: `module.access_logs.aws_s3_bucket.this`, owned by bootstrap.
Its own checks create four additional skips, each attached only to that destination:

| Policy | Category | Reason, controls and residual risk |
|---|---|---|
| CKV_AWS_18 | Static policy unsuitable for this sink | AWS recommends destination logging stay disabled to avoid recursive logging. Private IAM access, versioning, TLS and protected retention remain; reads of the log archive itself are not covered by these server logs. |
| CKV_AWS_145 | Static policy incompatible with chosen delivery mode | Direct S3 server-log delivery requires an SSE-S3 destination. Encryption is explicit; no customer key separation. Switching delivery modes would be a different architecture/cost decision. |
| CKV_AWS_144 | Trade-off | Same-Region versioned audit archive with prevent_destroy; no regional disaster-recovery copy. |
| CKV2_AWS_62 | Trade-off | No event consumer is needed for the archive; no immediate event-driven audit alerting. |

[AWS destination requirements](https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-server-access-logging.html)
support a separate same-account/Region bucket with a logging.s3.amazonaws.com PutObject policy.
The implementation uses exact SourceArn and SourceAccount conditions, separate state/data
prefixes, no source read/delete grant and no ACL grants. Bucket-owner-enforced ownership,
public blocks, SSE-S3, versioning and prevent_destroy protect the archive. TLS denial excludes
AWS service principals whose network context can be redacted; the logging allow statement
still constrains service, source, account and destination prefix.

[Delivery is best effort](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ServerLogs.html);
this is not a CloudTrail data-event trail, real-time alerting, immutable archive or complete
forensic record. No automated reviewer or alarm is deployed. Current and noncurrent objects
each expire at 90 days by default, so logs can persist approximately 180 days plus processing
delay. Source state/data retention is unchanged. No Object Lock is enabled on this destination.

### Cost, validation and review conditions

No KMS keys, replication or event-processing services were added. A dedicated S3 log bucket
has no fixed bucket charge; 1 GB total stored logs at London's reviewed $0.024/GB-month rate
adds about $0.0008/day plus access costs. See the [updated cost estimate](../infrastructure/costs.md).
The $50 budget remains an alert threshold, not a cap.

Post-change checks actually executed: Terraform fmt; backend-disabled init and validate for
bootstrap/foundation/platform; four provider-free config tests; five mock-provider network
tests; pinned Checkov Docker scan. All passed with the 15 disclosed scanner exceptions.
No real Terraform plan/apply/destroy, AWS calls, backend initialization, commits or pushes
were performed. The nine Terraform tests test their existing configuration/network behaviors;
they do not prove S3 log delivery. The two original logging checks passing is static evidence only.

All exceptions are scoped to this temporary FinSight assessment. Re-review before first apply,
at the end of the assessment, and whenever data classification, Region, Kubernetes version,
access paths, retention or detailed rubric changes. Do not copy suppressions into production
without a new risk decision. Assessor acceptance has not been obtained.

Remaining deployment checks: verify both source logging configurations and delivered records;
confirm unrelated sources cannot deliver and unauthorized readers cannot read; verify actual
API CIDRs and EKS default encryption; review logs without exposing state/object key metadata.
Pending regional add-on verification and F5 assessor acceptance remain unchanged.

### Files changed by this security review

- `infra/terraform/modules/access-log-bucket/{main.tf,versions.tf,README.md}`: new log destination.
- `infra/terraform/modules/retained-bucket/{main.tf,README.md}`: required source logging and three scoped policy exceptions.
- `infra/terraform/modules/{ecr,eks,network}/main.tf`: documented resource-level exceptions.
- `infra/terraform/modules/config/{main.tf,README.md}`: require three distinct bucket names.
- `infra/terraform/config/{defaults.json,local.json.example}`: log bucket name and central retention setting.
- `infra/terraform/bootstrap/main.tf`, `infra/terraform/environments/dev/foundation/main.tf`: wire retained logging before source use.
- `infra/checkov-image.txt`, `scripts/scan-terraform.ps1`: pinned, offline Docker scan and local JSON report.
- `scripts/validate-terraform.ps1`: require the scanner after the existing tests.
- `infra/terraform/README.md`, `docs/architecture/day2-aws.md`, `docs/infrastructure/{costs,runbook}.md`: security, costs and operational updates.
- `docs/assessment-tracker.md`, this evidence document and `day2-checkov-results.json`: actual results and exact dispositions.

Application sources, Compose, dependencies and the nine existing test definitions were not modified.

# Day 2 AWS evidence: bootstrap, state migration and foundation

Recorded 14 October 2026 in `eu-west-2` with Terraform 1.16.2 and AWS provider 6.59.0. Each
write step had separate approval from the project owner and applied a saved, reviewed plan.
Account IDs, bucket names, ARNs, the hosted zone, IP addresses and state contents are
deliberately omitted. These resources are live; the EKS platform has **not** been deployed.

## Bootstrap root

| Step | Result |
|---|---|
| Init and plan (local state, no backend) | `Plan: 15 to add, 0 to change, 0 to destroy`, saved as `bootstrap.tfplan` |
| Pre-apply check | Saved plan unchanged since review; active account matched the configuration; `create` = 15 only |
| Apply of the saved plan | `Apply complete! Resources: 15 added, 0 changed, 0 destroyed.` |

Read-only verification of the two buckets after apply:

| Check | State bucket | Access-log bucket |
|---|---|---|
| Region | eu-west-2 | eu-west-2 |
| Default encryption | SSE-S3 (AES256) | SSE-S3 (AES256) |
| Versioning | Enabled | Enabled |
| Public access block (all four settings) | On | On |
| Object ownership | BucketOwnerEnforced | BucketOwnerEnforced |
| Policy public | No | No |
| Policy | Deny non-TLS | Deny non-TLS; allow only `logging.s3.amazonaws.com` to write `state/` and `data/` from the exact source buckets in this account |
| Lifecycle | Abort incomplete uploads only; state never expires | Logs and old versions expire after 90 days; expired delete markers removed |
| Server access logging | To the access-log bucket, prefix `state/` | Off by design |

## Bootstrap state migration to S3

| Step | Result |
|---|---|
| Destination check | State key absent; bucket empty before migration |
| First attempt (agent, piped confirmation) | Failed cleanly: `Error asking for confirmation: EOF`. No state written to S3; local state unchanged; lock released |
| Second attempt (owner, interactive terminal) | `Successfully configured the backend "s3"!` |
| Remote state | Present, SSE-S3, 15 resources; resource addresses and IDs identical to the pre-migration copy |
| Post-migration plan | `No changes. Your infrastructure matches the configuration.` |
| Locking | Native S3 lock file (`use_lockfile = true`) created and released during each operation; no lock left held |

Note: the remote state's internal lineage differs from the pre-migration copy, although its
resources are identical. Pre-migration backups therefore cannot be pushed back to the backend
without `terraform state push -force`; keep them for a reviewed recovery only.

## Foundation root

| Step | Result |
|---|---|
| Init | New S3 backend with its own key (`dev/foundation/terraform.tfstate`); no migration |
| Plan | `Plan: 18 to add, 0 to change, 0 to destroy`, saved as `foundation.tfplan` |
| Apply of the saved plan | `Apply complete! Resources: 18 added, 0 changed, 0 destroyed.` |
| Remote state | 18 resources |
| Post-apply plan | `No changes. Your infrastructure matches the configuration.` |

Read-only verification after apply:

- Data bucket: SSE-S3, versioning on, public access fully blocked, BucketOwnerEnforced,
  non-public policy that denies non-TLS access, access logs to the access-log bucket under
  `data/`, no expiry on data.
- ECR repositories `finsight-dev/api`, `finsight-dev/etl`, `finsight-dev/frontend`: immutable
  tags, scan on push, AES256, lifecycle expiring only untagged images after 7 days, no
  repository policy.
- GitHub roles `finsight-dev-github-images` and `finsight-dev-github-infra-plan`: one trust
  statement each, `sts:AssumeRoleWithWebIdentity` from the existing GitHub OIDC provider only,
  exact `StringEquals` on audience `sts.amazonaws.com` and on the repository's immutable
  subject plus `:environment:dev-images` or `:environment:dev-infrastructure`; one-hour
  sessions; no managed policies; inline policies scoped as reviewed (image push/pull to the
  three repositories; plan-only reads plus the platform state lock file).

## What this does not show

The platform root (VPC, subnets, NAT gateway, EKS, nodes, add-ons) has not been planned or
applied. No Kubernetes resources, controllers, DNS records or certificates exist.

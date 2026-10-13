# access-log-bucket

Dedicated retained S3 destination for state/data server access logs. Owned by bootstrap
so it survives platform teardown. Sources must be in the same account and Region.
The source bucket name strings avoid a dependency cycle with bucket creation.

| Input | Type | Meaning |
|---|---|---|
| name | string | Unique destination name from central access_log_bucket config |
| account_id | string | Exact permitted source account |
| source_buckets | map(string) | Prefix without slash to exact source bucket name; no wildcard source |
| retention_days | number | At least 90; current and noncurrent log expiry ages measured separately |

Output `id` exposes the destination after its delivery policy and security controls exist.
The policy allows only the S3 logging service to PutObject under each source's own prefix,
with exact SourceArn and SourceAccount conditions. It grants no read/delete permissions.
Private access, SSE-S3, bucket-owner-enforced ownership, versioning and prevent_destroy apply.
No Object Lock, Requester Pays, replication, KMS key or event consumer is introduced.

Current objects expire after 90 days by default; their resulting noncurrent versions expire
after another 90 days. Thus stored bytes can persist for approximately 180 days plus lifecycle
processing delay. Objects overwritten earlier have their own noncurrent-age clock.
Expired delete markers and abandoned multipart uploads are cleaned up.
State/data object retention is unchanged.

S3 recommends leaving logging disabled on the destination to avoid recursion. Direct S3
server-log delivery requires SSE-S3. Those resource-specific exceptions and the temporary
single-Region/no-event-consumer choices are documented in the
[security review](../../../../docs/evidence/day2-terraform-validation.md).
Delivery is best effort; this is not an immutable or complete forensic audit system.

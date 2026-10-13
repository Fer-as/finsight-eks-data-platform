# retained-bucket

Retained encrypted/versioned private S3 bucket. No object expiry or bucket force deletion.

Repository-owned module; changes are versioned by Git commit. AWS modules accept provider
6.59.x through 6.x; deployable roots pin exactly 6.59.0 and retain checksum locks.
The config module has no provider dependency. Common resource tags come from the caller's
AWS provider default_tags; EC2/EBS tag specifications are passed explicitly to eks.

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `name` | `string` | Required globally unique bucket name. |
| `access_log_bucket` | `string` | Required separate same-account, same-Region logging destination. |
| `access_log_prefix` | `string` | Prefix allowed by the destination policy: state/ or data/. |

## Outputs

| Output | Meaning |
|---|---|
| `id` | Bucket name. |
| `arn` | Bucket ARN. |

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

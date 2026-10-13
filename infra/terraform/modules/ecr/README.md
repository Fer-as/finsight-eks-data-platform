# ecr

Immutable, scanned, retained ECR repositories with untagged-only lifecycle expiry.

Repository-owned module; changes are versioned by Git commit. AWS modules accept provider
6.59.x through 6.x; deployable roots pin exactly 6.59.0 and retain checksum locks.
The config module has no provider dependency. Common resource tags come from the caller's
AWS provider default_tags; EC2/EBS tag specifications are passed explicitly to eks.

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `name` | `string` | Resource prefix. |
| `repositories` | `set(string)` | Application repository suffixes. |
| `untagged_retention_days` | `number` | At least 1; tagged images are never expired by this module. |

## Outputs

| Output | Meaning |
|---|---|
| `arns` | Map of repository name to ARN. |
| `urls` | Map of repository name to image URL. |

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

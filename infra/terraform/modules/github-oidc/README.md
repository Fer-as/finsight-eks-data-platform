# github-oidc

Exact GitHub environment trust with separate infrastructure plan-only and ECR publisher roles. No apply role.

Repository-owned module; changes are versioned by Git commit. AWS modules accept provider
6.59.x through 6.x; deployable roots pin exactly 6.59.0 and retain checksum locks.
The config module has no provider dependency. Common resource tags come from the caller's
AWS provider default_tags; EC2/EBS tag specifications are passed explicitly to eks.

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `name` | `string` | Resource prefix. |
| `account_id` | `string` | Expected AWS account. |
| `region` | `string` | Platform Region. |
| `config` | `object` | create_provider, existing_provider_arn, subject_prefix, infra_environment, images_environment. Explicit provider ownership required. |
| `state_bucket_arn` | `string` | Retained state bucket ARN. |
| `platform_state_key` | `string` | Only this state key is readable; its lock object is writable/deletable. |
| `repository_arns` | `list(string)` | Only these repositories are writable. |
| `zone_id` | `string` | Existing zone ID; read-only access. |

## Outputs

| Output | Meaning |
|---|---|
| `role_arns` | Map with infra_plan and images ARNs. |

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

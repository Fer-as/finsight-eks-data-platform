# github-oidc

Exact GitHub environment trust with separate roles: infrastructure plan-only, ECR publisher, and an
approval-gated platform apply role (inline policy limited to platform state; the foundation root
attaches the scoped apply policies from [terraform-ci-policies](../terraform-ci-policies); see
[terraform-ci.md](../../../../docs/infrastructure/terraform-ci.md)). Never creates the shared OIDC provider
unless `create_provider` is explicitly true.

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
| `config` | `object` | create_provider, existing_provider_arn, subject_prefix, infra_environment, images_environment, apply_environment (three distinct names, no wildcards). Explicit provider ownership required. |
| `state_bucket_arn` | `string` | Retained state bucket ARN. |
| `platform_state_key` | `string` | Only this state key is readable; its lock object is writable/deletable. |
| `repository_arns` | `list(string)` | Only these repositories are writable. |
| `zone_id` | `string` | Existing zone ID; read-only access. |

## Outputs

| Output | Meaning |
|---|---|
| `role_arns` | Map with infra_plan, images and infra_apply ARNs. |

Tests: [github-oidc.tftest.hcl](tests/github-oidc.tftest.hcl) (mocked provider).

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

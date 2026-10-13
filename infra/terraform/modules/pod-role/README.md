# pod-role

Reusable IAM role for EKS Pod Identity. The caller or EKS add-on owns the association.

Repository-owned module; changes are versioned by Git commit. AWS modules accept provider
6.59.x through 6.x; deployable roots pin exactly 6.59.0 and retain checksum locks.
The config module has no provider dependency. Common resource tags come from the caller's
AWS provider default_tags; EC2/EBS tag specifications are passed explicitly to eks.

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `name` | `string` | Unique IAM role name. |
| `cluster_arn` | `string` | Exact EKS cluster ARN. |
| `namespace` | `string` | Exact Kubernetes namespace. |
| `service_account` | `string` | Exact Kubernetes service account. |
| `policy_arns` | `set(string)` | Managed policy ARNs; default empty. |
| `inline_policy` | `string / null` | Optional JSON policy; default null. |

## Outputs

| Output | Meaning |
|---|---|
| `arn` | Role ARN after attachments are ready. |

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

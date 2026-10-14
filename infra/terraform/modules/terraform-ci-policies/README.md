# terraform-ci-policies

Builds the FinSight workload permissions boundary and the four managed policies for the
Terraform CI apply role, without AWS access. The foundation root creates them as IAM managed
policies and attaches the apply policies to `finsight-dev-github-infra-apply` (from
[github-oidc](../github-oidc)).

Repository-owned module; changes are versioned by Git commit. It has no provider dependency, so
its tests run offline.

| Output policy | Purpose |
|---|---|
| `boundary_policy` | `<name>-workload-boundary`: the ceiling for every platform role (cluster, nodes, flow logs, Pod Identity roles). No IAM, PassRole, STS or state access. |
| `apply_policies.guardrails` | Explicit denies: boundary removal, policy authoring, GitHub/admin roles, OIDC/SAML providers, users and keys, role assumption, other state files, resource-based policies, cluster access for other principals. |
| `apply_policies.roles` | The exact platform roles only (`platform_roles`): creation and policy changes only with the boundary (`iam:PermissionsBoundary`); approved AWS-managed policies only; PassRole to EKS, Pod Identity and flow logs only; service-linked roles. |
| `apply_policies.identity` | Platform state; EKS on the one cluster; access entries for admin roles only; scoped log groups; zone reads. |
| `apply_policies.network` | EC2 in the Region: request tag only on the new resource, ownership tag on every parent and every change, rules only in owned or EKS cluster security groups, no tagging of existing untagged resources. |

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `name` | `string` | Environment name prefix, for example `finsight-dev`. |
| `account_id` | `string` | 12-digit account ID. |
| `region` | `string` | Region all EC2, ELB and Logs actions are limited to. |
| `project_tag` | `string` | Value of the `Project` ownership tag; default `finsight`. |
| `state_bucket_arn` | `string` | Terraform state bucket ARN. |
| `platform_state_key` | `string` | The only state key the apply role may use. |
| `protected_state_keys` | `list(string)` | State keys explicitly denied (bootstrap, foundation). |
| `data_bucket` | `string` | Data bucket name the boundary allows for ETL. |
| `zone_id` | `string` | Hosted zone ID. |
| `admin_role_arns` | `list(string)` | The only principals that may receive EKS access entries. |
| `platform_roles` | `list(string)` | Suffixes of the roles the platform creates (`<name>-<suffix>`); default the nine current roles. A new platform role needs a foundation change first. |

## Outputs

| Output | Meaning |
|---|---|
| `boundary_name` | Boundary policy name. |
| `boundary_arn` | Boundary policy ARN, required by every platform role. |
| `boundary_policy` | Boundary JSON. |
| `apply_policies` | Map of `guardrails`, `roles`, `identity`, `network` JSON; each is checked against the 6,144-character managed-policy limit. |

Tests in [tests/](tests) use a synthetic evaluator ([tests/evaluator](tests/evaluator)): explicit
Deny over Allow, wildcards, and the condition operators used here, one resource per request. They
are evidence about the policy text, not proof of AWS behaviour. See
[terraform-ci.md](../../../../docs/infrastructure/terraform-ci.md) for the design and the
semantics still to verify. Do not apply modules directly.

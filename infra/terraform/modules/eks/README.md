# eks

EKS control plane, API access entries, private managed node group and five explicitly pinned managed add-ons.

Repository-owned module; changes are versioned by Git commit. AWS modules accept provider
6.59.x through 6.x; deployable roots pin exactly 6.59.0 and retain checksum locks.
The config module has no provider dependency. Common resource tags come from the caller's
AWS provider default_tags; EC2/EBS tag specifications are passed explicitly to eks.

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `name` | `string` | Cluster/resource prefix. |
| `subnet_ids` | `list(string)` | Private subnet IDs. |
| `tags` | `map(string)` | Common tags propagated to node EC2/EBS resources; default empty. |
| `config` | `object` | version, public_access_cidrs, admin_role_arns, instance_types, min_size, desired_size, max_size, disk_size_gb, optional ami_release_version, log_retention_days, compatibility_verified, addon_versions. Required fields/types/guards are declared in main.tf. |

## Outputs

| Output | Meaning |
|---|---|
| `name` | Cluster name. |
| `arn` | Cluster ARN. |
| `endpoint` | Restricted Kubernetes API endpoint. |
| `node_group_name` | Managed group name. |
| `addon_versions` | Configured version map. |
| `cluster_security_group_id` | EKS-created cluster security group shared by control plane, nodes and pods. |

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

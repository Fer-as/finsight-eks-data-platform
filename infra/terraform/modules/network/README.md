# network

Two-AZ VPC with private workers, one NAT, S3 gateway endpoint and CloudWatch flow logs.

Repository-owned module; changes are versioned by Git commit. AWS modules accept provider
6.59.x through 6.x; deployable roots pin exactly 6.59.0 and retain checksum locks.
The config module has no provider dependency. Common resource tags come from the caller's
AWS provider default_tags; EC2/EBS tag specifications are passed explicitly to eks.

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `name` | `string` | Resource prefix. |
| `region` | `string` | AWS Region. |
| `config` | `object` | vpc_cidr, two availability_zones, two public_cidrs, two private_cidrs, log_retention_days. See central defaults. |

## Outputs

| Output | Meaning |
|---|---|
| `vpc_id` | VPC ID; preconditions reject overlapping/out-of-VPC subnets or wrong-Region AZs. |
| `private_subnet_ids` | Private subnet IDs in configured AZ order. |
| `public_subnet_ids` | Public subnet IDs in configured AZ order. |
| `nat_gateway_id` | Single NAT ID for inventory/teardown. |

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

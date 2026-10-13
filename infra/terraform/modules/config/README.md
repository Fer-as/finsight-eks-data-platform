# config

Loads central defaults and optional local JSON overrides without AWS access.

Repository-owned module; changes are versioned by Git commit. AWS modules accept provider
6.59.x through 6.x; deployable roots pin exactly 6.59.0 and retain checksum locks.
The config module has no provider dependency. Common resource tags come from the caller's
AWS provider default_tags; EC2/EBS tag specifications are passed explicitly to eks.

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `override_file` | `string / null` | Optional absolute override JSON path; defaults to config/local.json. |

## Outputs

| Output | Meaning |
|---|---|
| `value` | Merged configuration; rejects missing account, wrong Region/names, shared state/data/access-log bucket names. |
| `name` | Stable project-environment prefix. |
| `tags` | Common tags with reserved ownership keys. |

See [main.tf](main.tf) for complete type constraints and [central defaults](../../config/defaults.json)
for the dev example. Usage is demonstrated by the [bootstrap](../../bootstrap/main.tf),
[foundation](../../environments/dev/foundation/main.tf) and
[platform](../../environments/dev/platform/main.tf) roots. Do not apply modules directly.

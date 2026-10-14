# dns-policies

Builds the two Route 53 identity policies for the DNS controllers, without AWS access. The
platform root attaches them to separate Pod Identity roles through [pod-role](../pod-role).

Repository-owned module; changes are versioned by Git commit. Like the config module, it has
no provider dependency, so its tests run offline.

| Policy | Allows | Does not allow |
|---|---|---|
| `external_dns` | `ChangeResourceRecordSets` in the one zone, only for the application hostname (its A/AAAA alias) and its TXT ownership names (`a-`, `aaaa-` prefixed, as written by ExternalDNS v0.23.0), only A, AAAA and TXT; `ListResourceRecordSets` in that zone; `ListHostedZones` (AWS cannot scope it) | Other zones, other names, CNAME/NS/MX and other types, `_acme-challenge` records |
| `cert_manager` | `ChangeResourceRecordSets` in the one zone for `_acme-challenge.<hostname>` TXT only; `ListResourceRecordSets` in that zone; `GetChange` on change resources | Zone discovery (the ClusterIssuer must set `hostedZoneID`), any application record |

## Inputs

| Input | Type | Purpose/default |
|---|---|---|
| `zone_id` | `string` | Hosted zone ID without the `/hostedzone/` prefix. |
| `hostname` | `string` | Lowercase application hostname without a trailing dot. |

## Outputs

| Output | Meaning |
|---|---|
| `external_dns` | ExternalDNS policy JSON. |
| `cert_manager` | cert-manager DNS-01 policy JSON. |
| `external_dns_record_names` | Names ExternalDNS may change. |
| `acme_challenge_record` | The only name cert-manager may change. |

Controller settings these policies assume are in
[dns-and-certificates.md](../../../../docs/infrastructure/dns-and-certificates.md). Tests:
[dns-policies.tftest.hcl](tests/dns-policies.tftest.hcl). Do not apply modules directly.

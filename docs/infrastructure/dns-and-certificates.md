# DNS and certificate identities

Decision record, 14 October 2026 (issue #6). Terraform defines the IAM side only; no
controller, DNS record or certificate exists yet, and nothing here has been applied.

## Decisions

| Topic | Decision | Reason |
|---|---|---|
| Certificate validation | cert-manager with Let's Encrypt **DNS-01** through Route 53 | Works before the load balancer and DNS record exist, and does not depend on the ingress serving `/.well-known/acme-challenge/` |
| Application DNS | **ExternalDNS** manages the application record in the existing public hosted zone | Records follow the Ingress, as G04 requires |
| Workload identity | **EKS Pod Identity**, one role per controller | Matches the existing CNI, EBS CSI and ETL roles; no OIDC provider per cluster |
| Separation | ExternalDNS and cert-manager get **separate roles with non-overlapping record names** | A compromise of one controller cannot change the other's records |
| Ingress | F5 NGINX Ingress Controller behind a public NLB created by the AWS Load Balancer Controller | Planned; see "Dependencies" |

## What each role may do

Both policies are built by [modules/dns-policies](../../infra/terraform/modules/dns-policies)
and attached in the platform root through the existing `pod-role` module.

| Role | Kubernetes identity | Allowed | Scope |
|---|---|---|---|
| `finsight-dev-external-dns` | namespace `external-dns`, service account `external-dns` | `route53:ChangeResourceRecordSets` | The one hosted zone; record names limited to the application hostname, `a-<hostname>` and `aaaa-<hostname>`; record types limited to A, AAAA and TXT |
| | | `route53:ListResourceRecordSets` | The one hosted zone |
| | | `route53:ListHostedZones` | `*`. AWS does not support resource-level scoping for this action; it returns zone metadata only |
| `finsight-dev-cert-manager` | namespace `cert-manager`, service account `cert-manager` | `route53:ChangeResourceRecordSets` | The one hosted zone; record name `_acme-challenge.<hostname>` only; type TXT only |
| | | `route53:ListResourceRecordSets` | The one hosted zone |
| | | `route53:GetChange` | `arn:aws:route53:::change/*`. Change IDs are not known in advance; the action only reports propagation status |

Both roles trust only `pods.eks.amazonaws.com`, only for the FinSight cluster ARN, and only for
their exact namespace and service account (session tags checked in the trust policy). Neither
has managed policies, and neither can touch other zones, NS/SOA/MX/CNAME records, or each
other's records. Name and type limits use the Route 53 condition keys
`route53:ChangeResourceRecordSetsNormalizedRecordNames` and
`route53:ChangeResourceRecordSetsRecordTypes`; names are compared in Route 53's normalised
form (lowercase, no trailing dot), which the module enforces for the hostname input.

The unit tests in `modules/dns-policies/tests` check the zone ARN, record names, record types,
the wildcard exception and that the two policies cannot change each other's records.

## Ownership and TXT registry (R6.5)

ExternalDNS must run with settings that stay inside the role's limits:

- `--provider=aws`, `--registry=txt`, `--txt-owner-id=finsight-dev`
- `--domain-filter=<hostname>` and `--zone-id-filter=<zone id>`
- the default TXT naming (no `--txt-prefix` or `--txt-suffix`): the ownership records are
  `a-<hostname>` and `aaaa-<hostname>`
- `--policy=sync`, so that removing the Ingress also removes the records; the TXT owner ID
  stops it deleting records it did not create
- service account `external-dns` in namespace `external-dns`, with no IRSA annotation

A different TXT prefix or extra hostnames will be denied by IAM; change the module and its
tests first.

Verified on 14 October 2026 against the ExternalDNS **v0.23.0** source (`registry/txt`,
`registry/mapper`, `provider/aws`):

- `ToTXTName` lowercases the record type and prefixes the first label: an A alias record for
  `eks.<domain>` gets the ownership TXT `a-eks.<domain>`; AAAA gets `aaaa-eks.<domain>`.
- The registry writes only this format. Legacy formats (a bare-name TXT, or `cname-` for alias
  records) are read for migration but never written, so the role does not allow them.
- The record and its TXT are submitted in the same `ChangeResourceRecordSets` batch. Route 53
  condition keys apply to the whole batch, so names and types must be in one statement;
  splitting them per type would deny every change.
- The AWS provider calls `ListHostedZones` and `ListResourceRecordSets` (paginated) and
  `ChangeResourceRecordSets`. It calls `ListTagsForResources` only when a zone tag filter is
  set, which this design does not use.

Pin the ExternalDNS chart to a release using v0.23.0, or re-check this naming before
upgrading.

## cert-manager configuration this assumes

- Service account `cert-manager` in namespace `cert-manager` (the chart default), no IRSA
  annotation; Pod Identity supplies credentials through the standard AWS SDK chain.
- ClusterIssuers (staging and production) use the `route53` DNS-01 solver with `region:
  eu-west-2` and an explicit `hostedZoneID`. The role deliberately lacks
  `ListHostedZonesByName`, so zone auto-discovery will fail.
- The certificate covers the single application hostname. Wildcards or extra names need a
  policy change.

## Dependencies and remaining work

- **AWS Load Balancer Controller role: [#34](https://github.com/Fer-as/finsight-eks-data-platform/issues/34).** Originally part of #6 and
  moved to its own issue. It needs AWS's published controller policy, which is large (EC2 and
  Elastic Load Balancing actions with tag conditions), pinned to the controller version and
  reviewed separately. Until it exists, the NGINX Service cannot get its NLB.
- **Controllers.** Installing ExternalDNS (#22), cert-manager (#21) and NGINX (#20) through
  Argo CD is later work. The Pod Identity associations exist before the pods; the controllers
  must use exactly the namespaces and service accounts above.
- **Apply.** These roles are created with the platform root. The expected platform plan grows
  by 6 resources (two roles, two inline policies, two associations).

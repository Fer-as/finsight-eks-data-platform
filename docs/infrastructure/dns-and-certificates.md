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
- `--policy=upsert-only` (owner decision, 15 October 2026): records are created and updated,
  never deleted. G04.5's removal step needs `policy: sync` for the evidence window. The TXT owner ID
  and this role still limit it to FinSight's own records.
- `--managed-record-types=A,AAAA`: a CNAME (and its `cname-` TXT) would be denied by IAM
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
  moved to its own issue. Now defined in Terraform from AWS's published v3.6.0 policy, pinned
  and scoped to this cluster, with no Route 53 permissions; see
  [load-balancer-controller.md](load-balancer-controller.md). Not yet applied.
- **Controllers.** Installing ExternalDNS (#22), cert-manager (#21) and NGINX (#20) through
  Argo CD is later work. The Pod Identity associations exist before the pods; the controllers
  must use exactly the namespaces and service accounts above.
- **Apply.** These roles are created with the platform root. The expected platform plan grows
  by 6 resources (two roles, two inline policies, two associations).

## Implementation (G04, issues #21 and #22)

Status, 15 October 2026: **implemented locally and validated offline; not deployed.**

| Component | Pin | Files |
|---|---|---|
| cert-manager | chart and app **v1.21.2** (`https://charts.jetstack.io`). The 1.21 line is the only supported release covering Kubernetes 1.33–1.36 | `gitops/platform/cert-manager/` (values, Argo CD Application). CRDs come from the chart (`crds.enabled`, `keep`) |
| ClusterIssuers | `letsencrypt-staging` and `letsencrypt-production`, Route 53 DNS-01, `region: eu-west-2`, explicit `hostedZoneID`, solver limited to `eks.feras-dev.co.uk` | `gitops/platform/cluster-issuers/` (small chart). It refuses to render without a valid zone ID or hostname |
| ExternalDNS | chart **1.23.0**, image **v0.23.0** (`https://kubernetes-sigs.github.io/external-dns/`) | `gitops/platform/external-dns/` (values, Argo CD Application) |
| Ingress TLS | `gitops/apps/finsight`: `ingress.tls.enabled=true` adds the TLS block for the host with secret `finsight-tls`, plus `cert-manager.io/cluster-issuer` (staging by default) and `cert-manager.io/renew-before: 720h` | Switched with values only; no template edits |

**Identity and permissions.** The service accounts match the Terraform Pod Identity
associations:
- `cert-manager/cert-manager`
- `external-dns/external-dns`

There are no IRSA annotations, no access keys and no `role` in the issuers.

**Record names** were checked against the v0.23.0 source (`registry/mapper` `ToTXTName`) and
against the `dns-policies` module rendered for this hostname.
- **ExternalDNS writes** `eks.feras-dev.co.uk` (A or AAAA alias) and `a-` / `aaaa-eks.feras-dev.co.uk`
  (TXT). These are exactly the names the role allows, and nothing more.
- **cert-manager writes** only `_acme-challenge.eks.feras-dev.co.uk` (TXT), which is its role's
  only name.
- **Domain filter.** `--domain-filter=eks.feras-dev.co.uk` keeps the parent zone through
  `MatchParent`, and the registry, not the plan filter, handles the ownership TXT records.

**Install order** (after the platform, the AWS Load Balancer Controller and NGINX; the zone ID
comes from the private config's `dns.zone_id`):

```powershell
helm repo add jetstack https://charts.jetstack.io; helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/; helm repo update
helm upgrade --install cert-manager jetstack/cert-manager --version v1.21.2 -n cert-manager --create-namespace -f gitops/platform/cert-manager/values.yaml
helm upgrade --install cluster-issuers gitops/platform/cluster-issuers -n cert-manager --set route53.hostedZoneID=<zone id>
helm upgrade --install external-dns external-dns/external-dns --version 1.23.0 -n external-dns --create-namespace -f gitops/platform/external-dns/values.yaml --set-string extraArgs.zone-id-filter=<zone id>
helm upgrade --install finsight gitops/apps/finsight -n finsight --reuse-values --set ingress.tls.enabled=true                 # staging first
helm upgrade --install finsight gitops/apps/finsight -n finsight --reuse-values --set ingress.tls.clusterIssuer=letsencrypt-production   # after staging succeeds
```

**Live evidence needed for full marks** (nothing here can be proven offline):
1. `kubectl -n cert-manager get pods` all Running, and `kubectl get clusterissuer` shows both
   issuers Ready.
2. With the staging issuer, the `challenge` and `order` reach `valid`.
   `kubectl -n cert-manager logs deploy/cert-manager` shows Route 53 propagation with no
   `AccessDenied`.
3. With the production issuer:
   - `kubectl -n finsight get certificate finsight-tls` shows Ready=True
   - `kubectl describe certificate` shows the issuer is Let's Encrypt and the SAN is
     `eks.feras-dev.co.uk`
4. **Renewal (G04.3):** run `cmctl renew finsight-tls -n finsight`, and show that the serial
   changes and the secret updates.
5. **ExternalDNS logs** show only the A (or AAAA) alias and `a-` / `aaaa-` TXT changes for the
   host, with no `AccessDenied`.
   `aws route53 list-resource-record-sets` shows the alias pointing to the NLB, and the owner TXT
   `"heritage=external-dns,external-dns/owner=finsight-dev"`.
6. **Record lifecycle (G04.5):** changing the Ingress updates the record. Deleting it removes
   the record **only if `policy=sync`** for that test. Switch with a values-only change, then
   switch back:

   ```powershell
   helm upgrade external-dns external-dns/external-dns --version 1.23.0 -n external-dns --reuse-values --set policy=sync
   ```
7. `curl -v https://eks.feras-dev.co.uk/` shows a trusted chain with no warnings and HTTP 200,
   and `http://` returns a 301 to `https://`. Take a browser screenshot.

# DNS and HTTP evidence via eks.feras-dev.co.uk (G03, G04)

Captured 2026-10-16 07:46:10Z. ExternalDNS fix: PR #48 (flag added) and PR #49 (boolean form; #48's string value crash-looped the pod). Zone ID redacted; HTTP only, TLS not yet enabled.

## ExternalDNS (v0.23.0, policy upsert-only, owner finsight-dev)
```
2026-10-16T07:43:59Z Applying provider record filter for domains: [feras-dev.co.uk. .feras-dev.co.uk.]
2026-10-16T07:43:59Z Desired change: CREATE a-eks.feras-dev.co.uk TXT
2026-10-16T07:43:59Z Desired change: CREATE aaaa-eks.feras-dev.co.uk TXT
2026-10-16T07:43:59Z Desired change: CREATE eks.feras-dev.co.uk A
2026-10-16T07:43:59Z Desired change: CREATE eks.feras-dev.co.uk AAAA
2026-10-16T07:43:59Z 4 record(s) were successfully updated
2026-10-16T07:44:59Z Applying provider record filter for domains: [feras-dev.co.uk. .feras-dev.co.uk.]
```

## Route 53 zone feras-dev.co.uk (all record sets; NS/SOA unchanged from before the fix)
```
feras-dev.co.uk.             NS    (AWS name servers)
feras-dev.co.uk.             SOA   (AWS name servers)
a-eks.feras-dev.co.uk.       TXT   "heritage=external-dns,external-dns/owner=finsight-dev,external-dns/resource=ingress/finsight/finsight"
aaaa-eks.feras-dev.co.uk.    TXT   "heritage=external-dns,external-dns/owner=finsight-dev,external-dns/resource=ingress/finsight/finsight"
eks.feras-dev.co.uk.         A     ALIAS -> k8s-nginxing-nginxing-<redacted>.elb.eu-west-2.amazonaws.com.
eks.feras-dev.co.uk.         AAAA  ALIAS -> k8s-nginxing-nginxing-<redacted>.elb.eu-west-2.amazonaws.com.
```

## Resolution and HTTP
```
eks.feras-dev.co.uk A: 2 addresses, identical to the NLB's addresses (authoritative and 8.8.8.8); AAAA: none (IPv4 NLB)
GET http://eks.feras-dev.co.uk/                          -> 200
GET http://eks.feras-dev.co.uk/api/health/ready          -> 200
GET http://eks.feras-dev.co.uk/api/departments           -> 200
GET http://eks.feras-dev.co.uk/api/dashboard             -> 200
GET http://eks.feras-dev.co.uk/assets/does-not-exist.js  -> 404
GET http://eks.feras-dev.co.uk/no-such-page              -> 404
GET http://eks.feras-dev.co.uk/metrics                   -> 404
dashboard: currency=GBP period=2025-01-01..2026-01-01 has_data=True
```

## Argo CD Applications
```
NAME                           SYNC     HEALTH    REVISION
aws-load-balancer-controller   Synced   Healthy   <none>
cert-manager                   Synced   Healthy   <none>
cluster-issuers                Synced   Healthy   24f07a8d076402af000e7d2fe641bc19b3731f28
external-dns                   Synced   Healthy   <none>
finsight                       Synced   Healthy   24f07a8d076402af000e7d2fe641bc19b3731f28
finsight-root                  Synced   Healthy   24f07a8d076402af000e7d2fe641bc19b3731f28
monitoring                     Synced   Healthy   <none>
nginx-ingress                  Synced   Healthy   <none>
```

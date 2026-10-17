# Application verification through the NLB (G03, R4.1)

Captured 2026-10-16 06:48:42Z. Requests sent to the NLB hostname with Host: eks.feras-dev.co.uk because the DNS record is not yet created (ExternalDNS issue). HTTP only; TLS not yet enabled.

```
NLB: k8s-nginxing-nginxing-<redacted>.elb.eu-west-2.amazonaws.com (network, internet-facing, active, 2 AZs)
GET /                            -> 200
GET /api/health/ready            -> 200
GET /api/departments             -> 200
GET /api/dashboard               -> 200
GET /assets/does-not-exist.js    -> 404
GET /no-such-page                -> 404
GET /metrics                     -> 404
dashboard: currency=GBP period=2025-01-01..2026-01-01 has_data=True
```

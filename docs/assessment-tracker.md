# EKS assessment tracker

**135 available points**, using the category allocations supplied by the project owner.
Detailed marking criteria within each category remain pending. No earned points are claimed.
Local implementation is not evidence of a successful AWS deployment.

| Category | Available points | Planned artifacts / evidence | Current status |
|---|---:|---|---|
| Board and tickets | 10 | GitHub project board, scoped issues, acceptance criteria, linked PRs | Not created; no GitHub changes authorized |
| Terraform infrastructure | 15 | Reusable modules, central config, secure remote state, reviewed plans and deployed verification | Local validation and nine tests pass; Checkov 130 passed / 0 failed / 15 documented exceptions; AWS verification pending |
| NGINX Ingress Controller | 10 | Maintained F5 NGINX chart, controller health, application routing | Planned; **assessor acceptance pending**; retired community ingress-nginx must not be deployed |
| CertManager and ExternalDNS | 20 | Certificate Ready, Let's Encrypt HTTPS, scoped Route 53 reconciliation/ownership | Deferred; existing zone referenced read-only in Terraform; no DNS records/controllers created |
| Monitoring | 15 | Prometheus targets, Grafana dashboards, operational evidence | Deferred |
| Terraform CI/CD pipeline | 10 | Concise workflow, formatting/validation/security scans, protected OIDC plan and reviewed deployment process | Plan-only OIDC role implemented locally; workflow and apply-role design deferred |
| Application, security and Docker CI/CD pipeline | 30 | Tests, Checkov/Trivy results, image builds/digests, ECR publication and deployment evidence | Day 1 local application/tests exist; retained ECR and publisher role implemented locally; pipeline deferred |
| ArgoCD GitOps | 15 | Application/repository configuration, Synced/Healthy state, reconciliation evidence | Deferred |
| Architecture documentation | 10 | Original draw.io source with official AWS icons/boundaries; architecture, costs and teardown docs | Day 1/2 Markdown/Mermaid docs exist; original draw.io and deployed evidence pending |
| **Total available** | **135** | | **No scoring claim** |

Additional project requirements:

| Requirement | Status / evidence still needed |
|---|---|
| Original financial application using synthetic data | Day 1 implemented; see local evidence |
| Genuine ETL and ELT | ETL implemented locally; separate ELT/dbt path reserved for Day 5 |
| HTTPS at eks.<domain> or eks.labs.<domain> | Planned hostname only; DNS, certificate and public application test pending |
| EKS 1.36 STANDARD and managed add-ons | Terraform implemented; two regional add-on pins deliberately unset pending authorized compatibility checks |
| Two private m7i.large workers | Configurable in Terraform; actual readiness/AZ placement must be observed after deployment |
| Secure retained storage/state | Encryption/versioning/public block/retention and separate S3 access-log destination implemented; bootstrap/migration and delivery verification not performed |
| $50 budget awareness | Estimated costs and teardown runbook documented; alert is not a spending cap |

Evidence: [Day 1](evidence/day1-verification.md),
[Day 2 local validation](evidence/day2-terraform-validation.md),
[Day 2 architecture](architecture/day2-aws.md),
[infrastructure README](../infra/terraform/README.md).

For each category, add the exact subcriteria when supplied, map each to a concrete artifact
and test, and attach dated redacted evidence after actual execution. Never mark a deployment,
CI run, security scan or assessment category complete based solely on planned configuration.

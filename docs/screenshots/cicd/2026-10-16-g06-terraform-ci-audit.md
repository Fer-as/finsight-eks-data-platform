# G06 Terraform CI audit (16 Oct 2026, read-only)

No workflow was dispatched: the plan-only workflow has no manual trigger. Main at ff82177.

## Workflows
```
terraform.yml  (plan-only, PR review): on pull_request to main for infra/terraform/**, infra/checkov-image.txt, scripts/{validate,scan}-terraform.ps1, scripts/new-terraform-backend-config.ps1, scripts/ci/**, .github/actions/install-age/**, the workflow itself. No workflow_dispatch.
  jobs: checks (contents: read; fmt/validate/tests/Checkov) -> plan (environment dev-infrastructure [required reviewer Fer-as, admin bypass off], id-token: write, OIDC role vars.AWS_ROLE_ARN = finsight-dev-github-infra-plan, assert-terraform-ci-account.ps1 -Role plan, lock-timeout 5m, no force-unlock)
  output: value-free summary (summarize-terraform-plan.ps1: counts, masked addresses, actions); binary plan NOT uploaded; plan/config/backend files removed with if: always()
terraform-apply.yml  (protected apply): workflow_dispatch on main only, input allow_destroy (default false)
  plan job (dev-infrastructure, plan role) -> age-encrypted saved plan artifact only if has_changes; gate refuses delete/replace/forget unless allow_destroy and ALWAYS refuses VPC/EKS cluster lifecycle changes
  apply job only if has_changes: environment dev-infrastructure-apply (required reviewer Fer-as, main only, bypass off), apply role, config/plan digest checks, applies the reviewed saved plan only
```

## Configuration and drift
```
CI TERRAFORM_CONFIG_JSON (both environments) = local.json bytes uploaded 2026-10-15T20:28Z: instance_types m7i-flex.large, compatibility_verified true, account == caller, region eu-west-2
local read-only refresh plan (platform root, not saved): exit 0 - No changes. Your infrastructure matches the configuration.
platform state: 68 managed resources from the reviewed saved plan applied locally on 2026-10-16 05:18-05:31Z
```

## Existing GitHub evidence
```
terraform.yml PR run 38573056287 (2026-10-14, feat/terraform-plan-workflow): success (plan skipped by the compatibility gate at that time)
terraform.yml PR run 38594653778 (2026-10-14): cancelled (pending approval expired)
terraform-apply.yml: never run
```

# Secret scan (R6.1), 20 October 2026

Run locally against `main` at `065c928`, with pinned scanner images and no network access
(`docker run --network none`).

| Scan | Scope | Result |
|---|---|---|
| Trivy 0.75.0, `fs --scanners secret` | Working tree | Passed: no secrets found |
| Checkov (`infra/checkov-image.txt`), `--framework secrets` | Working tree | 1 finding, a false positive (below) |
| Pattern scan of every added line in history | All 76 commits on `main` | No AWS access keys, AWS secret keys, private keys, age secret keys, GitHub or Slack tokens, or PostgreSQL URLs with passwords |
| Trivy in CI, default scanners `vuln,secret` | Each built image (api, etl, frontend) | No HIGH or CRITICAL secret finding; the gate passed for all three images in run 38761479287 |

## Findings reviewed

- **Checkov `CKV_SECRET_6` in `gitops/platform/monitoring/values.yaml`.** It flags the key names
  `admin-user` and `admin-password` under `existingSecret: grafana-admin`. They name keys in a Secret
  created outside Git; no value is present.
- **Pattern scan.** It matched `SECRET = "finsight-database"` in `tests/gitops/test_database.py`, which
  is a Secret name. The only account ID in any ARN in history is the documentation placeholder
  `111111111111`, used in Terraform tests.

## Secret mechanism

The database and Grafana credentials are Kubernetes Secrets created before the first sync by
`scripts/new-cluster-secrets.ps1`, which prompts for each value and never prints or stores it.
Manifests reference the Secrets by name only. The reasons are in
[Argo CD](../infrastructure/argocd.md#bootstrap-during-a-deployment-window) and decision 13 of the
[decision index](../architecture/decisions.md).

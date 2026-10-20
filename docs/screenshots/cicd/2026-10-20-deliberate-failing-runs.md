# Deliberately failing pipeline runs (G06.6, G07.8), 20 October 2026

Three temporary draft pull requests, each branched from `main` at `065c928`, made one deliberate
change so that the pipeline would fail. None of them was merged; they are closed unmerged once this
evidence is accepted.

## Why these runs could not change AWS or publish images

Checked in the workflows before the pull requests were opened:
- **Terraform** ([terraform.yml](../../../.github/workflows/terraform.yml)): the `plan` job has
  `needs: checks`, so it does not start when the checks fail, and it also waits for the
  `dev-infrastructure` environment. The checks job has `contents: read` only and no AWS credentials.
  Apply ([terraform-apply.yml](../../../.github/workflows/terraform-apply.yml)) is `workflow_dispatch`
  only.
- **Application** ([app.yml](../../../.github/workflows/app.yml)): `publish` has
  `needs: [python, frontend, checkov, images]` and runs only on a push to `main`, in the `dev-images`
  environment; `gitops` needs `publish`. The scanned image is kept as an artifact only on a push to
  `main`.

On a pull request, `publish` is also skipped by its event condition. On `main`, the `needs` chain is
what stops publishing after a failed test or scan.

## Runs

| Criterion | Pull request | Run | Deliberate change | Failed at | Skipped |
|---|---|---|---|---|---|
| G06.6, R7.3 | [#64](https://github.com/Fer-as/finsight-eks-data-platform/pull/64) | [39387242933](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/39387242933) | One misaligned assignment in `environments/dev/platform/main.tf` | `fmt, validate, test and Checkov`: `terraform fmt -check` listed `main.tf`, then "Terraform formatting failed." | `Plan platform (plan-only role)`: no AWS credentials requested |
| G07.8, R7.1 | [#65](https://github.com/Fer-as/finsight-eks-data-platform/pull/65) | [39387572606](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/39387572606) | One test that always fails, `apps/api/tests/test_ci_failure_experiment.py` | `Python lint and tests`: pytest reported 1 failed, 40 passed | `Publish images to ECR (OIDC)`, `Propose the new image versions (GitOps pull request)` |
| G07.8, R7.4 | [#66](https://github.com/Fer-as/finsight-eks-data-platform/pull/66) | [39387251772](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/39387251772) | Frontend production stage moved to `nginx-unprivileged:1.25.3-alpine` (2023), pinned by digest | `Build and scan frontend image`: the Trivy gate found 19 fixable findings (16 HIGH, 3 CRITICAL) | `Publish images to ECR (OIDC)`, `Propose the new image versions (GitOps pull request)` |

All other jobs in each run passed. No run produced an artifact.

Screenshots, captured logged out from the public run pages:
- [Terraform formatting failure](terraform-fmt-failure-run-39387242933.png)
- [Failing unit test](app-failing-test-run-39387572606.png)
- [Trivy-blocked frontend image](app-trivy-blocked-run-39387251772.png)

## A finding on `main` found during the experiment

The first run on #65, [39387249888](https://github.com/Fer-as/finsight-eks-data-platform/actions/runs/39387249888),
also failed the frontend Trivy gate, although the frontend was unchanged. The base image pinned on
`main`, `nginx-unprivileged:1.30.6-alpine3.24`, now has two fixable HIGH findings published after the
last image build on 15 October 2026:
- libexpat CVE-2026-77214, fixed in 2.9.0-r0;
- libx11 CVE-2026-88806, fixed in 1.8.14-r0.

The deployed frontend image was built from the same base image, so it contains the same packages. It
has not been rebuilt or redeployed: the deployed image is **not** remediated.
The gate did what it should: the next publish from `main` would stop at this step.

Upstream rebuilt the same tag on 19 October 2026. With that digest added to #65, the frontend image
passed the gate in run 39387572606, and the failing test became the only failure. Moving `main` to
that digest is a separate change for review; it is not part of this evidence.

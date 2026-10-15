# Application pipeline (G07)

Status, 15 October 2026: **implemented and tested locally; not yet run on GitHub; nothing
published.** Workflow: `.github/workflows/app.yml`.

## Jobs

| Job | When | What | AWS |
|---|---|---|---|
| `python` | PR and main | `ruff check`, `ruff format --check`, pytest including the PostgreSQL integration tests (`FINSIGHT_INTEGRATION=1`, `postgres:17-alpine` service pinned by digest) | None |
| `frontend` | PR and main | `npm ci`, Prettier check, Vitest, production build | None |
| `checkov` | PR and main | Checkov (the repository's digest-pinned image) on `infra/terraform`, the Dockerfiles, and the rendered FinSight and ClusterIssuer manifests | None |
| `images` | PR and main | Matrix over **api**, **etl** and **frontend**: build the production target, then Trivy 0.75.0 (pinned by digest) | None |
| `publish` | main only, after all four jobs pass | Environment `dev-images`, OIDC image role (`vars.AWS_ROLE_ARN`). Loads the **scanned** image artifacts, pushes `finsight-dev/<image>:<commit SHA>` (never `latest`) and records the digests | Image role only |
| `gitops` | after `publish` | Writes `gitops/apps/finsight/image-tags.yaml` (tag and digest), pushes branch `gitops/images-<sha>` and opens a pull request. It never pushes to `main` | None |

**Trivy policy**
- Any HIGH or CRITICAL finding **with a fix** fails the image job (`--ignore-unfixed --exit-code 1`).
- Findings with no fix cannot be cured by rebuilding. They are listed in each job summary, not
  hidden.
- Local result on 15 October 2026: api and etl have 0 fixable and 44 unfixed (Debian 13.7 base);
  frontend has 0.

**Deployment.** Merging the GitOps pull request changes only `image-tags.yaml`. Argo CD (G05/G08)
then renders the chart with `repository@digest` and rolls the change out. Nothing in the pipeline
calls `kubectl`. The registry URLs contain the account ID, so they are supplied as Argo CD
Application parameters, not committed.

**No loop.** `image-tags.yaml` is not in the workflow's path filters, so merging an image pull
request does not start another build and publish. Pull requests opened with `GITHUB_TOKEN` do not
trigger workflows either.

**Immutable tags.** The ECR repositories are `IMMUTABLE`. A re-run for the same commit reuses the
existing tag and digest instead of pushing again.

## Prerequisites (owner approval; none configured yet)

1. **Environment `dev-images`.** The image role trusts only this environment's OIDC subject.
   - Deployment branches: `main` only.
   - Administrator bypass off. Required reviewer optional.
   - Variable `AWS_ROLE_ARN`: the image role ARN, from the foundation output
     `github_role_arns["images"]`.
   - No secrets.
2. **Repository variable `IMAGE_PUBLISHING_ENABLED=true`.** Set it only after step 1. Until then
   `publish` and `gitops` are skipped. This also stops GitHub auto-creating an unprotected
   `dev-images` environment on the first run on `main`.
3. **Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests".**
   This is currently **off**: `can_approve_pull_request_reviews=false`. Without it, `gitops` pushes
   its branch and then fails with an explicit error; the pull request can be opened by hand from
   that branch.
4. **Argo CD** with a FinSight Application that uses `values.yaml` and `image-tags.yaml`, plus the
   repository parameters (G05/G08).
5. **The `finsight-database` Secret** (`PG*` variables) in namespace `finsight`, created with the
   database.

## Local validation (15 October 2026)

- **actionlint 1.7.12 (with shellcheck):** clean for all three workflows.
- **Checkov GitHub Actions checks:** 319 passed, 0 failed, 1 documented skip.
- **Python job reproduced on Linux** with the pinned PostgreSQL service: ruff clean, 37 passed,
  integration tests included.
- **Frontend job reproduced on Linux from a true LF checkout:**
  - Prettier, Vitest (6/6) and the build all pass.
  - Prettier only fails on this Windows worktree, because `core.autocrlf` gives it CRLF copies;
    no configuration change was needed.
- **Checkov steps exactly as in the workflow:**
  - Terraform, Dockerfiles and Kubernetes all exit 0.
  - Kubernetes: 181 passed, 0 failed, 3 documented skips.
  - Skips are annotations on the resources: CKV_K8S_35 (libpq environment variables) and
    CKV2_K8S_6 (no NetworkPolicy enforcement yet).
- **Images:** the three images build, and the Trivy gate passes for all three.
- **GitOps step reproduced:** it writes valid `image-tags.yaml`, the chart renders
  `repository@digest`, and a malformed digest is refused.
- **Not testable locally:**
  - real GitHub runs
  - OIDC
  - the ECR push
  - pull-request creation
  - Argo CD rollout

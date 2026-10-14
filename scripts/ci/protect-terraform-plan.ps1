#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Root,
    [string]$PlanFile = "platform.tfplan",
    [Parameter(Mandatory)] [string]$OutDir,
    [string]$AllowDestroy = "false",
    # Validate the encryption configuration only, before any AWS session or plan exists.
    [switch]$CheckOnly,
    [string]$TerraformPath = "terraform",
    [string]$AgePath = "age",
    [string]$ConfigPath = "",
    # Offline testing only: use these instead of `terraform show`.
    [string]$PlanJsonPath = "",
    [string]$ReviewTextPath = ""
)
# Plan job (issue #11). Fails closed unless both age recipients are configured and the decryption
# key is not visible to this job. Then, for a saved plan: re-checks the safety gates, encrypts the
# binary plan for the protected apply job only and a human-readable copy (with an identity header)
# for the reviewer only, and publishes the plan's identity as step outputs: commit, workflow run,
# backend and configuration digests, lock file, Terraform version and SHA-256 digests of the plan,
# its ciphertexts and its canonical changes. No plaintext plan leaves the runner.
$ErrorActionPreference = "Stop"
$recipientPattern = '^age1[0-9a-z]{58}$'
$ci = "$env:PLAN_ENCRYPTION_RECIPIENT".Trim()
$reviewer = "$env:PLAN_REVIEW_RECIPIENT".Trim()
if ($ci -notmatch $recipientPattern) { throw "PLAN_ENCRYPTION_RECIPIENT is missing or not an age X25519 recipient; refusing to plan without encryption." }
if ($reviewer -notmatch $recipientPattern) { throw "PLAN_REVIEW_RECIPIENT is missing or not an age X25519 recipient; refusing to plan without an encrypted review copy." }
if ($ci -eq $reviewer) { throw "The CI and reviewer recipients must be different keys." }
# The decryption key belongs only to the approved apply environment. If the plan job can see it
# (for example a repository-level secret), the separation is broken: refuse to continue.
if (-not [string]::IsNullOrEmpty($env:DECRYPTION_IDENTITY_VISIBLE)) { throw "PLAN_DECRYPTION_IDENTITY is visible to the plan job; it must exist only in dev-infrastructure-apply." }
if ($CheckOnly) { Write-Output "Plan encryption recipients are configured; the decryption key is not visible here."; return }

function Get-FileSha256([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$planPath = Join-Path $rootPath $PlanFile
if (-not (Test-Path -LiteralPath $planPath)) { throw "Saved plan not found." }
$backend = Join-Path $rootPath "backend.hcl"
if (-not (Test-Path -LiteralPath $backend)) { throw "backend.hcl not found." }
$stateKey = (Select-String -LiteralPath $backend -Pattern '^\s*key\s*=\s*"([^"]+)"').Matches.Groups[1].Value
if (-not $stateKey) { throw "No state key in backend.hcl." }
if (-not $ConfigPath) { $ConfigPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "infra/terraform/config/local.json" }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Private configuration not found." }

# Counts, flags and digests, using the same summariser as pull-request plans.
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$metaPath = Join-Path $OutDir "plan-metadata.json"
$summaryArgs = @{ Root = $Root; PlanFile = $PlanFile; MetadataPath = $metaPath; TerraformPath = $TerraformPath; Heading = "Terraform plan for approval"; NoOutputs = $true }
if ($PlanJsonPath) { $summaryArgs.PlanJsonPath = $PlanJsonPath }
& (Join-Path $PSScriptRoot "summarize-terraform-plan.ps1") @summaryArgs | Out-Null
$meta = Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json
Remove-Item -LiteralPath $metaPath

$allow = $AllowDestroy -eq "true"
if ($meta.human_only) { throw "The plan includes changes CI never applies ($($meta.human_only_reason)). A human must run that apply (docs/infrastructure/terraform-ci.md)." }
if ($meta.destructive -and -not $allow) { throw "The plan deletes, replaces or forgets resources (or has unrecognised actions). Re-run with allow_destroy only if that is intended." }
$hasChanges = ($meta.create + $meta.update + $meta.replace + $meta.delete + $meta.forget + $meta.import + $meta.unknown) -gt 0

$lock = Join-Path $rootPath ".terraform.lock.hcl"
$identity = [ordered]@{
    has_changes              = $hasChanges
    commit                   = $env:GITHUB_SHA
    run_id                   = $env:GITHUB_RUN_ID
    run_attempt              = $env:GITHUB_RUN_ATTEMPT
    state_key                = $stateKey
    # Bucket, key, Region and account of the state, and the full private configuration, by digest.
    backend_sha256           = Get-FileSha256 $backend
    config_sha256            = Get-FileSha256 $ConfigPath
    terraform_version        = $meta.terraform_version
    lock_file_sha256         = Get-FileSha256 $lock
    plan_sha256              = $meta.plan_sha256
    changes_sha256           = $meta.changes_sha256
    plan_ciphertext_sha256   = ""
    review_ciphertext_sha256 = ""
    ci_recipient             = $ci
    allow_destroy            = $allow
    destructive              = [bool]$meta.destructive
    create                   = $meta.create
    update                   = $meta.update
    replace                  = $meta.replace
    delete                   = $meta.delete
    forget                   = $meta.forget
}

$planCipher = Join-Path $OutDir "platform.tfplan.age"
$reviewCipher = Join-Path $OutDir "platform-plan-review.txt.age"
if ($hasChanges) {
    # The binary plan: decryptable only with the identity held by the protected apply environment.
    & $AgePath --encrypt --recipient $ci --output $planCipher $planPath
    if ($LASTEXITCODE -ne 0) { throw "Encrypting the saved plan failed." }
    # The readable review copy: decryptable only by the human reviewer, outside GitHub. Its header
    # carries the identity the reviewer compares with the pending run before approving.
    $tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
    $reviewPlain = Join-Path $tempRoot ("review-" + [guid]::NewGuid().ToString("N") + ".txt")
    try {
        $header = @(
            "FinSight Terraform plan review copy. Approve the apply job only if every value below",
            "matches the pending workflow run's summary.",
            "repository:      $env:GITHUB_REPOSITORY",
            "commit:          $($identity.commit)",
            "workflow run:    $($identity.run_id) attempt $($identity.run_attempt)",
            "state key:       $stateKey",
            "plan SHA-256:    $($identity.plan_sha256)",
            "changes SHA-256: $($identity.changes_sha256)",
            ("changes:         {0} create, {1} update, {2} replace, {3} delete, {4} forget" -f $meta.create, $meta.update, $meta.replace, $meta.delete, $meta.forget),
            "allow_destroy:   $($allow.ToString().ToLower())",
            ("-" * 78), "")
        Set-Content -LiteralPath $reviewPlain -Value $header -Encoding utf8NoBOM
        if ($ReviewTextPath) { Get-Content -Raw -LiteralPath $ReviewTextPath | Add-Content -LiteralPath $reviewPlain }
        else {
            & $TerraformPath "-chdir=$rootPath" show -no-color $PlanFile >> $reviewPlain
            if ($LASTEXITCODE -ne 0) { throw "terraform show failed for the review copy." }
        }
        & $AgePath --encrypt --recipient $reviewer --output $reviewCipher $reviewPlain
        if ($LASTEXITCODE -ne 0) { throw "Encrypting the review copy failed." }
    }
    finally { Remove-Item -LiteralPath $reviewPlain -Force -ErrorAction SilentlyContinue }
    $identity.plan_ciphertext_sha256 = Get-FileSha256 $planCipher
    $identity.review_ciphertext_sha256 = Get-FileSha256 $reviewCipher
}

if ($env:GITHUB_OUTPUT) { foreach ($k in $identity.Keys) { "$k=$(([string]$identity[$k]).ToLower())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT } }
if ($env:GITHUB_STEP_SUMMARY -and $hasChanges) {
    @("", "### Before approving the apply job",
      "", "Compare these with the header of the decrypted review copy (docs/infrastructure/terraform-ci.md, 'Reviewing a plan'):",
      "", "| Field | Value |", "|---|---|",
      "| Workflow run | $($identity.run_id) attempt $($identity.run_attempt) |",
      "| Commit | ``$($identity.commit)`` |",
      "| State key | ``$stateKey`` |",
      "| Plan SHA-256 | ``$($identity.plan_sha256)`` |",
      "| Changes SHA-256 | ``$($identity.changes_sha256)`` |",
      "| Encrypted review copy SHA-256 | ``$($identity.review_ciphertext_sha256)`` |",
      "| Encrypted plan SHA-256 | ``$($identity.plan_ciphertext_sha256)`` |",
      "| allow_destroy | $($allow.ToString().ToLower()) |") | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY
}
Write-Output ("Plan protected: has_changes={0}, destructive={1}, allow_destroy={2}." -f $hasChanges, [bool]$meta.destructive, $allow)

#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Root,
    [Parameter(Mandatory)] [string]$EncryptedPlan,
    [string]$PlanFile = "approved.tfplan",
    [string]$TerraformPath = "terraform",
    [string]$AgePath = "age",
    [string]$AgeKeygenPath = "age-keygen",
    [string]$ConfigPath = "",
    # Offline testing only: use this instead of `terraform show -json` and `terraform version`.
    [string]$PlanJsonPath = "",
    [string]$TerraformVersion = ""
)
# Apply job (issue #11), after the reviewer approved the protected environment. Verifies that the
# encrypted artifact is exactly the plan the plan job produced for this commit, workflow run, state
# backend and configuration, decrypts it with the apply environment's identity, and re-checks the
# plan's digests and safety gates. Any mismatch or missing value fails closed, and a decrypted plan
# that fails a check is deleted. The apply step then runs `terraform apply` on this exact file;
# nothing is re-planned. The identity is passed to age on standard input, never as an argument or
# a file.
$ErrorActionPreference = "Stop"
function Get-FileSha256([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }
function Expect([string]$name) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Missing $name from the plan job; refusing to apply." }
    $value.Trim()
}
function Assert-Equal([string]$what, [string]$actual, [string]$expected) {
    if ($actual -ne $expected) { throw "$what does not match the reviewed plan; refusing to apply." }
}

# 1. Same commit, workflow run, state backend, configuration and dependency lock as the reviewed plan.
Assert-Equal "Commit" $env:GITHUB_SHA (Expect "EXPECTED_COMMIT")
Assert-Equal "Checked-out commit" (git rev-parse HEAD) (Expect "EXPECTED_COMMIT")
Assert-Equal "Workflow run" $env:GITHUB_RUN_ID (Expect "EXPECTED_RUN_ID")
if ([int]$env:GITHUB_RUN_ATTEMPT -lt [int](Expect "EXPECTED_RUN_ATTEMPT")) { throw "The plan is from a later run attempt; refusing to apply." }
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$backend = Join-Path $rootPath "backend.hcl"
if (-not (Test-Path -LiteralPath $backend)) { throw "backend.hcl not found; refusing to apply." }
Assert-Equal "State key" (Select-String -LiteralPath $backend -Pattern '^\s*key\s*=\s*"([^"]+)"').Matches.Groups[1].Value (Expect "EXPECTED_STATE_KEY")
Assert-Equal "State backend" (Get-FileSha256 $backend) (Expect "EXPECTED_BACKEND_SHA256")
if (-not $ConfigPath) { $ConfigPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "infra/terraform/config/local.json" }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Private configuration not found; refusing to apply." }
Assert-Equal "Private configuration" (Get-FileSha256 $ConfigPath) (Expect "EXPECTED_CONFIG_SHA256")
Assert-Equal "Dependency lock file" (Get-FileSha256 (Join-Path $rootPath ".terraform.lock.hcl")) (Expect "EXPECTED_LOCK_SHA256")
$version = if ($TerraformVersion) { $TerraformVersion } else { (& $TerraformPath version -json | ConvertFrom-Json).terraform_version }
Assert-Equal "Terraform version" $version (Expect "EXPECTED_TF_VERSION")

# 2. The artifact is exactly the ciphertext the plan job produced.
if (-not (Test-Path -LiteralPath $EncryptedPlan)) { throw "Encrypted plan artifact not found; refusing to apply." }
Assert-Equal "Encrypted plan digest" (Get-FileSha256 $EncryptedPlan) (Expect "EXPECTED_PLAN_CIPHERTEXT_SHA256")

# 3. Decrypt with the apply environment's identity, which must match the recipient used.
if ("$env:PLAN_DECRYPTION_IDENTITY".Trim() -notmatch '^AGE-SECRET-KEY-1[0-9A-Z]{58}$') { throw "PLAN_DECRYPTION_IDENTITY is missing or malformed; refusing to apply." }
$recipient = "$("$env:PLAN_DECRYPTION_IDENTITY".Trim() | & $AgeKeygenPath -y)".Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not derive the recipient from PLAN_DECRYPTION_IDENTITY." }
Assert-Equal "Encryption recipient" $recipient (Expect "EXPECTED_CI_RECIPIENT")
$planPath = Join-Path $rootPath $PlanFile
"$env:PLAN_DECRYPTION_IDENTITY".Trim() | & $AgePath --decrypt --identity - --output $planPath $EncryptedPlan
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
    throw "Decrypting the plan failed (wrong key or corrupted artifact); refusing to apply."
}

# 4. The plaintext is the reviewed plan, and it still passes the safety gates. A plan that fails
#    any check is deleted at once, so no later step can apply it.
try {
    Assert-Equal "Plan digest" (Get-FileSha256 $planPath) (Expect "EXPECTED_PLAN_SHA256")
    $tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
    $metaPath = Join-Path $tempRoot ("plan-meta-" + [guid]::NewGuid().ToString("N") + ".json")
    $summaryArgs = @{ Root = $Root; PlanFile = $PlanFile; MetadataPath = $metaPath; TerraformPath = $TerraformPath; Heading = "Approved plan to apply"; NoOutputs = $true }
    if ($PlanJsonPath) { $summaryArgs.PlanJsonPath = $PlanJsonPath }
    & (Join-Path $PSScriptRoot "summarize-terraform-plan.ps1") @summaryArgs | Out-Null
    $meta = Get-Content -Raw -LiteralPath $metaPath | ConvertFrom-Json
    Remove-Item -LiteralPath $metaPath
    Assert-Equal "Changes digest" $meta.changes_sha256 (Expect "EXPECTED_CHANGES_SHA256")
    if ($meta.human_only) { throw "The plan includes changes CI never applies ($($meta.human_only_reason)); refusing to apply." }
    if ($meta.destructive -and (Expect "EXPECTED_ALLOW_DESTROY") -ne "true") { throw "The plan deletes, replaces or forgets resources without allow_destroy; refusing to apply." }
}
catch {
    Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue
    throw
}
Write-Output "Verified: commit, run, state backend, configuration, lock file, Terraform version, artifact, recipient, plan and changes digests, and safety gates match the reviewed plan."

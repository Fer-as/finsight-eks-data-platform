#Requires -Version 7
[CmdletBinding()]
param()
# CI only. Writes the ignored central config from the TERRAFORM_CONFIG_JSON environment secret,
# masks every private value before anything can print it, and generates backend.hcl files.
# No AWS calls. Locally, use config/local.json and new-terraform-backend-config.ps1 instead.
$ErrorActionPreference = "Stop"
if ($env:GITHUB_ACTIONS -ne "true") { throw "CI only: locally, create config/local.json from its example." }
if (-not $env:TERRAFORM_CONFIG_JSON) { throw "Environment secret TERRAFORM_CONFIG_JSON is not available to this job." }
try { $config = $env:TERRAFORM_CONFIG_JSON | ConvertFrom-Json }
catch { throw "TERRAFORM_CONFIG_JSON is not valid JSON." }

# The repository is public, so run logs and summaries are public: mask identifiers and the
# operator's API CIDRs. Masking applies to later log lines only, so do this first.
$private = @($config.account_id, $config.state_bucket, $config.data_bucket, $config.access_log_bucket, $config.dns.zone_id)
$private += @($config.eks.admin_role_arns) + @($config.eks.public_access_cidrs | ForEach-Object { $_; ($_ -split "/")[0] })
if ($config.github.subject_prefix) { $private += @($config.github.subject_prefix) + [regex]::Matches($config.github.subject_prefix, "\d{5,}").Value }
foreach ($value in $private | Where-Object { $_ } | Sort-Object -Unique) { Write-Output "::add-mask::$value" }

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$destination = Join-Path $repo "infra/terraform/config/local.json"
if (Test-Path -LiteralPath $destination) { throw "Refusing to overwrite an existing config/local.json." }
Set-Content -LiteralPath $destination -Value $env:TERRAFORM_CONFIG_JSON -NoNewline -Encoding utf8NoBOM
& (Join-Path $repo "scripts/new-terraform-backend-config.ps1")

# The platform root refuses to plan until the regional compatibility gate is explicitly passed
# (modules/eks). Report that as a skipped plan rather than a failed check.
$enabled = [bool]$config.eks.compatibility_verified
if ($env:GITHUB_OUTPUT) { "plan_enabled=$($enabled.ToString().ToLower())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT }
if (-not $enabled) {
    $reason = "eks.compatibility_verified is false; the platform root cannot be planned until the compatibility gate is passed (docs/infrastructure/compatibility.md)."
    Write-Output "::notice title=Platform plan skipped::$reason"
    if ($env:GITHUB_STEP_SUMMARY) { "## Terraform plan: skipped`n`n$reason" | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
}

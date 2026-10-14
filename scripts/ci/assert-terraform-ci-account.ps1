#Requires -Version 7
[CmdletBinding()]
param()
# CI only. Confirms the OIDC session belongs to the configured account before Terraform runs.
# Prints no identifiers (the provider's allowed_account_ids is a second, independent check).
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$config = Get-Content -Raw (Join-Path $repo "infra/terraform/config/local.json") | ConvertFrom-Json
$caller = aws sts get-caller-identity --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $caller) { throw "Could not read the CI session identity." }
if ($caller.Account -ne $config.account_id) { throw "The CI session is not in the configured account." }
if ($caller.Arn -notmatch ":assumed-role/[^/]+-github-infra-(plan|apply)/") { throw "The CI session is not a FinSight Terraform role." }
Write-Output "CI session is the expected Terraform role in the configured account."

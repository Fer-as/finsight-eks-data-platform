#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Root,
    [Parameter(Mandatory)] [string]$PlanFile,
    [string]$Commit = $env:GITHUB_SHA,
    [string]$MetadataPath = "",
    [string]$TerraformPath = "terraform",
    # Offline testing only: read `terraform show -json` output from a file instead of running it.
    [string]$PlanJsonPath = ""
)
# Summarises a saved plan for review without printing attribute values: counts, resource addresses
# and actions, safety flags, and digests that a later apply job can compare (issue #11):
# - plan_sha256: the exact binary plan file
# - changes_sha256: canonical resource and output changes, values included, so an independent
#   re-plan of the same commit and state can be proven identical without sharing the binary plan
# Writes GitHub step summary and outputs when available; otherwise prints the summary.
$ErrorActionPreference = "Stop"
$planPath = Join-Path $Root $PlanFile
if (-not (Test-Path -LiteralPath $planPath)) { throw "Saved plan not found: $planPath" }
# .NET file APIs resolve relative paths against the process directory, not the PowerShell location.
$planPath = (Resolve-Path -LiteralPath $planPath).Path
if ($PlanJsonPath) { $json = Get-Content -Raw -LiteralPath $PlanJsonPath }
else {
    $json = & $TerraformPath "-chdir=$Root" show -json -no-color $PlanFile
    if ($LASTEXITCODE -ne 0) { throw "terraform show failed for the saved plan." }
}
$plan = ($json -join "`n") | ConvertFrom-Json -Depth 100

function Get-Sha256([byte[]]$bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLower() }
# Account IDs can appear in addresses (for example access entries keyed by role ARN).
function Hide([string]$text) { $text -replace '\b\d{12}\b', '<account>' }

$changes = @($plan.resource_changes | Where-Object { $_.mode -eq "managed" -and ((@($_.change.actions) -join ",") -notin @("no-op", "read")) })
$rows = foreach ($c in $changes) {
    $actions = @($c.change.actions)
    $kind = if ($actions -contains "delete" -and $actions -contains "create") { "replace" } elseif ($actions -contains "delete") { "delete" } elseif ($actions -contains "create") { "create" } else { "update" }
    [pscustomobject]@{ Address = (Hide $c.address); Type = $c.type; Kind = $kind }
}
$count = @{ create = 0; update = 0; replace = 0; delete = 0 }
foreach ($row in $rows) { $count[$row.Kind]++ }
$destructive = ($count.replace + $count.delete) -gt 0
# A new VPC's default security group must be tagged by a human: CI cannot apply such plans.
$createsVpc = [bool]($rows | Where-Object { $_.Type -eq "aws_vpc" -and $_.Kind -in @("create", "replace") })

$canonical = [ordered]@{ resource_changes = $plan.resource_changes; output_changes = $plan.output_changes } | ConvertTo-Json -Depth 100 -Compress
$lockPath = Join-Path (Resolve-Path -LiteralPath $Root).Path ".terraform.lock.hcl"
$meta = [ordered]@{
    root               = $Root -replace '\\', '/'
    commit             = $Commit
    terraform_version  = $plan.terraform_version
    plan_sha256        = Get-Sha256 ([IO.File]::ReadAllBytes($planPath))
    changes_sha256     = Get-Sha256 ([Text.Encoding]::UTF8.GetBytes($canonical))
    lock_file_sha256   = if (Test-Path -LiteralPath $lockPath) { Get-Sha256 ([IO.File]::ReadAllBytes($lockPath)) } else { $null }
    create             = $count.create
    update             = $count.update
    replace            = $count.replace
    delete             = $count.delete
    destructive        = $destructive
    creates_vpc        = $createsVpc
}

$md = [Collections.Generic.List[string]]::new()
$md.Add("## Terraform plan: ``$($meta.root)``")
$md.Add("")
$md.Add("| Create | Update | Replace | Delete |")
$md.Add("|---:|---:|---:|---:|")
$md.Add("| $($count.create) | $($count.update) | $($count.replace) | $($count.delete) |")
$md.Add("")
if ($destructive) { $md.Add("> **Destructive:** this plan deletes or replaces resources. It must never be applied automatically; an apply needs explicit destroy approval.") }
if ($createsVpc) { $md.Add("> **Human-run apply required:** this plan creates a VPC. CI cannot tag the new default security group (docs/infrastructure/terraform-ci.md).") }
if (-not $rows) { $md.Add("No changes.") }
$md.Add("")
$md.Add("Commit ``$($meta.commit)`` · Terraform $($meta.terraform_version) · plan SHA-256 ``$($meta.plan_sha256)`` · changes SHA-256 ``$($meta.changes_sha256)``")
$md.Add("")
$md.Add("Attribute values are deliberately not shown: run logs and summaries of this public repository are public.")
if ($rows) {
    $md.Add("")
    $md.Add("<details><summary>Resource changes ($(@($rows).Count))</summary>")
    $md.Add("")
    $md.Add("| Action | Address |")
    $md.Add("|---|---|")
    foreach ($row in $rows | Sort-Object Kind, Address) { $md.Add("| $($row.Kind) | ``$($row.Address)`` |") }
    $md.Add("")
    $md.Add("</details>")
}

if ($env:GITHUB_STEP_SUMMARY) { $md | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY } else { $md | Write-Output }
if ($env:GITHUB_OUTPUT) {
    foreach ($k in "plan_sha256", "changes_sha256", "create", "update", "replace", "delete", "destructive", "creates_vpc") {
        "$k=$(([string]$meta[$k]).ToLower())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }
}
if ($MetadataPath) { $meta | ConvertTo-Json | Set-Content -LiteralPath $MetadataPath -Encoding utf8NoBOM }
if ($destructive) { Write-Output "::warning title=Destructive plan::$($count.replace) replacement(s) and $($count.delete) deletion(s); never applied automatically." }
if ($createsVpc) { Write-Output "::warning title=Human-run apply required::The plan creates a VPC; CI must not apply it." }
Write-Output ("Plan: {0} to create, {1} to update, {2} to replace, {3} to delete." -f $count.create, $count.update, $count.replace, $count.delete)

#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Root,
    [Parameter(Mandatory)] [string]$PlanFile,
    [string]$Commit = $env:GITHUB_SHA,
    [string]$MetadataPath = "",
    [string]$TerraformPath = "terraform",
    # Offline testing only: read `terraform show -json` output from a file instead of running it.
    [string]$PlanJsonPath = "",
    [string]$Heading = "Terraform plan",
    # Callers that publish their own step outputs (the plan protection scripts) suppress these.
    [switch]$NoOutputs
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

# Every managed change is classified. Anything not recognised counts as destructive (fail closed).
$changes = @($plan.resource_changes | Where-Object { $_.mode -eq "managed" -and (((@($_.change.actions) -join ",") -notin @("no-op", "read")) -or $_.change.importing) })
$rows = foreach ($c in $changes) {
    $key = @($c.change.actions) -join ","
    $kind = switch ($key) {
        "create" { "create" }
        "update" { "update" }
        "delete" { "delete" }
        { $_ -in @("delete,create", "create,delete") } { "replace" }
        # Removed from state without being destroyed: management of a real resource is lost.
        "forget" { "forget" }
        { $_ -in @("no-op", "read") } { "import" }
        default { "unknown" }
    }
    if ($c.change.importing -and $kind -ne "import") { $kind = "import+$kind" }
    [pscustomobject]@{ Address = (Hide $c.address); Type = $c.type; Kind = $kind }
}
$count = [ordered]@{ create = 0; update = 0; replace = 0; delete = 0; forget = 0; import = 0; unknown = 0 }
foreach ($row in $rows) { $base = ($row.Kind -split "\+")[-1]; if ($row.Kind -like "import*") { $count.import++ }; if ($base -ne "import") { $count[$base]++ } }
$destructive = ($count.replace + $count.delete + $count.forget + $count.unknown) -gt 0
# Human-run only, never applied by CI even with allow_destroy:
# - any creation, replacement, deletion or removal of a VPC (its default security group must be
#   tagged by a human; teardown and rebuild of the network are owner operations)
# - the same for the EKS cluster, the expensive core of the initial deployment
# - any import, which brings existing infrastructure under this state
$humanOnlyTypes = @("aws_vpc", "aws_eks_cluster")
$humanOnly = @($rows | Where-Object { ($_.Kind -like "import*") -or (($_.Type -in $humanOnlyTypes) -and ($_.Kind -ne "update")) })
$humanOnlyReason = ($humanOnly | ForEach-Object { "$($_.Kind) $($_.Type)" } | Sort-Object -Unique) -join ", "
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
    forget             = $count.forget
    import             = $count.import
    unknown            = $count.unknown
    destructive        = $destructive
    human_only         = $humanOnly.Count -gt 0
    human_only_reason  = $humanOnlyReason
}

$md = [Collections.Generic.List[string]]::new()
$md.Add("## $($Heading): ``$($meta.root)``")
$md.Add("")
$md.Add("| Create | Update | Replace | Delete | Forget | Import | Unrecognised |")
$md.Add("|---:|---:|---:|---:|---:|---:|---:|")
$md.Add("| $($count.create) | $($count.update) | $($count.replace) | $($count.delete) | $($count.forget) | $($count.import) | $($count.unknown) |")
$md.Add("")
if ($destructive) { $md.Add("> **Destructive:** this plan deletes, replaces or forgets resources (or has unrecognised actions). It must never be applied automatically; an apply needs explicit destroy approval.") }
if ($humanOnly) { $md.Add("> **Human-run apply required:** $humanOnlyReason. CI never applies VPC or EKS cluster lifecycle changes or imports (docs/infrastructure/terraform-ci.md).") }
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
if ($env:GITHUB_OUTPUT -and -not $NoOutputs) {
    foreach ($k in "plan_sha256", "changes_sha256", "create", "update", "replace", "delete", "forget", "import", "unknown", "destructive", "human_only") {
        "$k=$(([string]$meta[$k]).ToLower())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
    }
}
if ($MetadataPath) { $meta | ConvertTo-Json | Set-Content -LiteralPath $MetadataPath -Encoding utf8NoBOM }
if ($destructive) { Write-Output "::warning title=Destructive plan::$($count.replace) replacement(s) and $($count.delete) deletion(s); never applied automatically." }
if ($humanOnly) { Write-Output "::warning title=Human-run apply required::$humanOnlyReason; CI must not apply it." }
Write-Output ("Plan: {0} to create, {1} to update, {2} to replace, {3} to delete, {4} to forget, {5} to import, {6} unrecognised." -f $count.create, $count.update, $count.replace, $count.delete, $count.forget, $count.import, $count.unknown)

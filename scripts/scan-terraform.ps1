[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$infra = Join-Path $repo "infra/terraform"
$image = (Get-Content -Raw (Join-Path $repo "infra/checkov-image.txt")).Trim()
$docker = Get-Command docker -ErrorAction Stop
$cache = Join-Path $repo ".cache/checkov"
$dockerConfig = Join-Path $cache "docker-config"
New-Item -ItemType Directory -Force $dockerConfig | Out-Null
# Empty dedicated config: do not read registry credentials from the user's Docker config.
"{}" | Set-Content (Join-Path $dockerConfig "config.json") -Encoding ascii
$reportPath = Join-Path $cache "latest.json"
# No network, credentials, Docker socket mount, or writable source mount in the scanner.
$report = & $docker.Source --config $dockerConfig run --rm --pull=never --network=none --mount "type=bind,source=$infra,target=/tf,readonly" $image -d /tf --framework terraform --skip-download --download-external-modules false --output json
$scanExit = $LASTEXITCODE
if ($scanExit -notin @(0, 1)) { throw "Checkov container failed (exit $scanExit). The pinned image must be cached; see infra/terraform/README.md." }
if (-not $report) { throw "Checkov returned no JSON report." }
$report | Set-Content -LiteralPath $reportPath -Encoding utf8
$scan = ($report -join [Environment]::NewLine) | ConvertFrom-Json
Write-Host ("Checkov {0}: {1} passed, {2} failed, {3} skipped, {4} parsing errors." -f $scan.summary.checkov_version, $scan.summary.passed, $scan.summary.failed, $scan.summary.skipped, $scan.summary.parsing_errors)
Write-Host "Full local report: $reportPath"
foreach ($finding in $scan.results.failed_checks) {
    Write-Host ("FAILED {0}: {1}" -f $finding.check_id, $finding.resource)
}
if ($scan.summary.skipped -gt 0) {
    Write-Host "Resource-scoped exceptions remain; see docs/evidence/day2-terraform-validation.md."
}
if ($scanExit -ne 0 -or $scan.summary.failed -gt 0 -or $scan.summary.parsing_errors -gt 0) {
    throw "Checkov reported failures or parsing errors."
}

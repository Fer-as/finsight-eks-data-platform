[CmdletBinding()]
param(
    [string]$TerraformPath = "",
    [switch]$Format
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $TerraformPath) {
    $cached = Join-Path $repo ".cache\terraform\terraform.exe"
    $command = Get-Command terraform -ErrorAction SilentlyContinue
    if ($command) { $TerraformPath = $command.Source }
    elseif (Test-Path -LiteralPath $cached) { $TerraformPath = $cached }
    else { throw "Terraform 1.16.2 is required. Install it or pass -TerraformPath." }
}
$TerraformPath = (Resolve-Path -LiteralPath $TerraformPath).Path
$infra = Join-Path $repo "infra\terraform"
$roots = @("bootstrap", "environments/dev/foundation", "environments/dev/platform")
# No plan, provider refresh, backend initialization, AWS CLI, or credential inspection.
$fmtArgs = @("-chdir=$infra", "fmt", "-recursive")
if (-not $Format) { $fmtArgs += "-check" }
& $TerraformPath @fmtArgs
if ($LASTEXITCODE -ne 0) { throw "Terraform formatting failed." }
foreach ($root in $roots) {
    $path = Join-Path $infra $root
    Write-Host "Validating $root (backend disabled)"
    & $TerraformPath "-chdir=$path" init -backend=false -input=false -lockfile=readonly
    if ($LASTEXITCODE -ne 0) { throw "Terraform initialization failed: $root" }
    & $TerraformPath "-chdir=$path" validate -no-color
    if ($LASTEXITCODE -ne 0) { throw "Terraform validation failed: $root" }
}
$configModule = Join-Path $infra "modules/config"
& $TerraformPath "-chdir=$configModule" init -backend=false -input=false
if ($LASTEXITCODE -ne 0) { throw "Configuration test initialization failed." }
& $TerraformPath "-chdir=$configModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Provider-free configuration tests failed." }
$dnsModule = Join-Path $infra "modules/dns-policies"
& $TerraformPath "-chdir=$dnsModule" init -backend=false -input=false
if ($LASTEXITCODE -ne 0) { throw "DNS policy test initialization failed." }
& $TerraformPath "-chdir=$dnsModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Provider-free DNS policy tests failed." }
$networkModule = Join-Path $infra "modules/network"
& $TerraformPath "-chdir=$networkModule" init -backend=false -input=false -lockfile=readonly
if ($LASTEXITCODE -ne 0) { throw "Mock network test initialization failed." }
& $TerraformPath "-chdir=$networkModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Mock network tests failed." }
$eksModule = Join-Path $infra "modules/eks"
& $TerraformPath "-chdir=$eksModule" init -backend=false -input=false -lockfile=readonly
if ($LASTEXITCODE -ne 0) { throw "Mock EKS test initialization failed." }
& $TerraformPath "-chdir=$eksModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Mock EKS tests failed." }
& (Join-Path $PSScriptRoot "scan-terraform.ps1")
Write-Host "All three Terraform roots passed fmt/init/validate. No AWS operations were performed."

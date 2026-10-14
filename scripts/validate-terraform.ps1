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
$infra = Join-Path $repo "infra/terraform"
$roots = @("bootstrap", "environments/dev/foundation", "environments/dev/platform")
# No plan, provider refresh, backend initialization, AWS CLI, or credential inspection.
$fmtArgs = @("-chdir=$infra", "fmt", "-recursive")
if (-not $Format) { $fmtArgs += "-check" }
& $TerraformPath @fmtArgs
if ($LASTEXITCODE -ne 0) { throw "Terraform formatting failed." }
# -backend=false alone can still load an already configured S3 backend. Isolate local
# validation metadata so the operator's deployed backend caches are never consulted.
$originalDataDir = $env:TF_DATA_DIR
try {
    foreach ($root in $roots) {
        $path = Join-Path $infra $root
        $env:TF_DATA_DIR = Join-Path $repo ".cache/terraform-validation/$root"
        Write-Host "Validating $root (isolated metadata; backend disabled)"
        & $TerraformPath "-chdir=$path" init -backend=false -input=false -lockfile=readonly
        if ($LASTEXITCODE -ne 0) { throw "Terraform initialization failed: $root" }
        & $TerraformPath "-chdir=$path" validate -no-color
        if ($LASTEXITCODE -ne 0) { throw "Terraform validation failed: $root" }
    }
}
finally {
    $env:TF_DATA_DIR = $originalDataDir
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
$lbcModule = Join-Path $infra "modules/load-balancer-controller-policy"
& $TerraformPath "-chdir=$lbcModule" init -backend=false -input=false
if ($LASTEXITCODE -ne 0) { throw "Load balancer controller policy test initialization failed." }
& $TerraformPath "-chdir=$lbcModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Provider-free load balancer controller policy tests failed." }
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
$podRoleModule = Join-Path $infra "modules/pod-role"
& $TerraformPath "-chdir=$podRoleModule" init -backend=false -input=false -lockfile=readonly
if ($LASTEXITCODE -ne 0) { throw "Mock pod-role test initialization failed." }
& $TerraformPath "-chdir=$podRoleModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Mock pod-role tests failed." }
$githubModule = Join-Path $infra "modules/github-oidc"
& $TerraformPath "-chdir=$githubModule" init -backend=false -input=false -lockfile=readonly
if ($LASTEXITCODE -ne 0) { throw "Mock GitHub OIDC test initialization failed." }
& $TerraformPath "-chdir=$githubModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Mock GitHub OIDC tests failed." }
$ciPolicyModule = Join-Path $infra "modules/terraform-ci-policies"
& $TerraformPath "-chdir=$ciPolicyModule" init -backend=false -input=false
if ($LASTEXITCODE -ne 0) { throw "CI policy test initialization failed." }
& $TerraformPath "-chdir=$ciPolicyModule" test -no-color
if ($LASTEXITCODE -ne 0) { throw "Provider-free CI policy tests failed." }
& (Join-Path $PSScriptRoot "scan-terraform.ps1")
Write-Host "All three Terraform roots passed fmt/init/validate. No AWS operations were performed."

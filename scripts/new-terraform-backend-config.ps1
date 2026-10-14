[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$infra = Join-Path $repo "infra/terraform"
$defaults = Get-Content -Raw (Join-Path $infra "config/defaults.json") | ConvertFrom-Json
$localPath = Join-Path $infra "config/local.json"
if (-not (Test-Path -LiteralPath $localPath)) { throw "Create ignored config/local.json from its example first." }
$overrides = Get-Content -Raw $localPath | ConvertFrom-Json
$config = @{}
foreach ($property in $defaults.PSObject.Properties) { $config[$property.Name] = $property.Value }
foreach ($property in $overrides.PSObject.Properties) { $config[$property.Name] = $property.Value }
if ($config.account_id -notmatch '^[0-9]{12}$' -or $config.account_id -eq "000000000000") { throw "Set the intended account ID." }
if ($config.state_bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw "Set a valid unique state bucket name." }
if ($config.region -ne "eu-west-2" -or $config.environment -ne "dev") { throw "This generator currently targets the approved London dev roots." }
$roots = @{
    "bootstrap" = "bootstrap/terraform.tfstate"
    "environments/dev/foundation" = "dev/foundation/terraform.tfstate"
    "environments/dev/platform" = "dev/platform/terraform.tfstate"
}
foreach ($root in $roots.Keys) {
    $destination = Join-Path (Join-Path $infra $root) "backend.hcl"
    if (Test-Path -LiteralPath $destination) { throw "Refusing to overwrite $destination. Review/remove that generated file explicitly first." }
}
foreach ($root in $roots.Keys) {
    $lines = @(
        ('bucket = "{0}"' -f $config.state_bucket),
        ('key = "{0}"' -f $roots[$root]),
        ('region = "{0}"' -f $config.region),
        'encrypt = true',
        'use_lockfile = true',
        ('allowed_account_ids = ["{0}"]' -f $config.account_id)
    )
    $destination = Join-Path (Join-Path $infra $root) "backend.hcl"
    $lines | Set-Content -LiteralPath $destination -Encoding ascii
    Write-Host "Created ignored $destination"
}
Write-Host "Local files only. No backend or AWS connection was made."

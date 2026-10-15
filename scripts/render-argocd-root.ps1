# Renders the root Application (gitops/argocd/root-application.yaml) with this account's values into
# an ignored file for `kubectl apply`. Values come from Terraform outputs and config; see
# docs/infrastructure/argocd.md. Nothing is contacted and no value is printed.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$VpcId,
    [Parameter(Mandatory = $true)][string]$HostedZoneId,
    [Parameter(Mandatory = $true)][string]$PublicIngressSecurityGroupId,
    [Parameter(Mandatory = $true)][string]$ApiRepositoryUrl,
    [Parameter(Mandatory = $true)][string]$FrontendRepositoryUrl,
    [string]$OutFile,
    # Only for local validation: render although image-tags.yaml has no published digests yet.
    [switch]$AllowMissingImages
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $repo ".cache/argocd/root-application.yaml" }

$ecr = '^[0-9]{12}\.dkr\.ecr\.eu-west-2\.amazonaws\.com/finsight-dev/'
$checks = @(
    @{ Name = "VpcId"; Value = $VpcId; Pattern = '^vpc-[0-9a-f]{8,17}$' },
    @{ Name = "HostedZoneId"; Value = $HostedZoneId; Pattern = '^Z[A-Z0-9]{1,32}$' },
    @{ Name = "PublicIngressSecurityGroupId"; Value = $PublicIngressSecurityGroupId; Pattern = '^sg-[0-9a-f]{8,17}$' },
    @{ Name = "ApiRepositoryUrl"; Value = $ApiRepositoryUrl; Pattern = ($ecr + 'api$') },
    @{ Name = "FrontendRepositoryUrl"; Value = $FrontendRepositoryUrl; Pattern = ($ecr + 'frontend$') }
)
foreach ($check in $checks) {
    if ($check.Value -cnotmatch $check.Pattern) { throw "$($check.Name) does not have the expected format." }
}

# FinSight cannot render until the pipeline has merged published digests, and an unrenderable
# last wave keeps the root sync waiting. Refuse unless explicitly validating locally.
$tags = [IO.File]::ReadAllLines((Join-Path $repo "gitops/apps/finsight/image-tags.yaml"))
$component = $null
$digests = @{}
foreach ($line in $tags) {
    if ($line -match '^([a-z]+):\s*$') { $component = $Matches[1] }
    elseif ($component -and $line -match '^\s+digest:\s*"?([^"\s]*)"?\s*$') { $digests[$component] = $Matches[1] }
}
foreach ($name in "api", "frontend") {
    if ($digests[$name] -notmatch '^sha256:[0-9a-f]{64}$' -and -not $AllowMissingImages) {
        throw "gitops/apps/finsight/image-tags.yaml has no published $name digest. Merge the pipeline's image pull request first."
    }
}

$text = [IO.File]::ReadAllText((Join-Path $repo "gitops/argocd/root-application.yaml"))
$tokens = @{
    "__VPC_ID__" = $VpcId
    "__HOSTED_ZONE_ID__" = $HostedZoneId
    "__PUBLIC_INGRESS_SECURITY_GROUP_ID__" = $PublicIngressSecurityGroupId
    "__API_REPOSITORY_URL__" = $ApiRepositoryUrl
    "__FRONTEND_REPOSITORY_URL__" = $FrontendRepositoryUrl
}
foreach ($token in $tokens.Keys) {
    if (-not $text.Contains($token)) { throw "Token $token is missing from root-application.yaml." }
    $text = $text.Replace($token, $tokens[$token])
}
if ($text -match '__[A-Z_]+__') { throw "Unfilled token $($Matches[0]) in root-application.yaml." }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
[IO.File]::WriteAllText($OutFile, $text.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
Write-Host "Rendered $OutFile (ignored; do not commit). Apply with: kubectl apply -f `"$OutFile`""

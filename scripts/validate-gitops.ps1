# Offline validation of the Argo CD GitOps layout (G08) and the monitoring stack (G05): renders
# the root Application with sample values, then runs tests/gitops in a pinned Python container
# with pinned helm, kustomize (the version Argo CD v3.5.4 bundles), kubeconform and promtool.
# Needs Docker and network access for chart pulls and schemas. Never contacts a cluster or AWS.
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $repo ".cache/gitops-validation"
$bin = Join-Path $cache "bin"
New-Item -ItemType Directory -Force -Path $bin | Out-Null

$python = "python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1"
$tools = @(
    @{ Name = "helm"; Image = "alpine/helm:3.22.0@sha256:70ed3f7b02ab2eee12aa520ad6870305db8a82516b07aff62f5656c657a26e2a"; Path = "/usr/bin/helm" },
    @{ Name = "kustomize"; Image = "registry.k8s.io/kustomize/kustomize:v5.8.1@sha256:899fcd3bc898160e62bcaf82932b0cb29ba38d16272353db2e7acbba82129429"; Path = "/app/kustomize" },
    @{ Name = "kubeconform"; Image = "ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e"; Path = "/kubeconform" },
    # promtool from the Prometheus version kube-prometheus-stack 91.8.2 deploys (G05 rule and query checks).
    @{ Name = "promtool"; Image = "quay.io/prometheus/prometheus:v3.15.0@sha256:efd719c99d83b060d9daefdcf00360461adf279f45ef5391f8d111892118753e"; Path = "/bin/promtool" }
)
foreach ($tool in $tools) {
    $container = (docker create $tool.Image).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot create a container from $($tool.Image)." }
    try {
        docker cp "${container}:$($tool.Path)" (Join-Path $bin $tool.Name) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Cannot copy $($tool.Name) from $($tool.Image)." }
    } finally {
        docker rm $container | Out-Null
    }
}

# Renderer: sample values must render; malformed values and missing image digests must be refused.
$sample = @{
    VpcId = "vpc-0123456789abcdef0"
    HostedZoneId = "Z0SAMPLEZONE0000"
    PublicIngressSecurityGroupId = "sg-0123456789abcdef0"
    ApiRepositoryUrl = "000000000000.dkr.ecr.eu-west-2.amazonaws.com/finsight-dev/api"
    FrontendRepositoryUrl = "000000000000.dkr.ecr.eu-west-2.amazonaws.com/finsight-dev/frontend"
}
$renderer = Join-Path $PSScriptRoot "render-argocd-root.ps1"
$rendered = Join-Path $cache "root-application.yaml"
& $renderer @sample -OutFile $rendered -AllowMissingImages | Out-Null
$refusals = @(
    @{ Case = "security group"; Values = @{ PublicIngressSecurityGroupId = "REPLACE_WITH_PUBLIC_INGRESS_SECURITY_GROUP_ID" } },
    @{ Case = "hosted zone"; Values = @{ HostedZoneId = "/hostedzone/Z0SAMPLEZONE0000" } },
    @{ Case = "repository"; Values = @{ ApiRepositoryUrl = $sample.FrontendRepositoryUrl } }
)
foreach ($refusal in $refusals) {
    $values = $sample.Clone()
    foreach ($key in $refusal.Values.Keys) { $values[$key] = $refusal.Values[$key] }
    $refused = $false
    try { & $renderer @values -OutFile (Join-Path $cache "refused.yaml") -AllowMissingImages | Out-Null } catch { $refused = $true }
    if (-not $refused) { throw "The renderer accepted an invalid $($refusal.Case)." }
}
$refused = $false
try { & $renderer @sample -OutFile (Join-Path $cache "refused.yaml") | Out-Null } catch { $refused = $_.Exception.Message -match "no published" }
if (-not $refused) { throw "The renderer did not refuse an image-tags.yaml without published digests." }
Write-Host "Renderer: sample rendered; 4 invalid inputs refused."

$command = "pip install --quiet --disable-pip-version-check --root-user-action=ignore pytest==9.1.1 PyYAML==6.0.3 " +
    "&& PATH=/cache/bin:`$PATH python -m pytest -q -p no:cacheprovider tests/gitops"
docker run --rm -e PYTHONDONTWRITEBYTECODE=1 -e GITOPS_CACHE=/cache -e ROOT_RENDERED=/cache/root-application.yaml `
    -v "${repo}:/repo:ro" -v "${cache}:/cache" -w /repo $python sh -c $command
if ($LASTEXITCODE -ne 0) { throw "GitOps tests failed." }

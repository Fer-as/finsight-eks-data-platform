# Creates the two Kubernetes Secrets the GitOps bootstrap needs, before the root Application is
# applied (docs/infrastructure/argocd.md step 1):
#   finsight/finsight-database   PGDATABASE, PGUSER, PGPASSWORD  (PostgreSQL, init Job and API)
#   monitoring/grafana-admin     admin-user, admin-password      (Grafana)
# Passwords are typed at a hidden prompt (or passed as SecureString). Nothing is generated, printed
# or written to disk, and no credential appears in a command line: each Secret is sent to
# `kubectl create -f -` on standard input. Existing Secrets are never overwritten.
[CmdletBinding()]
param(
    [string]$DatabaseName = "finsight",
    [string]$DatabaseUser = "finsight",
    [string]$GrafanaUser = "finsight-admin",
    [SecureString]$DatabasePassword,
    [SecureString]$GrafanaPassword,
    # Validate locally without a cluster: kubectl parses the manifests offline; prints only names.
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"

function Read-Password([string]$Purpose) {
    $first = Read-Host "$Purpose (hidden)" -AsSecureString
    $second = Read-Host "Repeat $Purpose" -AsSecureString
    if ((Get-Plain $first) -cne (Get-Plain $second)) { throw "The two $Purpose entries differ." }
    return $first
}

function Get-Plain([SecureString]$Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Invoke-Kubectl([string[]]$Arguments, [string]$InputText) {
    $info = New-Object Diagnostics.ProcessStartInfo "kubectl"
    $info.Arguments = $Arguments -join " "
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    # ASCII without a byte-order mark: the manifest contains only ASCII (values are base64).
    $writer = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.ASCIIEncoding))
    $writer.Write($InputText)
    $writer.Close()
    $output = $process.StandardOutput.ReadToEnd()
    $errors = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "kubectl $($Arguments[0]) failed: $errors" }
    return $output.Trim()
}

function New-Secret([string]$Namespace, [string]$Name, [hashtable]$Values) {
    if (-not $DryRun) {
        & kubectl get namespace $Namespace -o name 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { & kubectl create namespace $Namespace | Out-Null }
        & kubectl -n $Namespace get secret $Name -o name 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { throw "Secret $Namespace/$Name already exists; delete it deliberately before recreating." }
    }
    $data = @{}
    foreach ($key in $Values.Keys) { $data[$key] = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Values[$key])) }
    $manifest = @{ apiVersion = "v1"; kind = "Secret"; type = "Opaque"; metadata = @{ name = $Name; namespace = $Namespace }; data = $data } |
        ConvertTo-Json -Depth 4 -Compress
    $arguments = @("create", "-f", "-", "-o", "name")
    # Offline: kubectl parses the same manifest from standard input without contacting a server.
    if ($DryRun) { $arguments = @("label", "--local", "-f", "-", "-o", "name", "finsight-dry-run=true") }
    Invoke-Kubectl $arguments $manifest
}

if ($DatabaseName -notmatch '^[a-z_][a-z0-9_]{0,62}$' -or $DatabaseUser -notmatch '^[a-z_][a-z0-9_]{0,62}$') {
    throw "Database and user names must be lowercase PostgreSQL identifiers."
}
if (-not $DatabasePassword) { $DatabasePassword = Read-Password "PostgreSQL password for $DatabaseUser" }
if (-not $GrafanaPassword) { $GrafanaPassword = Read-Password "Grafana password for $GrafanaUser" }
foreach ($secret in $DatabasePassword, $GrafanaPassword) {
    if ((Get-Plain $secret).Length -lt 16) { throw "Use passwords of at least 16 characters (from a password manager)." }
}

New-Secret "finsight" "finsight-database" @{
    PGDATABASE = $DatabaseName; PGUSER = $DatabaseUser; PGPASSWORD = (Get-Plain $DatabasePassword)
}
New-Secret "monitoring" "grafana-admin" @{
    "admin-user" = $GrafanaUser; "admin-password" = (Get-Plain $GrafanaPassword)
}
$DatabasePassword.Dispose(); $GrafanaPassword.Dispose()
if ($DryRun) { Write-Host "Dry run only: nothing was sent to a cluster." }

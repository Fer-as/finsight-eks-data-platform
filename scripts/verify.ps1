param([switch]$SkipSmoke)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    docker compose --profile test run --build --rm test
    if ($LASTEXITCODE -ne 0) { throw 'Python/PostgreSQL tests failed' }
    docker compose --profile test run --build --rm frontend-test
    if ($LASTEXITCODE -ne 0) { throw 'Frontend tests or build failed' }
    if (-not $SkipSmoke) {
        $apiPort = 8000
        $frontendPort = 5173
        if (Test-Path .env) {
            foreach ($line in Get-Content .env) {
                if ($line -match '^API_PORT=(\d+)$') { $apiPort = [int]$Matches[1] }
                if ($line -match '^FRONTEND_PORT=(\d+)$') { $frontendPort = [int]$Matches[1] }
            }
        }
        $ready = Invoke-RestMethod "http://localhost:$apiPort/api/health/ready"
        if ($ready.status -ne 'ready') { throw 'API is not ready' }
        $dashboard = Invoke-RestMethod "http://localhost:$frontendPort/api/dashboard"
        if (-not $dashboard.has_data -or $dashboard.currency -ne 'GBP') {
            throw 'Frontend proxy did not return populated GBP analytics'
        }
        $page = Invoke-WebRequest "http://localhost:$frontendPort/" -UseBasicParsing
        if ($page.StatusCode -ne 200) { throw 'Frontend did not respond' }
        Write-Host 'Smoke checks passed: API readiness, frontend and proxied analytics.'
    }
} finally {
    Pop-Location
}

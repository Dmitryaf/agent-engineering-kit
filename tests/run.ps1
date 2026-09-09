[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$powershellExe = (Get-Process -Id $PID -ErrorAction Stop).Path
$suites = @(
    'contracts/test-contracts.ps1',
    'sync/test-sync-plan.ps1',
    'diagnostics/test-project-state.ps1',
    'policy-structure/test-module-boundaries.ps1',
    'policy-structure/test-portable-boundaries.ps1',
    'policy-structure/test-evals.ps1',
    'cli/test-integration.ps1'
)

foreach ($suite in $suites) {
    $suitePath = Join-Path $PSScriptRoot $suite
    Write-Host "== $suite =="
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $suitePath
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Host 'All tooling suites passed.' -ForegroundColor Green
exit 0

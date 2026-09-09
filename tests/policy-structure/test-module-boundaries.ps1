[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$requiredModules = @('Catalog.psm1', 'Contracts.psm1', 'PathsAndHashing.psm1', 'GitState.psm1', 'SyncPlan.psm1', 'ProjectState.psm1', 'Diagnostics.psm1')
foreach ($module in $requiredModules) {
    if (-not (Test-Path -LiteralPath (Join-Path $hubRoot "src/$module") -PathType Leaf)) { throw "Required module is missing: $module" }
}

$cli = Get-Content -LiteralPath (Join-Path $hubRoot 'ai-rules.ps1') -Raw -Encoding UTF8
$syncPlan = Get-Content -LiteralPath (Join-Path $hubRoot 'src/SyncPlan.psm1') -Raw -Encoding UTF8
if ($cli -match "Summary:\\s" -or $cli -match 'function Get-PlanSummary' -or $cli -match '\[regex\]::Replace\(\$planOutput') { throw 'CLI must not parse or rewrite its own human-readable plan output.' }
if ($cli -notmatch 'Get-AiRulesProjectState' -or $cli -notmatch 'Get-AiRulesStatusAssessment') { throw 'CLI status and doctor must consume modular state and diagnostics.' }
if ($syncPlan -match '\b(Set-Content|Add-Content|Copy-Item|Move-Item|Remove-Item|WriteAllBytes|WriteAllText)\b') { throw 'SyncPlan module must remain read-only.' }

Write-Host 'Module boundary tests passed: 10 assertions.' -ForegroundColor Green

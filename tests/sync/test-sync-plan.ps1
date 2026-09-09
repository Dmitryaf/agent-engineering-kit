[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$projectRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ai-rules-sync-plan-$([Guid]::NewGuid().ToString('N'))"
$powershellExe = (Get-Process -Id $PID -ErrorAction Stop).Path

try {
    New-Item -ItemType Directory -Path $projectRoot | Out-Null
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hubRoot 'scripts/init-project-sync.ps1') -ProjectRoot $projectRoot -Profiles standard-product
    if ($LASTEXITCODE -ne 0) { throw 'Sync plan fixture initialization failed.' }
    $before = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join "`n"

    Import-Module (Join-Path $hubRoot 'src/SyncPlan.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $hubRoot 'src/PathsAndHashing.psm1') -Force -ErrorAction Stop
    $plan = Get-AiRulesSyncPlan -HubRoot $hubRoot -ProjectRoot $projectRoot
    $after = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join "`n"

    if ($plan.PSObject.TypeNames[0] -ne 'AiRules.SyncPlan') { throw 'Get-AiRulesSyncPlan must return the typed contract.' }
    if ($plan.Summary['add'] -le 0 -or $plan.Entries.Count -le 0) { throw 'Unpinned plan must contain managed additions.' }
    if ($before -ne $after) { throw 'Get-AiRulesSyncPlan must be read-only.' }
    $indexEntries = @($plan.Entries | Where-Object { $_.Target -eq '.ai-rules/upstream/INDEX.md' })
    if ($indexEntries.Count -ne 1 -or $indexEntries[0].Source -ne 'generated/effective-index') { throw 'Sync plan must contain one generated effective index.' }
    if ($indexEntries[0].Content -notmatch 'standard-product' -or $indexEntries[0].Content -notmatch '`profile`' -or $indexEntries[0].Content -match 'project-study') { throw 'Effective index must describe only selected profiles and effective topics.' }
    if ($indexEntries[0].Sha256 -ne (Get-AiRulesSha256Text -Content $indexEntries[0].Content)) { throw 'Effective index hash must cover generated content.' }
    $secondPlan = Get-AiRulesSyncPlan -HubRoot $hubRoot -ProjectRoot $projectRoot
    if (@($secondPlan.Entries | Where-Object { $_.Target -eq '.ai-rules/upstream/INDEX.md' })[0].Content -ne $indexEntries[0].Content) { throw 'Effective index generation must be deterministic.' }
    $expectedPathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq [char]'\') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ((Get-AiRulesPathComparison) -ne $expectedPathComparison) { throw 'Path comparison must follow the current filesystem platform.' }
    $caseBoundaryAccepted = $true
    try { [void](Get-AiRulesSafePath -BasePath (Join-Path $projectRoot 'CaseBase') -ChildPath '../casebase/escape.md' -Label 'case boundary') } catch { $caseBoundaryAccepted = $false }
    if (($env:OS -eq 'Windows_NT') -ne $caseBoundaryAccepted) { throw 'Path containment must follow filesystem case sensitivity.' }
    Write-Host 'Sync plan tests passed: 9 assertions.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $projectRoot) { Remove-Item -LiteralPath $projectRoot -Recurse -Force }
}

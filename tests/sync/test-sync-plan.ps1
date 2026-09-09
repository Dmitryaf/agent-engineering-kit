[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$projectRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ai-rules-sync-plan-$([Guid]::NewGuid().ToString('N'))"
$powershellExe = (Get-Command powershell.exe -ErrorAction Stop).Source

try {
    New-Item -ItemType Directory -Path $projectRoot | Out-Null
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hubRoot 'scripts/init-project-sync.ps1') -ProjectRoot $projectRoot -Profiles standard-product
    if ($LASTEXITCODE -ne 0) { throw 'Sync plan fixture initialization failed.' }
    $before = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join "`n"

    Import-Module (Join-Path $hubRoot 'src/SyncPlan.psm1') -Force -ErrorAction Stop
    $plan = Get-AiRulesSyncPlan -HubRoot $hubRoot -ProjectRoot $projectRoot
    $after = @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }) -join "`n"

    if ($plan.PSObject.TypeNames[0] -ne 'AiRules.SyncPlan') { throw 'Get-AiRulesSyncPlan must return the typed contract.' }
    if ($plan.Summary['add'] -le 0 -or $plan.Entries.Count -le 0) { throw 'Unpinned plan must contain managed additions.' }
    if ($before -ne $after) { throw 'Get-AiRulesSyncPlan must be read-only.' }
    Write-Host 'Sync plan tests passed: 3 assertions.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $projectRoot) { Remove-Item -LiteralPath $projectRoot -Recurse -Force }
}

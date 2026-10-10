[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$projectRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ai-rules-sync-plan-$([Guid]::NewGuid().ToString('N'))"
$powershellExe = (Get-Process -Id $PID -ErrorAction Stop).Path

try {
    New-Item -ItemType Directory -Path $projectRoot | Out-Null
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hubRoot 'scripts/init-project-sync.ps1') -ProjectRoot $projectRoot -Profiles standard-product,data-sensitive
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
    if ($indexEntries[0].Content -notmatch 'standard-product' -or $indexEntries[0].Content -notmatch '`profile`' -or $indexEntries[0].Content -match 'project-study|project-audit|parallel-delivery') { throw 'Effective index must describe only selected profiles and effective topics.' }
    # Check the produced index, not only the wording in its source catalog.
    $catalog = Get-Content -LiteralPath (Join-Path $hubRoot 'sync/catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($topic in @('product', 'architecture-and-data', 'security-and-privacy', 'git-and-delivery')) {
        $condition = [string]$catalog.topics.$topic.readWhen
        $entryHeader = '### ' + [char]96 + $topic + [char]96
        $entry = @(
            $indexEntries[0].Content -split '(?m)(?=^### )' |
                Where-Object {
                    $_.StartsWith($entryHeader + [Environment]::NewLine) -or
                    $_.StartsWith($entryHeader + [char]10)
                }
        )
        if ($entry.Count -ne 1 -or -not $entry[0].Contains($condition)) {
            throw "Effective index must preserve the exact routing condition for $topic."
        }
    }
    foreach ($profile in @('standard-product', 'data-sensitive')) {
        if (-not $indexEntries[0].Content.Contains('profiles/' + $profile + '.md')) {
            throw "Task-first routing must retain selected profile $profile."
        }
    }
    $coreEntries = @($plan.Entries | Where-Object { $_.Target -eq '.ai-rules/upstream/CORE.md' })
    if ($coreEntries.Count -ne 1 -or $coreEntries[0].Source -ne 'rules/CORE.md' -or $indexEntries[0].Content -notmatch '### `core`' -or $indexEntries[0].Content -notmatch '`CORE.md`') { throw 'The mandatory core must be installed once and routed in the effective index.' }
    if (@($plan.Entries | Where-Object { $_.Target -eq '.ai-rules/upstream/workflows/PARALLEL_DELIVERY.md' }).Count -ne 0) { throw 'Unselected parallel workflow must not enter the sync plan.' }
    if ($indexEntries[0].Sha256 -ne (Get-AiRulesSha256Text -Content $indexEntries[0].Content)) { throw 'Effective index hash must cover generated content.' }
    $secondPlan = Get-AiRulesSyncPlan -HubRoot $hubRoot -ProjectRoot $projectRoot
    if (@($secondPlan.Entries | Where-Object { $_.Target -eq '.ai-rules/upstream/INDEX.md' })[0].Content -ne $indexEntries[0].Content) { throw 'Effective index generation must be deterministic.' }
    $parallelProjectRoot = Join-Path $projectRoot 'parallel project'
    New-Item -ItemType Directory -Path $parallelProjectRoot | Out-Null
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hubRoot 'scripts/init-project-sync.ps1') -ProjectRoot $parallelProjectRoot -Topics parallel-delivery
    if ($LASTEXITCODE -ne 0) { throw 'Explicit parallel workflow fixture initialization failed.' }
    $parallelPlan = Get-AiRulesSyncPlan -HubRoot $hubRoot -ProjectRoot $parallelProjectRoot
    $parallelWorkflowEntries = @($parallelPlan.Entries | Where-Object { $_.Target -eq '.ai-rules/upstream/workflows/PARALLEL_DELIVERY.md' })
    $parallelIndexEntries = @($parallelPlan.Entries | Where-Object { $_.Target -eq '.ai-rules/upstream/INDEX.md' })
    if ($parallelWorkflowEntries.Count -ne 1 -or $parallelIndexEntries.Count -ne 1 -or $parallelIndexEntries[0].Content -notmatch '### `parallel-delivery`' -or $parallelIndexEntries[0].Content -notmatch '`workflow`') { throw 'Explicit parallel selection must add its workflow and route it in the effective index.' }
    $expectedPathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq [char]'\') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ((Get-AiRulesPathComparison) -ne $expectedPathComparison) { throw 'Path comparison must follow the current filesystem platform.' }
    $caseBoundaryAccepted = $true
    try { [void](Get-AiRulesSafePath -BasePath (Join-Path $projectRoot 'CaseBase') -ChildPath '../casebase/escape.md' -Label 'case boundary') } catch { $caseBoundaryAccepted = $false }
    if (($env:OS -eq 'Windows_NT') -ne $caseBoundaryAccepted) { throw 'Path containment must follow filesystem case sensitivity.' }
    Write-Host 'Sync plan tests passed: 12 assertions.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $projectRoot) { Remove-Item -LiteralPath $projectRoot -Recurse -Force }
}

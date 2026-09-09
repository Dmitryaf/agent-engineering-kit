[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [ValidateSet('Plan', 'Apply')]
    [string]$Mode = 'Plan',

    [string]$RevisionOverride,

    [switch]$FailOnConflict,

    [switch]$SuppressNextStep
)

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $hubRoot 'scripts/sync-common.ps1')
Import-Module (Join-Path $hubRoot 'src/SyncPlan.psm1') -ErrorAction Stop

function Test-AiRulesBytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function New-AiRulesFileSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([System.IO.Directory]::Exists($Path)) {
        throw "$Label должен быть файлом, но является каталогом: $Path"
    }
    $exists = [System.IO.File]::Exists($Path)
    return [pscustomobject]@{
        Path = $Path
        Exists = $exists
        Bytes = $(if ($exists) { [System.IO.File]::ReadAllBytes($Path) } else { $null })
        Attributes = $(if ($exists) { [System.IO.File]::GetAttributes($Path) } else { $null })
    }
}

function Restore-AiRulesFileSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    if (-not $Snapshot.Exists) {
        if ([System.IO.Directory]::Exists($Snapshot.Path)) {
            throw "Rollback не удаляет каталог на месте ожидаемого файла: $($Snapshot.Path)"
        }
        if ([System.IO.File]::Exists($Snapshot.Path)) {
            [System.IO.File]::Delete($Snapshot.Path)
        }
        return
    }

    if ([System.IO.Directory]::Exists($Snapshot.Path)) {
        throw "Rollback не может восстановить файл поверх каталога: $($Snapshot.Path)"
    }
    if ([System.IO.File]::Exists($Snapshot.Path)) {
        $currentBytes = [System.IO.File]::ReadAllBytes($Snapshot.Path)
        if (Test-AiRulesBytesEqual -Left $currentBytes -Right $Snapshot.Bytes) {
            [System.IO.File]::SetAttributes($Snapshot.Path, $Snapshot.Attributes)
            return
        }
        [System.IO.File]::SetAttributes($Snapshot.Path, [System.IO.FileAttributes]::Normal)
    }
    else {
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Snapshot.Path)) | Out-Null
    }

    [System.IO.File]::WriteAllBytes($Snapshot.Path, $Snapshot.Bytes)
    [System.IO.File]::SetAttributes($Snapshot.Path, $Snapshot.Attributes)
}

if (-not [string]::IsNullOrWhiteSpace($RevisionOverride) -and $Mode -ne 'Plan') {
    throw 'RevisionOverride поддерживается только в режиме Plan.'
}
$syncPlan = Get-AiRulesSyncPlan -HubRoot $hubRoot -ProjectRoot $ProjectRoot -RevisionOverride $RevisionOverride
$projectRootFull = $syncPlan.ProjectRoot
$catalog = $syncPlan.Catalog
$manifest = $syncPlan.Manifest
$destinationRelative = '.ai-rules/upstream'
$manifestFullPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath '.ai-rules/manifest.json' -Label 'sync manifest'
$lockPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath '.ai-rules/lock.json' -Label 'sync lock'
$revision = $syncPlan.HubRevision
$sourceDirty = $syncPlan.HubDirty
$expectedRevision = $syncPlan.ExpectedRevision
$previousLock = $syncPlan.PreviousLock
$selectedTopics = @($syncPlan.Topics)
$plan = @($syncPlan.Entries)

if ($Mode -eq 'Apply') {
    if ([string]::IsNullOrWhiteSpace($expectedRevision)) {
        throw 'Apply требует закреплённую source.revision с полным commit SHA; для первого применения используйте update -Apply.'
    }
    if ($sourceDirty -eq $true) {
        throw 'Закреплённую синхронизацию нельзя применять из изменённого checkout хаба.'
    }
    if ($sourceDirty -ne $false) {
        throw 'Apply остановлен: чистоту рабочего дерева хаба определить не удалось.'
    }
}

Write-Host "Revision хаба: $revision"
Write-Host "Checkout хаба изменён: $sourceDirty"
Write-Host "Manifest: .ai-rules/manifest.json"
Write-Host "Managed root: $destinationRelative"
$plan | Select-Object Action, Source, Target | Format-Table -AutoSize

$actionOrder = @('add', 'update', 'unchanged', 'conflict', 'orphan', 'orphan-modified', 'orphan-missing')
$summaryParts = @(
    foreach ($actionName in $actionOrder) {
        $count = @($plan | Where-Object { $_.Action -eq $actionName }).Count
        if ($count -gt 0) {
            "${actionName}=$count"
        }
    }
)
Write-Host "Summary: $($summaryParts -join ', ')"

if ($Mode -eq 'Plan') {
    Write-Host 'Только Plan: файлы проекта не изменены.' -ForegroundColor Green
    $planConflicts = @($plan | Where-Object { $_.Action -eq 'conflict' })
    if ($planConflicts.Count -gt 0) {
        Write-Host 'Разрешите конфликты managed-файлов до Apply.' -ForegroundColor Yellow
        if ($FailOnConflict) {
            throw "Plan остановлен: конфликтов managed-файлов, требующих ручного решения: $($planConflicts.Count)."
        }
    }
    elseif (-not $SuppressNextStep) {
        Write-Host 'Следующий шаг: проверьте Plan и выбранную revision, затем повторите команду с -Mode Apply.'
    }
    exit 0
}

$conflicts = @($plan | Where-Object { $_.Action -eq 'conflict' })
if ($conflicts.Count -gt 0) {
    throw "Apply остановлен: конфликтов managed-файлов, требующих ручного решения: $($conflicts.Count)."
}

$lockEntries = @(
    $plan |
        Sort-Object Target |
        ForEach-Object {
            [ordered]@{
                source = $_.Source
                target = $_.Target
                sha256 = $_.Sha256
                state = $(if ($_.Managed) { 'managed' } else { 'orphan' })
            }
        }
)

$generatedAtUtc = [DateTime]::UtcNow.ToString('o')
if ($null -ne $previousLock -and -not [string]::IsNullOrWhiteSpace([string]$previousLock.generatedAtUtc)) {
    $generatedAtUtc = [string]$previousLock.generatedAtUtc
}

$lockObject = [ordered]@{
    schemaVersion = '0.2'
    generatedAtUtc = $generatedAtUtc
    source = [ordered]@{
        repository = 'ai-rules-hub'
        revision = $revision
        dirty = $sourceDirty
        catalogVersion = $catalog.schemaVersion
    }
    manifest = '.ai-rules/manifest.json'
    managedRoot = $destinationRelative
    topics = @($selectedTopics | Sort-Object)
    profiles = @($manifest.profiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    files = $lockEntries
}

$lockJson = ConvertTo-AiRulesJson -InputObject $lockObject -Depth 10
$lockChanged = $true
if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
    $existingLockJson = [System.IO.File]::ReadAllText($lockPath).TrimEnd([char[]]@("`r", "`n"))
    if ($existingLockJson -eq $lockJson.TrimEnd([char[]]@("`r", "`n"))) {
        $lockChanged = $false
    }
}

if ($lockChanged) {
    $lockObject.generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $lockJson = ConvertTo-AiRulesJson -InputObject $lockObject -Depth 10
}

$writeItems = @($plan | Where-Object { $_.Action -in @('add', 'update') })
$snapshots = [System.Collections.Generic.List[object]]::new()
foreach ($item in $writeItems) {
    $validatedTargetPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath $item.Target -Label 'managed target'
    if ($validatedTargetPath -ne $item.TargetPath) {
        throw "Managed target изменился после построения Plan: $($item.Target)"
    }
    $snapshots.Add((New-AiRulesFileSnapshot -Path $item.TargetPath -Label 'Managed target'))
}
if ($lockChanged) {
    $validatedLockPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath '.ai-rules/lock.json' -Label 'sync lock'
    if ($validatedLockPath -ne $lockPath) {
        throw 'Путь lock изменился после построения Plan.'
    }
    $snapshots.Add((New-AiRulesFileSnapshot -Path $lockPath -Label 'Sync lock'))
}

$createdDirectories = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($item in $writeItems) {
        $validatedTargetPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath $item.Target -Label 'managed target'
        if ($validatedTargetPath -ne $item.TargetPath) {
            throw "Managed target изменился во время Apply: $($item.Target)"
        }

        $targetDirectory = Split-Path -Parent $item.TargetPath
        if (-not [System.IO.Directory]::Exists($targetDirectory)) {
            $missingDirectories = [System.Collections.Generic.List[string]]::new()
            $directoryCursor = $targetDirectory
            while (-not [System.IO.Directory]::Exists($directoryCursor)) {
                if ([System.IO.File]::Exists($directoryCursor)) {
                    throw "Родитель managed target должен быть каталогом: $directoryCursor"
                }
                $missingDirectories.Add($directoryCursor)
                $parentDirectory = Split-Path -Parent $directoryCursor
                if ([string]::IsNullOrWhiteSpace($parentDirectory) -or $parentDirectory -eq $directoryCursor) {
                    throw "Не удалось определить существующий родитель для managed target: $($item.Target)"
                }
                $directoryCursor = $parentDirectory
            }

            foreach ($missingDirectory in @($missingDirectories | Sort-Object Length)) {
                [System.IO.Directory]::CreateDirectory($missingDirectory) | Out-Null
                if (-not $createdDirectories.Contains($missingDirectory)) {
                    $createdDirectories.Add($missingDirectory)
                }
            }
        }

        [void](Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath $item.Target -Label 'managed target')
        Copy-Item -LiteralPath $item.SourcePath -Destination $item.TargetPath -Force
    }

    if ($lockChanged) {
        [void](Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath '.ai-rules/lock.json' -Label 'sync lock')
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($lockPath, $lockJson + "`n", $utf8WithoutBom)
        Write-Host "Lock обновлён: $lockPath" -ForegroundColor Green
    }
    else {
        Write-Host "Lock не изменён: $lockPath" -ForegroundColor Green
    }
}
catch {
    $applyError = $_.Exception.Message
    $rollbackErrors = [System.Collections.Generic.List[string]]::new()

    for ($snapshotIndex = $snapshots.Count - 1; $snapshotIndex -ge 0; $snapshotIndex--) {
        try {
            Restore-AiRulesFileSnapshot -Snapshot $snapshots[$snapshotIndex]
        }
        catch {
            $rollbackErrors.Add($_.Exception.Message)
        }
    }

    foreach ($createdDirectory in @($createdDirectories | Sort-Object Length -Descending)) {
        try {
            if ([System.IO.Directory]::Exists($createdDirectory)) {
                [System.IO.Directory]::Delete($createdDirectory, $false)
            }
        }
        catch {
            $rollbackErrors.Add("Не удалось удалить созданный каталог ${createdDirectory}: $($_.Exception.Message)")
        }
    }

    if ($rollbackErrors.Count -gt 0) {
        throw "Apply завершился ошибкой: $applyError Rollback также завершился ошибкой: $($rollbackErrors -join ' | ')"
    }
    throw "Apply завершился ошибкой; исходное состояние восстановлено: $applyError"
}

Write-Host 'Sync применён.' -ForegroundColor Green

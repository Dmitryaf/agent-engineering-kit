$moduleRoot = $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'PathsAndHashing.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'Catalog.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'GitState.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'Contracts.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'EffectiveIndex.psm1') -ErrorAction Stop

function Get-AiRulesJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw ("Некорректный JSON в {0}: {1}" -f $Path, $_.Exception.Message)
    }
}

function Get-AiRulesObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw ("Неизвестное значение {0}: {1}" -f $Label, $Name)
    }
    return $property.Value
}

function Get-AiRulesManagedRelativePath {
    param([Parameter(Mandatory = $true)][string]$SourceRelativePath)

    $normalizedSource = $SourceRelativePath.Replace('\', '/')
    if ($normalizedSource -eq 'rules/CORE.md') {
        return 'CORE.md'
    }
    return $normalizedSource
}

function Get-AiRulesSyncPlan {
    param(
        [Parameter(Mandatory = $true)][string]$HubRoot,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$RevisionOverride
    )

    $hubRootFull = (Resolve-Path -LiteralPath $HubRoot).Path
    $projectRootFull = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $catalog = Get-AiRulesCatalog -HubRoot $hubRootFull
    $destinationRelative = '.ai-rules/upstream'
    $manifestFullPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath '.ai-rules/manifest.json' -Label 'sync manifest'
    [void](Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath $destinationRelative -Label 'managed root')
    $lockPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath '.ai-rules/lock.json' -Label 'sync lock'

    if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) {
        throw "Sync manifest не найден: $manifestFullPath"
    }

    $manifest = Get-AiRulesJsonFile -Path $manifestFullPath
    if ($manifest.schemaVersion -ne '0.2') {
        throw "Неподдерживаемая manifest schemaVersion: $($manifest.schemaVersion)"
    }
    foreach ($requiredProperty in @('source', 'topics', 'profiles')) {
        if ($null -eq $manifest.PSObject.Properties[$requiredProperty]) {
            throw "Обязательное поле manifest отсутствует: $requiredProperty"
        }
    }
    if ($null -eq $manifest.source.PSObject.Properties['repository']) {
        throw 'В manifest обязательно поле source.repository.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.source.repository)) {
        throw 'Поле source.repository не должно быть пустым.'
    }
    if ($null -eq $manifest.source.PSObject.Properties['revision']) {
        throw 'В manifest обязательно поле source.revision; для незакреплённой подготовки используйте null.'
    }

    $pathComparer = Get-AiRulesPathStringComparer
    $pathComparison = Get-AiRulesPathComparison
    $selectedSources = New-Object 'System.Collections.Generic.HashSet[string]' ($pathComparer)
    $selectedTopics = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($coreFile in @($catalog.core)) {
        [void]$selectedSources.Add([string]$coreFile)
    }
    foreach ($topicName in @($manifest.topics)) {
        $topic = Get-AiRulesObjectProperty -Object $catalog.topics -Name ([string]$topicName) -Label 'topic'
        [void]$selectedTopics.Add([string]$topicName)
        [void]$selectedSources.Add([string]$topic.file)
    }
    foreach ($profileName in @($manifest.profiles)) {
        $profile = Get-AiRulesObjectProperty -Object $catalog.profiles -Name ([string]$profileName) -Label 'profile'
        [void]$selectedSources.Add([string]$profile.file)
        foreach ($topicName in @($profile.topics)) {
            $topic = Get-AiRulesObjectProperty -Object $catalog.topics -Name ([string]$topicName) -Label 'profile topic'
            [void]$selectedTopics.Add([string]$topicName)
            [void]$selectedSources.Add([string]$topic.file)
        }
    }

    $revision = $null
    $sourceDirty = $null
    try {
        $hubState = Get-AiRulesHubGitState -HubRoot $hubRootFull
        $revision = $hubState.Revision
        $sourceDirty = $hubState.Dirty
    }
    catch {
        $revision = $null
        $sourceDirty = $null
    }

    $expectedRevision = $null
    if ($null -ne $manifest.source -and $null -ne $manifest.source.revision) {
        $expectedRevision = [string]$manifest.source.revision
    }
    if (-not [string]::IsNullOrWhiteSpace($RevisionOverride)) {
        if ($RevisionOverride -notmatch '^[0-9a-fA-F]{40}$') {
            throw 'RevisionOverride должен быть полным 40-символьным SHA Git commit.'
        }
        if ([string]::IsNullOrWhiteSpace($revision)) {
            throw 'Передан RevisionOverride, но Git revision хаба определить не удалось.'
        }
        if ($revision -ne $RevisionOverride) {
            throw "RevisionOverride должен совпадать с текущим checkout хаба. Ожидалось $RevisionOverride, получено $revision."
        }
        $expectedRevision = $RevisionOverride
    }
    if (-not [string]::IsNullOrWhiteSpace($expectedRevision)) {
        if ($expectedRevision -notmatch '^[0-9a-fA-F]{40}$') {
            throw 'Manifest source.revision должен быть полным 40-символьным SHA Git commit.'
        }
        if ([string]::IsNullOrWhiteSpace($revision)) {
            throw 'Manifest закрепляет revision, но Git revision хаба определить не удалось.'
        }
        if ($revision -ne $expectedRevision) {
            throw "Revision хаба не совпадает. Ожидалось $expectedRevision, получено $revision."
        }
    }

    $previousLock = $null
    $oldByTarget = @{}
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        $previousLock = Get-AiRulesJsonFile -Path $lockPath
        if ($previousLock.schemaVersion -ne '0.2') {
            throw "Неподдерживаемая lock schemaVersion: $($previousLock.schemaVersion)"
        }
        if ([string]$previousLock.manifest -ne '.ai-rules/manifest.json') {
            throw "Неподдерживаемый путь manifest в lock: $($previousLock.manifest)"
        }
        if ([string]$previousLock.managedRoot -ne $destinationRelative) {
            throw "Неподдерживаемый managed root в lock: $($previousLock.managedRoot)"
        }
        foreach ($entry in @($previousLock.files)) {
            $oldByTarget[[string]$entry.target] = $entry
        }
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $selectedTargets = New-Object 'System.Collections.Generic.HashSet[string]' ($pathComparer)
    foreach ($sourceRelativePath in @($selectedSources) | Sort-Object) {
        $sourceFullPath = Get-AiRulesSafePath -BasePath $hubRootFull -ChildPath $sourceRelativePath -Label 'catalog source'
        if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) {
            throw "Source из catalog не существует: $sourceRelativePath"
        }

        $managedRelativePath = Get-AiRulesManagedRelativePath -SourceRelativePath $sourceRelativePath
        $targetRelativePath = $destinationRelative.TrimEnd('/') + '/' + $managedRelativePath
        $targetFullPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath $targetRelativePath -Label 'managed target'
        if (-not $selectedTargets.Add($targetRelativePath)) {
            throw "Несколько catalog sources ведут в один managed target: $targetRelativePath"
        }

        $sourceHash = Get-AiRulesSha256 -Path $sourceFullPath
        $action = 'add'
        if (Test-Path -LiteralPath $targetFullPath -PathType Leaf) {
            $targetHash = Get-AiRulesSha256 -Path $targetFullPath
            if ($targetHash -eq $sourceHash) {
                $action = 'unchanged'
            }
            elseif ($oldByTarget.ContainsKey($targetRelativePath) -and $oldByTarget[$targetRelativePath].sha256 -eq $targetHash) {
                $action = 'update'
            }
            else {
                $action = 'conflict'
            }
        }

        $entries.Add([pscustomobject]@{
            Action = $action
            Source = $sourceRelativePath
            Target = $targetRelativePath
            SourcePath = $sourceFullPath
            Content = $null
            TargetPath = $targetFullPath
            Sha256 = $sourceHash
            Managed = $true
        })
    }

    $indexTargetRelativePath = $destinationRelative.TrimEnd('/') + '/INDEX.md'
    $indexTargetFullPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath $indexTargetRelativePath -Label 'generated index target'
    if (-not $selectedTargets.Add($indexTargetRelativePath)) {
        throw "Catalog source конфликтует со сгенерированным index: $indexTargetRelativePath"
    }
    $indexContent = New-AiRulesEffectiveIndexContent -Catalog $catalog -Manifest $manifest
    $indexHash = Get-AiRulesSha256Text -Content $indexContent
    $indexAction = 'add'
    if (Test-Path -LiteralPath $indexTargetFullPath -PathType Leaf) {
        $indexTargetHash = Get-AiRulesSha256 -Path $indexTargetFullPath
        if ($indexTargetHash -eq $indexHash) {
            $indexAction = 'unchanged'
        }
        elseif ($oldByTarget.ContainsKey($indexTargetRelativePath) -and $oldByTarget[$indexTargetRelativePath].sha256 -eq $indexTargetHash) {
            $indexAction = 'update'
        }
        else {
            $indexAction = 'conflict'
        }
    }
    $entries.Add([pscustomobject]@{
        Action = $indexAction
        Source = 'generated/effective-index'
        Target = $indexTargetRelativePath
        SourcePath = $null
        Content = $indexContent
        TargetPath = $indexTargetFullPath
        Sha256 = $indexHash
        Managed = $true
    })

    foreach ($oldTarget in @($oldByTarget.Keys) | Sort-Object) {
        if ($selectedTargets.Contains($oldTarget)) {
            continue
        }
        $managedPrefix = $destinationRelative.TrimEnd('/') + '/'
        if (-not $oldTarget.StartsWith($managedPrefix, $pathComparison)) {
            throw "Target из lock находится вне managed-каталога upstream: $oldTarget"
        }
        $oldTargetFullPath = Get-AiRulesSafePath -BasePath $projectRootFull -ChildPath $oldTarget -Label 'locked target'
        $orphanAction = 'orphan-missing'
        if (Test-Path -LiteralPath $oldTargetFullPath -PathType Leaf) {
            $oldTargetHash = Get-AiRulesSha256 -Path $oldTargetFullPath
            if ($oldTargetHash -eq $oldByTarget[$oldTarget].sha256) {
                $orphanAction = 'orphan'
            }
            else {
                $orphanAction = 'orphan-modified'
            }
        }
        $entries.Add([pscustomobject]@{
            Action = $orphanAction
            Source = [string]$oldByTarget[$oldTarget].source
            Target = $oldTarget
            SourcePath = $null
            Content = $null
            TargetPath = $oldTargetFullPath
            Sha256 = [string]$oldByTarget[$oldTarget].sha256
            Managed = $false
        })
    }

    $planParameters = @{
        ProjectRoot = $projectRootFull
        HubRoot = $hubRootFull
        Catalog = $catalog
        Manifest = $manifest
        HubRevision = $revision
        HubDirty = $sourceDirty
        ExpectedRevision = $expectedRevision
        Topics = @($selectedTopics | Sort-Object)
        Profiles = @($manifest.profiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        Entries = @($entries)
        PreviousLock = $previousLock
    }
    return New-AiRulesSyncPlan @planParameters
}

Export-ModuleMember -Function 'Get-AiRulesSyncPlan'

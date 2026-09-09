$moduleRoot = $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Contracts.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'PathsAndHashing.psm1') -ErrorAction Stop

function Get-AiRulesAgentRouteState {
    param([Parameter(Mandatory = $true)][string]$Content)

    $requiredRoutes = @('.ai-rules/RULESET.md', '.ai-rules/PROJECT_RULES.md', '.ai-rules/upstream/CORE.md', '.ai-rules/upstream/INDEX.md')
    $missingRequiredRoutes = @($requiredRoutes | Where-Object { -not $Content.Contains($_) })

    return [pscustomobject]@{
        RequiredRoutes = $requiredRoutes
        MissingRequiredRoutes = $missingRequiredRoutes
    }
}

function Get-AiRulesRulesetSection {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Heading
    )

    $pattern = '(?ms)^## ' + [regex]::Escape($Heading) + '[ \t]*(?:\r?\n(?<body>.*?)(?=^## |\z)|\z)'
    $match = [regex]::Match($Content, $pattern)
    return [pscustomobject]@{
        Found = $match.Success
        Content = if ($match.Success) { $match.Groups['body'].Value } else { '' }
    }
}

function Get-AiRulesRulesetSectionIds {
    param([Parameter(Mandatory = $true)][string]$Content)

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($Content -split '\r?\n')) {
        $match = [regex]::Match($line, '^\s*-\s*`(?<id>[A-Za-z0-9_-]+)`(?:\s|—|-|$)')
        if (-not $match.Success) {
            $match = [regex]::Match($line, '^\s*-\s*(?<id>[A-Za-z0-9][A-Za-z0-9_-]*)(?:\s|—|-|$)')
        }
        if ($match.Success) { $ids.Add($match.Groups['id'].Value) }
    }
    return @($ids | Sort-Object -Unique)
}

function Get-AiRulesRulesetConsistencyResults {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $selectedProfiles = @($Manifest.profiles | ForEach-Object { [string]$_ })
    $selectedTopics = @($Manifest.topics | ForEach-Object { [string]$_ })
    $profileSection = Get-AiRulesRulesetSection -Content $Content -Heading 'Выбранные профили'
    $topicSection = Get-AiRulesRulesetSection -Content $Content -Heading 'Дополнительные темы'

    if (-not $profileSection.Found -and $selectedProfiles.Count -gt 0) {
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'ruleset' -Message 'В RULESET.md нет раздела «Выбранные профили» для профилей из manifest.json.'))
    }
    elseif ($profileSection.Found) {
        $profileIds = @(Get-AiRulesRulesetSectionIds -Content $profileSection.Content)
        foreach ($profileId in @($Catalog.profiles.PSObject.Properties.Name)) {
            if ($profileId -in $selectedProfiles -and $profileId -notin $profileIds) {
                $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'ruleset' -Message "Профиль $profileId выбран в manifest.json, но не объяснён в разделе «Выбранные профили»."))
            }
            elseif ($profileId -notin $selectedProfiles -and $profileId -in $profileIds) {
                $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'ruleset' -Message "Раздел «Выбранные профили» содержит $profileId, но этот профиль не выбран в manifest.json."))
            }
        }
    }

    if (-not $topicSection.Found -and $selectedTopics.Count -gt 0) {
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'ruleset' -Message 'В RULESET.md нет раздела «Дополнительные темы» для тем из manifest.json.'))
    }
    elseif ($topicSection.Found) {
        $topicIds = @(Get-AiRulesRulesetSectionIds -Content $topicSection.Content)
        foreach ($topicId in @($Catalog.topics.PSObject.Properties.Name)) {
            if ($topicId -in $selectedTopics -and $topicId -notin $topicIds) {
                $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'ruleset' -Message "Тема $topicId выбрана напрямую, но не объяснена в секции «Дополнительные темы»."))
            }
            elseif ($topicId -notin $selectedTopics -and $topicId -in $topicIds) {
                $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'ruleset' -Message "Раздел «Дополнительные темы» содержит $topicId, но эта тема не выбрана напрямую в manifest.json."))
            }
        }
    }
    return @($results)
}

function Get-AiRulesLockSnapshotResults {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)]$Lock
    )

    $results = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Lock.PSObject.Properties['files']) {
        $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message 'В lock.json отсутствует массив files.'))
        return @($results)
    }

    $upstreamRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '.ai-rules/upstream')).TrimEnd([char[]]@('\', '/'))
    $upstreamPrefix = $upstreamRoot + [System.IO.Path]::DirectorySeparatorChar
    foreach ($entry in @($Lock.files)) {
        $target = [string]$entry.target
        $entryState = [string]$entry.state
        if ([string]::IsNullOrWhiteSpace($target) -or [System.IO.Path]::IsPathRooted($target)) {
            $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message "Некорректный относительный путь target в lock.json: $target"))
            continue
        }
        try {
            $targetPath = Get-AiRulesSafePath -BasePath $ProjectRoot -ChildPath $target -Label 'lock target'
        }
        catch {
            $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message $_.Exception.Message))
            continue
        }
        if (-not $targetPath.StartsWith($upstreamPrefix, (Get-AiRulesPathComparison))) {
            $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message "Путь target из lock.json находится вне .ai-rules/upstream/: $target"))
            continue
        }
        if ($entryState -notin @('managed', 'orphan')) {
            $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message "Неизвестное состояние '$entryState' в lock.json для $target."))
            continue
        }
        if ([string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message "Некорректный SHA-256 в lock.json для $target."))
            continue
        }

        $exists = Test-Path -LiteralPath $targetPath -PathType Leaf
        if ($entryState -eq 'managed') {
            if (-not $exists) {
                $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message "Управляемый файл отсутствует: $target"))
                continue
            }
            $actualHash = Get-AiRulesSha256 -Path $targetPath
            if ($actualHash -ne [string]$entry.sha256) {
                $results.Add((New-AiRulesDiagnostic -Level 'ERROR' -Category 'lock' -Message "Управляемый файл изменён вручную: $target"))
            }
            else {
                $results.Add((New-AiRulesDiagnostic -Level 'OK' -Category 'lock' -Message "Управляемый файл соответствует lock.json: $target"))
            }
            continue
        }
        if (-not $exists) {
            $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'lock' -Message "Исключённый файл уже отсутствует, но остаётся в lock.json: $target"))
            continue
        }
        $actualHash = Get-AiRulesSha256 -Path $targetPath
        if ($actualHash -eq [string]$entry.sha256) {
            $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'lock' -Message "Исключённый файл сохранён без изменений: $target"))
        }
        else {
            $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'lock' -Message "Исключённый файл изменён; его нельзя удалять автоматически: $target"))
        }
    }
    return @($results)
}

function Get-AiRulesStatusAssessment {
    param([Parameter(Mandatory = $true)]$ProjectState)

    $diagnostics = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    if (-not $ProjectState.Found.Manifest) {
        return [pscustomobject]@{ State = 'not-initialized'; Diagnostics = @('сначала инициализируйте подключение проекта.'); Warnings = @() }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectState.ManifestError)) {
        return [pscustomobject]@{ State = 'inconsistent'; Diagnostics = @($ProjectState.ManifestError); Warnings = @() }
    }

    $manifest = $ProjectState.Manifest
    if ($manifest.schemaVersion -ne '0.2') { $diagnostics.Add("неподдерживаемая schemaVersion в manifest.json: $($manifest.schemaVersion).") }
    foreach ($requiredProperty in @('source', 'topics', 'profiles')) {
        if ($null -eq $manifest.PSObject.Properties[$requiredProperty]) { $diagnostics.Add("в manifest.json отсутствует поле: $requiredProperty.") }
    }
    if ($null -eq $manifest.source) {
        $diagnostics.Add('в manifest.json отсутствует source.')
    }
    else {
        if ($null -eq $manifest.source.PSObject.Properties['repository'] -or [string]$manifest.source.repository -ne 'ai-rules-hub') { $diagnostics.Add('manifest source.repository отсутствует или не поддерживается.') }
        if ($null -eq $manifest.source.PSObject.Properties['revision']) { $diagnostics.Add('в manifest.json отсутствует поле source.revision.') }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectState.SelectionError)) { $diagnostics.Add($ProjectState.SelectionError) }

    if ($ProjectState.Found.Lock) {
        if (-not [string]::IsNullOrWhiteSpace($ProjectState.LockError)) {
            $diagnostics.Add($ProjectState.LockError)
        }
        elseif ($null -ne $ProjectState.Lock) {
            $lock = $ProjectState.Lock
            if ($lock.schemaVersion -ne '0.2') { $diagnostics.Add("неподдерживаемая schemaVersion в lock.json: $($lock.schemaVersion).") }
            if ([string]$lock.manifest -ne '.ai-rules/manifest.json') { $diagnostics.Add('путь manifest в lock.json противоречит контракту.') }
            if ([string]$lock.managedRoot -ne '.ai-rules/upstream') { $diagnostics.Add('поле managedRoot в lock.json противоречит контракту.') }
            $lockTopics = @($lock.topics | ForEach-Object { [string]$_ } | Sort-Object -Unique)
            if ((@($ProjectState.EffectiveTopics | Sort-Object -Unique) -join "`n") -ne ($lockTopics -join "`n")) { $diagnostics.Add('итоговые темы в manifest.json и lock.json не совпадают.') }
            $lockProfiles = @($lock.profiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)
            if ((@($ProjectState.Profiles | Sort-Object -Unique) -join "`n") -ne ($lockProfiles -join "`n")) { $diagnostics.Add('профили в manifest.json и lock.json не совпадают.') }
            if ($ProjectState.LockContractValid) {
                foreach ($result in @(Get-AiRulesLockSnapshotResults -ProjectRoot $ProjectState.ProjectRoot -Lock $lock)) {
                    if ($result.Level -eq 'ERROR') { $diagnostics.Add($result.Message) }
                    elseif ($result.Level -eq 'WARN') { $warnings.Add($result.Message) }
                }
            }
        }
    }

    if ($diagnostics.Count -gt 0) {
        return [pscustomobject]@{ State = 'inconsistent'; Diagnostics = @($diagnostics); Warnings = @($warnings) }
    }
    if ([string]::IsNullOrWhiteSpace($ProjectState.ManifestRevision)) {
        $diagnostics.Add('версия правил ещё не закреплена.')
        return [pscustomobject]@{ State = 'unpinned'; Diagnostics = @($diagnostics); Warnings = @($warnings) }
    }
    if (-not $ProjectState.Pinned) { $diagnostics.Add('source.revision в manifest.json не является полным SHA Git.') }
    if (-not $ProjectState.Found.Lock) { $diagnostics.Add('для закреплённой версии отсутствует lock.json.') }
    if (-not $ProjectState.Found.ManagedRoot) { $diagnostics.Add('для закреплённой версии отсутствует каталог .ai-rules/upstream/.') }
    if ($ProjectState.Found.Lock -and [string]::IsNullOrWhiteSpace($ProjectState.LockRevision)) { $diagnostics.Add('в lock.json отсутствует source.revision.') }
    if (-not [string]::IsNullOrWhiteSpace($ProjectState.LockRevision) -and $ProjectState.LockRevision -notmatch '^[0-9a-fA-F]{40}$') { $diagnostics.Add('source.revision в lock.json не является полным SHA Git.') }
    if (-not [string]::IsNullOrWhiteSpace($ProjectState.LockRevision) -and $ProjectState.ManifestRevision -ne $ProjectState.LockRevision) { $diagnostics.Add('версии в manifest.json и lock.json не совпадают.') }
    if (-not $ProjectState.Found.Agents) {
        $diagnostics.Add('для закреплённого проекта отсутствует корневой AGENTS.md.')
    }
    else {
        $routes = Get-AiRulesAgentRouteState -Content (Get-Content -LiteralPath $ProjectState.Paths.Agents -Raw -Encoding UTF8)
        if ($routes.MissingRequiredRoutes.Count -gt 0) { $diagnostics.Add("закреплённый проект не подключает обязательные маршруты AI Rules Hub: $($routes.MissingRequiredRoutes -join ', ').") }
    }
    if (-not $ProjectState.Found.Ruleset) { $diagnostics.Add('для закреплённого проекта отсутствует .ai-rules/RULESET.md.') }
    if (-not $ProjectState.Found.ProjectRules) { $diagnostics.Add('для закреплённого проекта отсутствует .ai-rules/PROJECT_RULES.md.') }
    if ($diagnostics.Count -gt 0) {
        return [pscustomobject]@{ State = 'inconsistent'; Diagnostics = @($diagnostics); Warnings = @($warnings) }
    }

    switch ($ProjectState.RevisionRelation.Relation) {
        'ahead' { return [pscustomobject]@{ State = 'update-available'; Diagnostics = @('в локальной копии хаба есть более новая версия правил.'); Warnings = @($warnings) } }
        'behind' { return [pscustomobject]@{ State = 'checkout-older'; Diagnostics = @('локальная копия хаба старее версии проекта; update -Apply предложит откат.'); Warnings = @($warnings) } }
        'diverged' { return [pscustomobject]@{ State = 'checkout-diverged'; Diagnostics = @('версии проекта и хаба находятся в разных ветках истории.'); Warnings = @($warnings) } }
        'unavailable' { return [pscustomobject]@{ State = 'checkout-mismatch'; Diagnostics = @("сравнить версии не удалось. $($ProjectState.RevisionRelation.Detail)"); Warnings = @($warnings) } }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectState.SyncPlanError)) {
        return [pscustomobject]@{ State = 'inconsistent'; Diagnostics = @('не удалось подготовить план синхронизации.', $ProjectState.SyncPlanError); Warnings = @($warnings) }
    }
    if ($null -ne $ProjectState.SyncPlan -and $ProjectState.SyncPlan.IsUnchanged) {
        return [pscustomobject]@{ State = 'synchronized'; Diagnostics = @(); Warnings = @($warnings) }
    }
    return [pscustomobject]@{ State = 'inconsistent'; Diagnostics = @('план синхронизации содержит незавершённые изменения или конфликты.'); Warnings = @($warnings) }
}

Export-ModuleMember -Function @(
    'Get-AiRulesAgentRouteState',
    'Get-AiRulesRulesetConsistencyResults',
    'Get-AiRulesLockSnapshotResults',
    'Get-AiRulesStatusAssessment'
)

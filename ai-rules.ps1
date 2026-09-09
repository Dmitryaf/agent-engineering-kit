[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$ListTarget,

    [string]$ProjectRoot,

    [string[]]$Profiles = @(),

    [string[]]$Topics = @(),

    [switch]$NoSeedProjectFiles,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$powerShellExe = (Get-Process -Id $PID).Path
$syncScriptPath = Join-Path $hubRoot 'scripts/sync-rules.ps1'
$initScriptPath = Join-Path $hubRoot 'scripts/init-project-sync.ps1'
$promptScriptPath = Join-Path $hubRoot 'scripts/show-prompt.ps1'
. (Join-Path $hubRoot 'scripts/sync-common.ps1')
Import-Module (Join-Path $hubRoot 'src/Catalog.psm1') -ErrorAction Stop
Import-Module (Join-Path $hubRoot 'src/GitState.psm1') -ErrorAction Stop
Import-Module (Join-Path $hubRoot 'src/ProjectState.psm1') -ErrorAction Stop
Import-Module (Join-Path $hubRoot 'src/Diagnostics.psm1') -ErrorAction Stop

function Write-Help {
    @'
Команды AI Rules Hub

  help                     Показать эту справку.
  doctor                   Проверить сам хаб и его рабочее дерево.
  doctor -ProjectRoot PATH Проверить подключение проекта без изменений.
  list profiles            Показать профили и их назначение.
  list topics              Показать темы и их назначение.
  prompt connect -ProjectRoot PATH
                           Показать готовый запрос подключения для AI-агента.
  prompt audit             Показать готовый запрос подключения и аудита.
  connect -ProjectRoot PATH
                           Подготовить проект и показать первый Plan.
  connect -ProjectRoot PATH -Apply
                           Применить ранее показанный Plan и проверить результат.
  init   -ProjectRoot PATH Подготовить проект без применения правил.
  status -ProjectRoot PATH Показать состояние подключения проекта.
  plan   -ProjectRoot PATH Предварительно показать изменения текущей revision.
  apply  -ProjectRoot PATH Применить уже закреплённую revision.
  update -ProjectRoot PATH Показать переход на текущую revision хаба.
  update -ProjectRoot PATH -Apply
                           Закрепить текущую revision и применить её.

Примеры

  .\ai-rules.ps1 list profiles
  .\ai-rules.ps1 prompt connect -ProjectRoot C:\path\to\project
  .\ai-rules.ps1 prompt audit
  .\ai-rules.ps1 connect -ProjectRoot C:\path\to\project -Profiles standard-product
  .\ai-rules.ps1 connect -ProjectRoot C:\path\to\project -Profiles standard-product -Apply
  .\ai-rules.ps1 init -ProjectRoot C:\path\to\project -Profiles standard-product
  .\ai-rules.ps1 doctor -ProjectRoot C:\path\to\project
  .\ai-rules.ps1 status -ProjectRoot C:\path\to\project
  .\ai-rules.ps1 plan -ProjectRoot C:\path\to\project
  .\ai-rules.ps1 update -ProjectRoot C:\path\to\project
  .\ai-rules.ps1 update -ProjectRoot C:\path\to\project -Apply

plan ничего не меняет и использует revision из manifest.
apply работает только с уже закреплённой revision.
update использует текущий checkout хаба и меняет проект только с -Apply.
connect объединяет init и первый update, но не позволяет пропустить preview.

CLI не выполняет git pull или git fetch автоматически.
'@ | Write-Host
}

function Invoke-ChildScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [switch]$Capture
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1 | Out-String
        if (-not $Capture -and -not [string]::IsNullOrWhiteSpace($output)) {
            Write-Host $output.TrimEnd()
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Resolve-ProjectRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Для команды '$Command' обязателен параметр -ProjectRoot."
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Некорректный JSON в ${Path}: $($_.Exception.Message)"
    }
}

function Write-Values {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [object[]]$Values
    )

    Write-Host "${Label}:"
    if (@($Values).Count -eq 0) {
        Write-Host '  (не выбраны)'
        return
    }
    foreach ($value in @($Values)) {
        Write-Host "  $value"
    }
}

function Get-ManifestRevision {
    param([Parameter(Mandatory = $true)][string]$ResolvedProjectRoot)

    $manifestPath = Join-Path $ResolvedProjectRoot '.ai-rules/manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Manifest не найден: $manifestPath"
    }
    $manifest = Get-JsonFile -Path $manifestPath
    if ($null -eq $manifest.source -or $null -eq $manifest.source.PSObject.Properties['revision']) {
        throw 'В manifest отсутствует обязательное поле source.revision.'
    }
    if ($null -eq $manifest.source.revision) {
        return $null
    }
    return [string]$manifest.source.revision
}

function Write-StateResult {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$ResolvedProjectRoot
    )

    Write-Host "State: $State"
    switch ($State) {
        'not-initialized' {
            Write-Host 'Описание: проект ещё не подключён к AI Rules Hub.'
            Write-Host "Next: .\ai-rules.ps1 init -ProjectRoot `"$ResolvedProjectRoot`" -Profiles <profile>"
        }
        'unpinned' {
            Write-Host 'Описание: проект подготовлен, но ещё не закреплён за воспроизводимой revision.'
            Write-Host "Next: заполните локальные файлы и выполните .\ai-rules.ps1 update -ProjectRoot `"$ResolvedProjectRoot`" -Apply"
        }
        'update-available' {
            Write-Host 'Описание: текущий checkout хаба содержит более новую revision.'
            Write-Host "Next: просмотрите переход через .\ai-rules.ps1 update -ProjectRoot `"$ResolvedProjectRoot`""
        }
        'checkout-older' {
            Write-Host 'Описание: checkout хаба старее revision, установленной в проекте.'
            Write-Host 'Next: получите нужную версию хаба или явно переключите checkout; не применяйте update -Apply без намеренного отката.'
        }
        'checkout-diverged' {
            Write-Host 'Описание: revision проекта и текущий checkout хаба находятся в расходящихся историях.'
            Write-Host 'Next: проверьте ветку и историю локального checkout хаба перед обновлением проекта.'
        }
        'checkout-mismatch' {
            Write-Host 'Описание: отношение revision проекта и checkout хаба надёжно определить не удалось.'
            Write-Host 'Next: получите или переключите checkout на revision проекта либо нужную целевую revision.'
        }
        'synchronized' {
            Write-Host 'Описание: проект синхронизирован с текущей revision хаба.'
            Write-Host 'Next: действий не требуется.'
        }
        'inconsistent' {
            Write-Host 'Описание: подключение содержит противоречие или незавершённое managed-состояние.'
            Write-Host "Next: .\ai-rules.ps1 doctor -ProjectRoot `"$ResolvedProjectRoot`""
        }
        default {
            Write-Host 'Описание: состояние подключения не распознано.'
            Write-Host "Next: .\ai-rules.ps1 doctor -ProjectRoot `"$ResolvedProjectRoot`""
        }
    }
}

function Show-Status {
    param([Parameter(Mandatory = $true)][string]$ResolvedProjectRoot)

    $projectState = Get-AiRulesProjectState -HubRoot $hubRoot -ProjectRoot $ResolvedProjectRoot
    $assessment = Get-AiRulesStatusAssessment -ProjectState $projectState

    Write-Host "Проект: $($projectState.ProjectName)"
    Write-Host "Корень проекта: $($projectState.ProjectRoot)"
    Write-Host "Manifest: $(if ($projectState.Found.Manifest) { 'найден' } else { 'отсутствует' })"
    Write-Host "Lock: $(if ($projectState.Found.Lock) { 'найден' } else { 'отсутствует' })"
    Write-Host "Managed-каталог: $(if ($projectState.Found.ManagedRoot) { 'найден' } else { 'отсутствует' })"
    Write-Host ''
    Write-Host "Revision хаба: $($projectState.HubState.Revision)"
    Write-Host "Checkout хаба изменён: $($projectState.HubState.Dirty.ToString().ToLowerInvariant())"
    Write-Host ''
    Write-Host "Revision manifest: $(if ([string]::IsNullOrWhiteSpace($projectState.ManifestRevision)) { 'не закреплена' } else { $projectState.ManifestRevision })"
    Write-Host "Revision lock: $(if ([string]::IsNullOrWhiteSpace($projectState.LockRevision)) { 'отсутствует' } else { $projectState.LockRevision })"
    Write-Values -Label 'Профили (Profiles)' -Values $projectState.Profiles
    Write-Values -Label 'Прямые темы (Direct topics)' -Values $projectState.DirectTopics
    Write-Values -Label 'Итоговые темы (Effective topics)' -Values $projectState.EffectiveTopics
    Write-Host ''
    foreach ($warning in @($assessment.Warnings)) { Write-Host "Предупреждение: $warning" }
    foreach ($diagnostic in @($assessment.Diagnostics)) { Write-Host "Диагностика: $diagnostic" }
    Write-StateResult -State $assessment.State -ResolvedProjectRoot $ResolvedProjectRoot
    return
}

function Add-DoctorResult {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)]$Errors,
        [Parameter(Mandatory = $true)]$Warnings
    )

    Write-Host "[$Level] $Message"
    if ($Level -eq 'ERROR') {
        $Errors.Add($Message) | Out-Null
    }
    elseif ($Level -eq 'WARN') {
        $Warnings.Add($Message) | Out-Null
    }
}

function Get-TemplatePlaceholders {
    param([Parameter(Mandatory = $true)][string]$TemplatePath)

    $content = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
    return @(
        [regex]::Matches($content, '<[^<>\r\n]+>') |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )
}

function Invoke-ProjectDoctor {
    param([Parameter(Mandatory = $true)][string]$ResolvedProjectRoot)

    $projectState = Get-AiRulesProjectState -HubRoot $hubRoot -ProjectRoot $ResolvedProjectRoot
    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $projectName = $projectState.ProjectName
    $manifestPath = $projectState.Paths.Manifest
    $lockPath = $projectState.Paths.Lock
    $upstreamRoot = $projectState.Paths.ManagedRoot
    $agentsPath = $projectState.Paths.Agents
    $rulesetPath = $projectState.Paths.Ruleset
    $projectRulesPath = $projectState.Paths.ProjectRules
    $catalog = $projectState.Catalog
    $manifest = $null
    $manifestValid = $false
    $selectionsValid = $false
    $manifestRevision = $null
    $pinned = $false

    Write-Host "Проверка проекта: $projectName"
    Write-Host "Корень проекта: $ResolvedProjectRoot"
    Write-Host ''

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-DoctorResult -Level 'ERROR' -Message 'Manifest .ai-rules/manifest.json не найден.' -Errors $errors -Warnings $warnings
    }
    else {
        try {
            if (-not [string]::IsNullOrWhiteSpace($projectState.ManifestError)) {
                throw $projectState.ManifestError
            }
            $manifest = $projectState.Manifest
            if ($manifest.schemaVersion -ne '0.2') {
                Add-DoctorResult -Level 'ERROR' -Message "Manifest использует неподдерживаемую schemaVersion: $($manifest.schemaVersion)." -Errors $errors -Warnings $warnings
            }
            elseif (
                $null -eq $manifest.PSObject.Properties['source'] -or
                $null -eq $manifest.PSObject.Properties['profiles'] -or
                $null -eq $manifest.PSObject.Properties['topics'] -or
                $null -eq $manifest.source -or
                $null -eq $manifest.source.PSObject.Properties['revision'] -or
                [string]$manifest.source.repository -ne 'ai-rules-hub'
            ) {
                Add-DoctorResult -Level 'ERROR' -Message 'Manifest не содержит обязательные source, profiles и topics.' -Errors $errors -Warnings $warnings
            }
            else {
                $manifestValid = $true
                Add-DoctorResult -Level 'OK' -Message 'Manifest найден и валиден.' -Errors $errors -Warnings $warnings
                try {
                    Assert-AiRulesSelections -Catalog $catalog -SelectedProfiles @($manifest.profiles) -SelectedTopics @($manifest.topics)
                    $selectionsValid = $true
                    Add-DoctorResult -Level 'OK' -Message 'Все profiles и topics известны catalog.' -Errors $errors -Warnings $warnings
                }
                catch {
                    Add-DoctorResult -Level 'ERROR' -Message $_.Exception.Message -Errors $errors -Warnings $warnings
                }

                if ($null -ne $manifest.source.revision) {
                    $manifestRevision = [string]$manifest.source.revision
                }
                if ([string]::IsNullOrWhiteSpace($manifestRevision)) {
                    Add-DoctorResult -Level 'WARN' -Message 'Revision пока не закреплена; первое применение выполняется через update -Apply.' -Errors $errors -Warnings $warnings
                }
                elseif ($manifestRevision -notmatch '^[0-9a-fA-F]{40}$') {
                    Add-DoctorResult -Level 'ERROR' -Message 'Revision manifest должна быть полным 40-символьным Git SHA.' -Errors $errors -Warnings $warnings
                }
                else {
                    $pinned = $true
                    Add-DoctorResult -Level 'OK' -Message 'Revision закреплена полным Git SHA.' -Errors $errors -Warnings $warnings
                }
            }
        }
        catch {
            Add-DoctorResult -Level 'ERROR' -Message $_.Exception.Message -Errors $errors -Warnings $warnings
        }
    }

    foreach ($requiredFile in @(
        [pscustomobject]@{ Path = $agentsPath; Label = 'Корневой AGENTS.md' },
        [pscustomobject]@{ Path = $rulesetPath; Label = '.ai-rules/RULESET.md' },
        [pscustomobject]@{ Path = $projectRulesPath; Label = '.ai-rules/PROJECT_RULES.md' }
    )) {
        if (Test-Path -LiteralPath $requiredFile.Path -PathType Leaf) {
            Add-DoctorResult -Level 'OK' -Message "$($requiredFile.Label) найден." -Errors $errors -Warnings $warnings
        }
        else {
            Add-DoctorResult -Level 'ERROR' -Message "$($requiredFile.Label) не найден." -Errors $errors -Warnings $warnings
        }
    }

    $lock = $null
    $lockValid = $false
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($projectState.LockError)) {
                throw $projectState.LockError
            }
            $lock = $projectState.Lock
            if ($lock.schemaVersion -ne '0.2') {
                Add-DoctorResult -Level 'ERROR' -Message "Lock использует неподдерживаемую schemaVersion: $($lock.schemaVersion)." -Errors $errors -Warnings $warnings
            }
            elseif (
                [string]$lock.manifest -ne '.ai-rules/manifest.json' -or
                [string]$lock.managedRoot -ne '.ai-rules/upstream' -or
                $null -eq $lock.PSObject.Properties['source'] -or
                $null -eq $lock.PSObject.Properties['files']
            ) {
                Add-DoctorResult -Level 'ERROR' -Message 'Lock содержит неподдерживаемые пути manifest или managedRoot.' -Errors $errors -Warnings $warnings
            }
            else {
                $lockValid = $true
                Add-DoctorResult -Level 'OK' -Message 'Lock найден и валиден.' -Errors $errors -Warnings $warnings
            }
        }
        catch {
            Add-DoctorResult -Level 'ERROR' -Message $_.Exception.Message -Errors $errors -Warnings $warnings
        }
    }
    elseif ($pinned) {
        Add-DoctorResult -Level 'ERROR' -Message 'Для закреплённого проекта отсутствует .ai-rules/lock.json.' -Errors $errors -Warnings $warnings
    }

    if ($pinned) {
        if (Test-Path -LiteralPath $upstreamRoot -PathType Container) {
            Add-DoctorResult -Level 'OK' -Message 'Managed-каталог .ai-rules/upstream найден.' -Errors $errors -Warnings $warnings
        }
        else {
            Add-DoctorResult -Level 'ERROR' -Message 'Для закреплённого проекта отсутствует .ai-rules/upstream.' -Errors $errors -Warnings $warnings
        }
    }
    if ($pinned -and $lockValid) {
        if ([string]$lock.source.revision -eq $manifestRevision) {
            Add-DoctorResult -Level 'OK' -Message 'Revision manifest и lock согласованы.' -Errors $errors -Warnings $warnings
        }
        else {
            Add-DoctorResult -Level 'ERROR' -Message 'Revision manifest и lock не совпадают.' -Errors $errors -Warnings $warnings
        }
        $expectedTopics = @(Get-AiRulesEffectiveTopics -Catalog $catalog -SelectedProfiles @($manifest.profiles) -SelectedTopics @($manifest.topics) | Sort-Object -Unique)
        $lockTopics = @($lock.topics | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (($expectedTopics -join "`n") -ne ($lockTopics -join "`n")) {
            Add-DoctorResult -Level 'ERROR' -Message 'Итоговые темы manifest и lock не совпадают.' -Errors $errors -Warnings $warnings
        }
        $expectedProfiles = @($manifest.profiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $lockProfiles = @($lock.profiles | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        if (($expectedProfiles -join "`n") -ne ($lockProfiles -join "`n")) {
            Add-DoctorResult -Level 'ERROR' -Message 'Профили manifest и lock не совпадают.' -Errors $errors -Warnings $warnings
        }
    }
    if ($lockValid) {
        foreach ($snapshotResult in @(Get-AiRulesLockSnapshotResults -ProjectRoot $ResolvedProjectRoot -Lock $lock)) {
            Add-DoctorResult -Level $snapshotResult.Level -Message $snapshotResult.Message -Errors $errors -Warnings $warnings
        }
    }

    if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
        $agentsContent = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8
        $selectedProfiles = if ($manifestValid) { @($manifest.profiles | ForEach-Object { [string]$_ }) } else { @() }
        $routeState = Get-AiRulesAgentRouteState -Content $agentsContent -SelectedProfiles $selectedProfiles
        if ($routeState.MissingRequiredRoutes.Count -gt 0) {
            if ($pinned) {
                Add-DoctorResult -Level 'ERROR' -Message "Закреплённый проект не подключает обязательные маршруты AI Rules Hub. Объедините существующий AGENTS.md с templates/AGENTS.md. Отсутствуют: $($routeState.MissingRequiredRoutes -join ', ')." -Errors $errors -Warnings $warnings
            }
            else {
                Add-DoctorResult -Level 'WARN' -Message "AGENTS.md пока не подключает правила хаба. Объедините существующий файл с templates/AGENTS.md. Отсутствуют: $($routeState.MissingRequiredRoutes -join ', ')." -Errors $errors -Warnings $warnings
            }
        }
        else {
            Add-DoctorResult -Level 'OK' -Message 'AGENTS.md содержит стандартные маршруты AI Rules Hub.' -Errors $errors -Warnings $warnings
        }

        if (-not $routeState.ProfileRoutingPresent) {
            if ($pinned) {
                Add-DoctorResult -Level 'ERROR' -Message "Закреплённый проект не подключает выбранные профили AI Rules Hub. Выбраны: $($selectedProfiles -join ', '). Объедините существующий AGENTS.md с templates/AGENTS.md." -Errors $errors -Warnings $warnings
            }
            else {
                Add-DoctorResult -Level 'WARN' -Message 'AGENTS.md пока не подключает выбранные профили AI Rules Hub. Объедините существующий файл с templates/AGENTS.md.' -Errors $errors -Warnings $warnings
            }
        }
        elseif ($routeState.ProfileRoutingRequired) {
            Add-DoctorResult -Level 'OK' -Message 'AGENTS.md подключает все выбранные профили AI Rules Hub.' -Errors $errors -Warnings $warnings
        }

        foreach ($route in $routeState.RequiredRoutes) {
            if (-not $agentsContent.Contains($route)) {
                continue
            }
            $targetPath = Join-Path $ResolvedProjectRoot $route
            if (Test-Path -LiteralPath $targetPath) {
                continue
            }
            if ($route -eq '.ai-rules/upstream/CORE.md' -and -not $pinned) {
                Add-DoctorResult -Level 'WARN' -Message 'Маршрут к upstream/CORE.md станет доступен после первого update -Apply.' -Errors $errors -Warnings $warnings
            }
            else {
                Add-DoctorResult -Level 'ERROR' -Message "AGENTS.md ссылается на отсутствующий путь: $route." -Errors $errors -Warnings $warnings
            }
        }
    }

    foreach ($placeholderFile in @(
        [pscustomobject]@{ Path = $agentsPath; Template = (Join-Path $hubRoot 'templates/AGENTS.md'); Label = 'AGENTS.md' },
        [pscustomobject]@{ Path = $rulesetPath; Template = (Join-Path $hubRoot 'templates/RULESET.md'); Label = 'RULESET.md' },
        [pscustomobject]@{ Path = $projectRulesPath; Template = (Join-Path $hubRoot 'templates/PROJECT_RULES.md'); Label = 'PROJECT_RULES.md' }
    )) {
        if (-not (Test-Path -LiteralPath $placeholderFile.Path -PathType Leaf)) {
            continue
        }
        $userContent = Get-Content -LiteralPath $placeholderFile.Path -Raw -Encoding UTF8
        $remaining = @(Get-TemplatePlaceholders -TemplatePath $placeholderFile.Template | Where-Object { $userContent.Contains($_) })
        if ($remaining.Count -gt 0) {
            Add-DoctorResult -Level 'WARN' -Message "В $($placeholderFile.Label) остались placeholders: $($remaining -join ', ')." -Errors $errors -Warnings $warnings
        }
        else {
            Add-DoctorResult -Level 'OK' -Message "В $($placeholderFile.Label) нет известных placeholders." -Errors $errors -Warnings $warnings
        }
    }

    if ($manifestValid -and $selectionsValid -and (Test-Path -LiteralPath $rulesetPath -PathType Leaf)) {
        $rulesetContent = Get-Content -LiteralPath $rulesetPath -Raw -Encoding UTF8
        $rulesetResults = @(Get-AiRulesRulesetConsistencyResults -Catalog $catalog -Manifest $manifest -Content $rulesetContent)
        if ($rulesetResults.Count -eq 0) {
            Add-DoctorResult -Level 'OK' -Message 'Manifest и RULESET.md согласованы по profiles и прямым topics.' -Errors $errors -Warnings $warnings
        }
        else {
            foreach ($rulesetResult in $rulesetResults) {
                Add-DoctorResult -Level $rulesetResult.Level -Message $rulesetResult.Message -Errors $errors -Warnings $warnings
            }
        }
    }

    if ($manifestValid -and $selectionsValid) {
        $canRunPlan = $true
        if ($pinned) {
            try {
                $revisionRelation = $projectState.RevisionRelation
                switch ($revisionRelation.Relation) {
                    'ahead' {
                        $canRunPlan = $false
                        Add-DoctorResult -Level 'WARN' -Message 'Текущий checkout хаба содержит более новую revision; установленный snapshot проверен отдельно по lock.' -Errors $errors -Warnings $warnings
                    }
                    'behind' {
                        $canRunPlan = $false
                        Add-DoctorResult -Level 'WARN' -Message 'Checkout хаба старее revision проекта; update -Apply без намерения приведёт к откату.' -Errors $errors -Warnings $warnings
                    }
                    'diverged' {
                        $canRunPlan = $false
                        Add-DoctorResult -Level 'WARN' -Message 'Revision проекта и checkout хаба расходятся; проверьте ветку и историю перед обновлением.' -Errors $errors -Warnings $warnings
                    }
                    'unavailable' {
                        $canRunPlan = $false
                        Add-DoctorResult -Level 'WARN' -Message "Revision проекта недоступна локально; managed Plan пропущен, snapshot проверен по lock. $($revisionRelation.Detail)" -Errors $errors -Warnings $warnings
                    }
                }
            }
            catch {
                $canRunPlan = $false
                Add-DoctorResult -Level 'ERROR' -Message $_.Exception.Message -Errors $errors -Warnings $warnings
            }
        }
        if ($canRunPlan) {
            $syncPlan = $projectState.SyncPlan
            if (-not [string]::IsNullOrWhiteSpace($projectState.SyncPlanError)) {
                Add-DoctorResult -Level 'ERROR' -Message "Не удалось построить managed Plan: $($projectState.SyncPlanError)." -Errors $errors -Warnings $warnings
            }
            if ($null -ne $syncPlan) {
                $summary = $syncPlan.Summary
                if ($summary.Contains('conflict')) {
                    Add-DoctorResult -Level 'ERROR' -Message "Managed Plan обнаружил conflict: $($summary['conflict'])." -Errors $errors -Warnings $warnings
                }
                foreach ($pendingAction in @('add', 'update')) {
                    if ($summary.Contains($pendingAction)) {
                        if ($pinned) {
                            Add-DoctorResult -Level 'ERROR' -Message "Для текущей закреплённой revision обнаружено pending-состояние ${pendingAction}: $($summary[$pendingAction])." -Errors $errors -Warnings $warnings
                        }
                        else {
                            Add-DoctorResult -Level 'OK' -Message "Предварительный Plan: ${pendingAction}=$($summary[$pendingAction])." -Errors $errors -Warnings $warnings
                        }
                    }
                }
                foreach ($orphanAction in @('orphan', 'orphan-modified', 'orphan-missing')) {
                    if ($summary.Contains($orphanAction)) {
                        Add-DoctorResult -Level 'WARN' -Message "Managed Plan обнаружил ${orphanAction}: $($summary[$orphanAction])." -Errors $errors -Warnings $warnings
                    }
                }
                if ($summary.Contains('unchanged') -and $summary.Count -eq 1) {
                    Add-DoctorResult -Level 'OK' -Message "Managed-файлы синхронизированы: unchanged=$($summary['unchanged'])." -Errors $errors -Warnings $warnings
                }
            }
        }
    }

    Write-Host ''
    Write-Host 'Doctor проверяет целостность подключения AI Rules Hub.'
    Write-Host 'Успешный результат не означает соответствие всего проекта всем выбранным правилам.'
    Write-Host ''
    if ($errors.Count -gt 0) {
        Write-Host 'Итог: требуется исправление' -ForegroundColor Red
        return 1
    }
    if ($warnings.Count -gt 0) {
        Write-Host 'Итог: подключение работоспособно, есть предупреждения' -ForegroundColor Yellow
        return 0
    }
    Write-Host 'Итог: подключение корректно' -ForegroundColor Green
    return 0
}

function Invoke-HubDoctor {
    $failed = $false
    foreach ($step in @(
        [pscustomobject]@{ Name = 'Структура хаба'; Kind = 'script'; Path = (Join-Path $hubRoot 'scripts/check-hub.ps1') },
        [pscustomobject]@{ Name = 'Тесты tooling'; Kind = 'script'; Path = (Join-Path $hubRoot 'tests/test-tooling.ps1') },
        [pscustomobject]@{ Name = 'Проверка diff'; Kind = 'git'; Path = $null },
        [pscustomobject]@{ Name = 'Рабочее дерево'; Kind = 'status'; Path = $null }
    )) {
        Write-Host "`n== $($step.Name) =="
        if ($step.Kind -eq 'script') {
            $result = Invoke-ChildScript -ScriptPath $step.Path
            if ($result.ExitCode -ne 0) {
                $failed = $true
            }
        }
        elseif ($step.Kind -eq 'git') {
            & git -C $hubRoot diff --check
            if ($LASTEXITCODE -ne 0) {
                $failed = $true
            }
        }
        else {
            & git -C $hubRoot status --short
            if ($LASTEXITCODE -ne 0) {
                $failed = $true
            }
        }
    }
    if ($failed) {
        throw 'Проверка хаба обнаружила одну или несколько ошибок.'
    }
    Write-Host "`nПроверка хаба пройдена." -ForegroundColor Green
}

function Invoke-Update {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedProjectRoot,
        [switch]$Accept
    )

    $manifestPath = Join-Path $ResolvedProjectRoot '.ai-rules/manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Manifest подключения не найден: $manifestPath"
    }
    $manifest = Get-JsonFile -Path $manifestPath
    if ($null -eq $manifest.source -or $null -eq $manifest.source.PSObject.Properties['revision']) {
        throw 'В manifest обязательно поле source.revision; для подготовки без pinning используйте null.'
    }
    $currentRevision = $null
    if ($null -ne $manifest.source.revision) {
        $currentRevision = [string]$manifest.source.revision
    }
    $hubState = Get-AiRulesHubGitState -HubRoot $hubRoot

    Write-Host "Текущая revision проекта: $(if ([string]::IsNullOrWhiteSpace($currentRevision)) { 'не закреплена' } else { $currentRevision })"
    Write-Host "Базовая revision checkout: $($hubState.Revision)"
    Write-Host "Рабочее дерево хаба изменено: $($hubState.Dirty.ToString().ToLowerInvariant())"
    if ($hubState.Dirty) {
        Write-Host ''
        Write-Host 'ВНИМАНИЕ: рабочее дерево хаба содержит незакоммиченные изменения.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Preview построен по текущим файлам checkout и может не соответствовать'
        Write-Host 'только указанному commit SHA.'
        Write-Host ''
        Write-Host 'Применение через update -Apply заблокировано до очистки рабочего дерева.'
    }
    else {
        Write-Host "Целевая revision хаба: $($hubState.Revision)"
    }

    $planArguments = @(
        '-ProjectRoot', $ResolvedProjectRoot,
        '-Mode', 'Plan',
        '-RevisionOverride', $hubState.Revision
    )
    if ($Accept) {
        if ($hubState.Dirty) {
            throw 'Для update -Apply рабочее дерево хаба должно быть чистым.'
        }
        $planArguments += '-FailOnConflict'
    }
    Write-Host "`nПредварительный Plan:"
    $planResult = Invoke-ChildScript -ScriptPath $syncScriptPath -Arguments $planArguments -Capture
    Write-Host $planResult.Output.TrimEnd()
    if ($planResult.ExitCode -ne 0) {
        throw 'Не удалось построить update Plan; файлы проекта не изменены.'
    }

    if (-not $Accept) {
        Write-Host "`nФайлы проекта не изменены." -ForegroundColor Green
        if ($hubState.Dirty) {
            Write-Host 'Чтобы применить результат, сначала сохраните или отмените изменения хаба,'
            Write-Host 'повторно выполните preview и только затем используйте -Apply.'
        }
        else {
            Write-Host 'После проверки выполните ту же команду с -Apply, чтобы закрепить revision.'
        }
        return
    }

    $originalManifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    $temporaryManifestPath = Join-Path (Split-Path -Parent $manifestPath) "manifest.$([Guid]::NewGuid().ToString('N')).tmp"
    $manifest.source.revision = $hubState.Revision
    $manifestJson = (ConvertTo-AiRulesJson -InputObject $manifest -Depth 10) + "`n"
    try {
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temporaryManifestPath, $manifestJson, $utf8WithoutBom)
        Move-Item -LiteralPath $temporaryManifestPath -Destination $manifestPath -Force

        $applyResult = Invoke-ChildScript -ScriptPath $syncScriptPath -Arguments @(
            '-ProjectRoot', $ResolvedProjectRoot,
            '-Mode', 'Apply'
        ) -Capture
        Write-Host "`nПрименение:"
        Write-Host $applyResult.Output.TrimEnd()
        if ($applyResult.ExitCode -ne 0) {
            throw 'Применение правил завершилось ошибкой.'
        }
    }
    catch {
        [System.IO.File]::WriteAllBytes($manifestPath, $originalManifestBytes)
        throw
    }
    finally {
        if (Test-Path -LiteralPath $temporaryManifestPath) {
            Remove-Item -LiteralPath $temporaryManifestPath -Force
        }
    }

    Write-Host "`nRevision закреплена, правила применены." -ForegroundColor Green
    Write-Host "Проверьте diff: git -C `"$ResolvedProjectRoot`" diff -- .ai-rules/manifest.json .ai-rules/lock.json .ai-rules/upstream"

    Write-Host "`nПроверка подключения:"
    $doctorExitCode = Invoke-ProjectDoctor -ResolvedProjectRoot $ResolvedProjectRoot
    if ($doctorExitCode -ne 0) {
        throw 'Правила применены, но doctor обнаружил ошибку подключения. Проверьте сообщения выше и diff проекта.'
    }

    Write-Host "`nИтоговое состояние:"
    Show-Status -ResolvedProjectRoot $ResolvedProjectRoot
}

try {
    $normalizedCommand = $Command.ToLowerInvariant()
    switch ($normalizedCommand) {
        'help' {
            Write-Help
        }
        'doctor' {
            if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
                Invoke-HubDoctor
            }
            else {
                $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
                $doctorExitCode = Invoke-ProjectDoctor -ResolvedProjectRoot $resolvedProjectRoot
                if ($doctorExitCode -ne 0) {
                    exit $doctorExitCode
                }
            }
        }
        'list' {
            $catalog = Get-AiRulesCatalog -HubRoot $hubRoot
            if ([string]::IsNullOrWhiteSpace($ListTarget)) {
                throw "Для команды 'list' укажите 'profiles' или 'topics'."
            }
            switch ($ListTarget.ToLowerInvariant()) {
                'profiles' {
                    foreach ($profileProperty in $catalog.profiles.PSObject.Properties) {
                        Write-Host $profileProperty.Name
                        Write-Host "  $($profileProperty.Value.description)"
                        Write-Host "  Темы: $(@($profileProperty.Value.topics) -join ', ')"
                        Write-Host "  Файл: $($profileProperty.Value.file)"
                    }
                }
                'topics' {
                    foreach ($topicProperty in $catalog.topics.PSObject.Properties) {
                        Write-Host $topicProperty.Name
                        Write-Host "  $($topicProperty.Value.description)"
                        Write-Host "  Файл: $($topicProperty.Value.file)"
                    }
                }
                default {
                    throw "Неизвестный раздел '$ListTarget'. Используйте 'profiles' или 'topics'."
                }
            }
        }
        'prompt' {
            if ([string]::IsNullOrWhiteSpace($ListTarget) -or $ListTarget.ToLowerInvariant() -notin @('audit', 'connect')) {
                throw "Для команды 'prompt' укажите 'connect' или 'audit'."
            }
            $promptName = $ListTarget.ToLowerInvariant()
            $promptArguments = @('-Name', $promptName)
            if ($promptName -eq 'connect') {
                $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
                $promptArguments += @('-ProjectRoot', $resolvedProjectRoot)
            }
            $result = Invoke-ChildScript -ScriptPath $promptScriptPath -Arguments $promptArguments -Capture
            if ($result.ExitCode -ne 0) {
                throw "Не удалось вывести готовый запрос '$promptName'."
            }
            Write-Output $result.Output.TrimEnd()
        }
        'connect' {
            $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
            $manifestPath = Join-Path $resolvedProjectRoot '.ai-rules/manifest.json'
            $selectedProfiles = ConvertTo-AiRulesNameList -Values $Profiles
            $selectedTopics = ConvertTo-AiRulesNameList -Values $Topics

            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                if ($Apply) {
                    throw @"
Первый Plan ещё не показан. Сначала выполните connect без -Apply:

.\ai-rules.ps1 connect -ProjectRoot "$resolvedProjectRoot" -Profiles <profile>
"@
                }
                if ($selectedProfiles.Count -eq 0 -and $selectedTopics.Count -eq 0) {
                    throw 'Для нового проекта укажите хотя бы один -Profiles или -Topics. AI-агент может подобрать набор через prompt connect.'
                }

                $catalog = Get-AiRulesCatalog -HubRoot $hubRoot
                Assert-AiRulesSelections -Catalog $catalog -SelectedProfiles $selectedProfiles -SelectedTopics $selectedTopics
                $initArguments = @('-ProjectRoot', $resolvedProjectRoot, '-SeedProjectFiles')
                if ($selectedProfiles.Count -gt 0) {
                    $initArguments += @('-Profiles', ($selectedProfiles -join ','))
                }
                if ($selectedTopics.Count -gt 0) {
                    $initArguments += @('-Topics', ($selectedTopics -join ','))
                }
                if ($NoSeedProjectFiles) {
                    $initArguments = @($initArguments | Where-Object { $_ -ne '-SeedProjectFiles' })
                }

                Write-Host 'Подготовка локального слоя проекта:'
                $initResult = Invoke-ChildScript -ScriptPath $initScriptPath -Arguments $initArguments
                if ($initResult.ExitCode -ne 0) {
                    throw 'Подготовка проекта завершилась ошибкой.'
                }
                Write-Host "`nЛокальный слой подготовлен. Теперь показан первый Plan; managed-файлы ещё не применяются."
            }
            else {
                if ($NoSeedProjectFiles) {
                    throw '-NoSeedProjectFiles применяется только при первой подготовке проекта.'
                }
                if ($selectedProfiles.Count -gt 0 -or $selectedTopics.Count -gt 0) {
                    $manifest = Get-JsonFile -Path $manifestPath
                    $manifestProfiles = @($manifest.profiles | ForEach-Object { [string]$_ } | Sort-Object)
                    $manifestTopics = @($manifest.topics | ForEach-Object { [string]$_ } | Sort-Object)
                    $requestedProfiles = @($selectedProfiles | Sort-Object)
                    $requestedTopics = @($selectedTopics | Sort-Object)
                    if (($manifestProfiles -join ',') -ne ($requestedProfiles -join ',') -or ($manifestTopics -join ',') -ne ($requestedTopics -join ',')) {
                        throw 'Проект уже инициализирован, а переданный состав отличается от manifest. Изменяйте состав явно в project-owned файлах.'
                    }
                }
            }

            Invoke-Update -ResolvedProjectRoot $resolvedProjectRoot -Accept:$Apply
        }
        'init' {
            $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
            $catalog = Get-AiRulesCatalog -HubRoot $hubRoot
            $selectedProfiles = ConvertTo-AiRulesNameList -Values $Profiles
            $selectedTopics = ConvertTo-AiRulesNameList -Values $Topics
            Assert-AiRulesSelections -Catalog $catalog -SelectedProfiles $selectedProfiles -SelectedTopics $selectedTopics
            $arguments = @('-ProjectRoot', $resolvedProjectRoot)
            if ($selectedProfiles.Count -gt 0) {
                $arguments += '-Profiles'
                $arguments += ($selectedProfiles -join ',')
            }
            if ($selectedTopics.Count -gt 0) {
                $arguments += '-Topics'
                $arguments += ($selectedTopics -join ',')
            }
            if (-not $NoSeedProjectFiles) {
                $arguments += '-SeedProjectFiles'
            }
            $result = Invoke-ChildScript -ScriptPath $initScriptPath -Arguments $arguments
            if ($result.ExitCode -ne 0) {
                throw 'Инициализация проекта завершилась ошибкой.'
            }
            Write-Host "`nПроект инициализирован." -ForegroundColor Green
            Write-Host 'Подключение подготовлено.'
            Write-Host 'Следующий шаг ограничен AGENTS.md, RULESET.md и PROJECT_RULES.md.'
            Write-Host 'Не исправляйте код, документацию, CI, лицензию или настройки проекта'
            Write-Host 'в рамках подключения. Обнаруженные разрывы зафиксируйте отдельно.'
            Write-Host "`nПеред первым применением:"
            Write-Host ''
            Write-Host '1. Просмотрите первое применение:'
            Write-Host "   .\ai-rules.ps1 update -ProjectRoot `"$resolvedProjectRoot`""
            Write-Host '2. Примените закреплённую revision:'
            Write-Host "   .\ai-rules.ps1 update -ProjectRoot `"$resolvedProjectRoot`" -Apply"
            Write-Host '3. Откройте целевой проект в AI-агенте и используйте запрос:'
            Write-Host '   .\ai-rules.ps1 prompt audit'
            Write-Host '   Общие правила переносить вручную не нужно.'
        }
        'plan' {
            $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
            $manifestRevision = Get-ManifestRevision -ResolvedProjectRoot $resolvedProjectRoot
            $planArguments = @('-ProjectRoot', $resolvedProjectRoot, '-Mode', 'Plan')
            if ([string]::IsNullOrWhiteSpace($manifestRevision)) {
                $planArguments += '-SuppressNextStep'
            }
            $result = Invoke-ChildScript -ScriptPath $syncScriptPath -Arguments $planArguments -Capture
            $planOutput = $result.Output
            Write-Host $planOutput.TrimEnd()
            if ($result.ExitCode -ne 0) {
                throw 'Не удалось построить sync Plan.'
            }
            if ([string]::IsNullOrWhiteSpace($manifestRevision)) {
                Write-Host "`nManifest пока не закреплён за revision."
                Write-Host 'Этот Plan является предварительным.'
                Write-Host "`nДля первого воспроизводимого применения используйте:"
                Write-Host ".\ai-rules.ps1 update -ProjectRoot `"$resolvedProjectRoot`" -Apply"
            }
        }
        'apply' {
            $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
            $manifestRevision = Get-ManifestRevision -ResolvedProjectRoot $resolvedProjectRoot
            if ([string]::IsNullOrWhiteSpace($manifestRevision)) {
                throw @"
Проект ещё не закреплён за версией хаба.
Для первого применения выполните:

.\ai-rules.ps1 update -ProjectRoot "$resolvedProjectRoot"
.\ai-rules.ps1 update -ProjectRoot "$resolvedProjectRoot" -Apply
"@
            }
            $result = Invoke-ChildScript -ScriptPath $syncScriptPath -Arguments @('-ProjectRoot', $resolvedProjectRoot, '-Mode', 'Apply')
            if ($result.ExitCode -ne 0) {
                throw 'Применение правил завершилось ошибкой.'
            }
        }
        'status' {
            $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
            Show-Status -ResolvedProjectRoot $resolvedProjectRoot
        }
        'update' {
            $resolvedProjectRoot = Resolve-ProjectRoot -Path $ProjectRoot
            Invoke-Update -ResolvedProjectRoot $resolvedProjectRoot -Accept:$Apply
        }
        default {
            throw "Неизвестная команда '$Command'. Выполните '.\ai-rules.ps1 help'."
        }
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

exit 0

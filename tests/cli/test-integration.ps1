[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$powershellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$tempRoot = Join-Path $tempBase "ai-rules-hub-tests-$([Guid]::NewGuid().ToString('N'))"
$assertionCount = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
    $script:assertionCount++
}

function Get-NormalizedSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $content = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8WithoutBom.GetBytes($content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($bytes)
        return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return '<missing>'
    }

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
    return (@(
        Get-ChildItem -LiteralPath $rootFull -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($rootFull.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
                "$relativePath|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
            }
    ) -join "`n")
}

function Invoke-HubScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $captureId = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $tempRoot "hub-script-$captureId.stdout"
    $stderrPath = Join-Path $tempRoot "hub-script-$captureId.stderr"
    try {
        & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 1> $stdoutPath 2> $stderrPath
        $exitCode = $LASTEXITCODE
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { [System.IO.File]::ReadAllText($stdoutPath) } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [System.IO.File]::ReadAllText($stderrPath) } else { '' }
        $output = $stdout + $stderr
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $documentationRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/DOCUMENTATION.md') -Raw -Encoding UTF8
    $coreRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/CORE.md') -Raw -Encoding UTF8
    $architectureRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/ARCHITECTURE_AND_DATA.md') -Raw -Encoding UTF8
    $productRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/PRODUCT.md') -Raw -Encoding UTF8
    $projectStudyRule = Get-Content -LiteralPath (Join-Path $hubRoot 'workflows/PROJECT_STUDY.md') -Raw -Encoding UTF8
    $reliabilityRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/RELIABILITY_AND_OPERATIONS.md') -Raw -Encoding UTF8
    $rulesReadme = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/README.md') -Raw -Encoding UTF8
    $agentsTemplate = Get-Content -LiteralPath (Join-Path $hubRoot 'templates/AGENTS.md') -Raw -Encoding UTF8
    $projectRulesTemplate = Get-Content -LiteralPath (Join-Path $hubRoot 'templates/PROJECT_RULES.md') -Raw -Encoding UTF8
    $fullProjectRulesTemplate = Get-Content -LiteralPath (Join-Path $hubRoot 'templates/PROJECT_RULES.full.md') -Raw -Encoding UTF8
    $rulesetTemplate = Get-Content -LiteralPath (Join-Path $hubRoot 'templates/RULESET.md') -Raw -Encoding UTF8
    $profilesReadme = Get-Content -LiteralPath (Join-Path $hubRoot 'profiles/README.md') -Raw -Encoding UTF8
    $publicRepositoryProfile = Get-Content -LiteralPath (Join-Path $hubRoot 'profiles/public-repository.md') -Raw -Encoding UTF8
    $aiCollaborationRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/AI_COLLABORATION.md') -Raw -Encoding UTF8
    $projectConnectPrompt = Get-Content -LiteralPath (Join-Path $hubRoot 'workflows/PROJECT_CONNECT_PROMPT.md') -Raw -Encoding UTF8
    $projectAuditPrompt = Get-Content -LiteralPath (Join-Path $hubRoot 'workflows/PROJECT_AUDIT_PROMPT.md') -Raw -Encoding UTF8
    $rootReadme = Get-Content -LiteralPath (Join-Path $hubRoot 'README.md') -Raw -Encoding UTF8
    $templatesReadme = Get-Content -LiteralPath (Join-Path $hubRoot 'templates/README.md') -Raw -Encoding UTF8
    $profileFiles = Get-ChildItem -LiteralPath (Join-Path $hubRoot 'profiles') -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' }
    $standardProductProfile = Get-Content -LiteralPath (Join-Path $hubRoot 'profiles/standard-product.md') -Raw -Encoding UTF8
    $dataSensitiveProfile = Get-Content -LiteralPath (Join-Path $hubRoot 'profiles/data-sensitive.md') -Raw -Encoding UTF8
    $securityRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/SECURITY_AND_PRIVACY.md') -Raw -Encoding UTF8
    $researchRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/RESEARCH_AND_EVIDENCE.md') -Raw -Encoding UTF8
    $deliveryRule = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/GIT_AND_DELIVERY.md') -Raw -Encoding UTF8
    $hubProjectRules = Get-Content -LiteralPath (Join-Path $hubRoot 'hub/PROJECT_RULES.md') -Raw -Encoding UTF8
    $validationWorkflow = Get-Content -LiteralPath (Join-Path $hubRoot '.github/workflows/validate.yml') -Raw -Encoding UTF8
    $hubCheck = Get-Content -LiteralPath (Join-Path $hubRoot 'scripts/check-hub.ps1') -Raw -Encoding UTF8
    $catalog = Get-Content -LiteralPath (Join-Path $hubRoot 'sync/catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    $crlfHubRoot = Join-Path $tempRoot 'crlf hub fixture'
    foreach ($trackedPath in @(& git -C $hubRoot ls-files --cached --others --exclude-standard)) {
        $sourcePath = Join-Path $hubRoot $trackedPath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            continue
        }
        $targetPath = Join-Path $crlfHubRoot $trackedPath
        $targetDirectory = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    }
    $crlfGitignorePath = Join-Path $crlfHubRoot '.gitignore'
    $crlfGitignore = [System.IO.File]::ReadAllText($crlfGitignorePath).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($crlfGitignorePath, $crlfGitignore, (New-Object System.Text.UTF8Encoding($false)))
    $crlfHubCheck = Invoke-HubScript -ScriptPath (Join-Path $crlfHubRoot 'scripts/check-hub.ps1')
    Assert-True -Condition ($crlfHubCheck.ExitCode -eq 0) -Message "hub validation must accept a clean Windows checkout: $($crlfHubCheck.Output)"
    Add-Content -LiteralPath (Join-Path $crlfHubRoot 'README.md') -Value "`nСлучайный tooling в русском тексте." -Encoding UTF8
    $mixedLanguageCheck = Invoke-HubScript -ScriptPath (Join-Path $crlfHubRoot 'scripts/check-hub.ps1')
    Assert-True -Condition ($mixedLanguageCheck.ExitCode -ne 0 -and $mixedLanguageCheck.Output -match 'Смешение языков.*README\.md') -Message 'hub validation must reject common accidental English words in Russian prose'

    foreach ($auditConcept in @('перечень', 'классификация', 'канонического источника', 'оставить/объединить/перенести/архивировать/удалить', 'согласование', 'изменение', 'проверка ссылок', 'сохранности информации')) {
        Assert-True -Condition ($documentationRule.Contains($auditConcept)) -Message "documentation audit must cover: $auditConcept"
    }
    $rulesetIndex = $agentsTemplate.IndexOf('.ai-rules/RULESET.md')
    $projectRulesIndex = $agentsTemplate.IndexOf('.ai-rules/PROJECT_RULES.md')
    $coreIndex = $agentsTemplate.IndexOf('.ai-rules/upstream/CORE.md')
    $profilesIndex = $agentsTemplate.IndexOf('.ai-rules/upstream/profiles/')
    $topicsIndex = $agentsTemplate.IndexOf('.ai-rules/upstream/rules/')
    Assert-True -Condition ($rulesetIndex -ge 0 -and $rulesetIndex -lt $projectRulesIndex -and $projectRulesIndex -lt $coreIndex -and $coreIndex -lt $profilesIndex -and $profilesIndex -lt $topicsIndex) -Message 'agent template must route RULESET, project rules, core, profiles, then task topics'
    Assert-True -Condition ($agentsTemplate -match 'не весь `upstream/`' -and $agentsTemplate -match 'workflows/PROJECT_STUDY\.md.*явном выборе') -Message 'agent template must forbid whole-upstream reading and route project-study explicitly'
    Assert-True -Condition ($agentsTemplate -match 'средняя или большая задача.*AI_COLLABORATION\.md' -and $agentsTemplate -match 'до плана и реализации') -Message 'agent template must load selected collaboration rules before significant task decisions'
    Assert-True -Condition ($agentsTemplate -match 'Подключение хаба разрешает менять только' -and $agentsTemplate -match 'не разрешает менять несвязанные код, документацию, CI, лицензию или настройки' -and $agentsTemplate -match 'зафиксируй в `RULESET\.md`') -Message 'agent template must provide a scope firewall for hub adoption'
    Assert-True -Condition ($agentsTemplate -match 'читателя.*задачу.*хранения в Git.*публикации' -and $agentsTemplate -match 'канонического документа' -and $agentsTemplate -match 'минимальный локальный каталог') -Message 'agent template must route new documents through audience, purpose, storage, publication, and canonical-source decisions'
    Assert-True -Condition (([regex]::Matches($projectRulesTemplate, '(?m)^## ')).Count -eq 7 -and $projectRulesTemplate.Length -lt 2500 -and $projectRulesTemplate -notmatch '\|.*\|.*\|') -Message 'default project rules template must stay minimal'
    Assert-True -Condition ($fullProjectRulesTemplate -match 'docs/README\.md' -and $fullProjectRulesTemplate -match '\|.*\|.*\|') -Message 'full project rules template must retain detailed routing content'
    foreach ($projectTemplate in @($projectRulesTemplate, $fullProjectRulesTemplate)) {
        Assert-True -Condition ($projectTemplate -match 'не установлен' -and $projectTemplate -match 'не установлена' -and $projectTemplate -match 'Не создавай документацию, инструменты или CI' -and $projectTemplate -match 'RULESET\.md') -Message 'project rules templates must describe missing sources without creating them during adoption'
        Assert-True -Condition ($projectTemplate -match 'Публичная документация' -and $projectTemplate -match 'Локальная или закрытая документация' -and $projectTemplate -match 'Критерий публикации') -Message 'project rules templates must support an explicit documentation boundary'
        Assert-True -Condition ($projectTemplate -notmatch 'ROADMAP\.md|BACKLOG\.md|decisions/') -Message 'project rules templates must not require public planning or decision-log files'
    }
    Assert-True -Condition ($rulesetTemplate -notmatch 'ROADMAP\.md|BACKLOG\.md|decisions/') -Message 'RULESET template must not require public planning or decision-log files'
    Assert-True -Condition ($projectRulesTemplate -notmatch 'Специальная аудитория и терминология' -and $fullProjectRulesTemplate -match 'Специальная аудитория и терминология.*не требуется') -Message 'special terminology must stay optional and only in the full project rules template'
    Assert-True -Condition ($rulesetTemplate -match 'не локальное исключение' -and $rulesetTemplate -match 'не разрешение на исправление' -and $rulesetTemplate -match 'правило.*наблюдаемое несоответствие.*подтверждение.*риск.*условие возврата' -and $rulesetTemplate -match 'неизвестно') -Message 'RULESET deferred gaps must remain decision records, not permission to fix'
    Assert-True -Condition ($profilesReadme -match 'новым и изменяемым файлам' -and $profilesReadme -match 'внешним действием.*обязательной проверкой' -and $profilesReadme -match 'не разрешает аудит всего репозитория') -Message 'profile guidance must be prospective and action-gated'
    Assert-True -Condition ($publicRepositoryProfile -match '(?m)^### Постоянные инварианты\s*$' -and $publicRepositoryProfile -match '(?m)^### Гейты внешнего действия\s*$' -and $publicRepositoryProfile -match 'Существующие несоответствия.*разрывами внедрения' -and $publicRepositoryProfile -match 'LICENSE.*CONTRIBUTING.*правил безопасности') -Message 'public profile must separate ongoing invariants, external-action gates, and adoption gaps'
    Assert-True -Condition ($publicRepositoryProfile -match 'аудиторию.*назначение.*необходимость' -and $publicRepositoryProfile -match 'PROJECT_STUDY.*не является разрешением публикации') -Message 'public profile must gate documentation publication without duplicating the internal-document catalog'
    Assert-True -Condition ($publicRepositoryProfile -match 'не внутреннее происхождение правил' -and $publicRepositoryProfile -match 'авторстве, лицензии и правах распространения') -Message 'public profile must omit internal rule provenance while preserving required attribution'
    Assert-True -Condition ($documentationRule -match 'маршрутов.*не является.*полной ревизией' -and $documentationRule -match 'ревизия не даёт разрешения исправлять' -and $documentationRule -match 'выбор темы документации не запускает полный перечень') -Message 'documentation routing and review must not authorize fixes'
    Assert-True -Condition ($documentationRule -match '(?m)^## Аудитория и граница публикации\s*$' -and $documentationRule -match 'публичный / внутренний в Git / локальный' -and $documentationRule -match 'явно названной внешней аудитории') -Message 'documentation rule must be the canonical audience and publication boundary'
    Assert-True -Condition ($documentationRule -match 'сложность текста.*знаниям читателя' -and $documentationRule -match 'главный вывод до подробностей' -and $documentationRule -match 'сказать то же проще.*без потери смысла') -Message 'documentation must adapt complexity to the reader and preserve meaning while simplifying'
    Assert-True -Condition ($aiCollaborationRule -notmatch 'В фазе подключения|первичн.{0,20}аудит' -and $agentsTemplate -match 'Подключение хаба разрешает менять только.*AGENTS\.md.*локальные файлы.*\.ai-rules') -Message 'hub adoption boundaries must stay in the project entry-point template, not the portable AI collaboration rule'
    Assert-True -Condition ($aiCollaborationRule -match '(?m)^## Улучшение системы после ошибок\s*$' -and $aiCollaborationRule -match 'единичной.*повторяющийся класс сбоев' -and $aiCollaborationRule -match 'самую узкую достаточную меру' -and $aiCollaborationRule -match 'Не расширяй постоянно загружаемые инструкции' -and $aiCollaborationRule -match 'не требует обязательного журнала') -Message 'AI collaboration must turn repeated failures into the narrowest verified system improvement without growing mandatory context from single cases'
    Assert-True -Condition ($aiCollaborationRule -match '(?m)^## Самостоятельное решение и уточнение\s*$' -and $aiCollaborationRule -match 'критерий готовности.*наблюдаемый результат.*способ проверки' -and $aiCollaborationRule -match 'границы полномочий.*данные.*совместимость.*публичное поведение.*обратимость' -and $aiCollaborationRule -match 'один конкретный вопрос' -and $aiCollaborationRule -match 'низкорискового и обратимого решения.*продолжай') -Message 'AI collaboration must distinguish safe autonomy from decision checkpoints without requiring approval for every implementation detail'
    Assert-True -Condition ($aiCollaborationRule -match 'повторившейся ошибке.*канонический источник.*маршрут до точки решения.*применяемая версия.*наблюдаемая проверка' -and $aiCollaborationRule -match 'Одна запись правила.*не считается завершённым исправлением') -Message 'AI collaboration must verify the full delivery path for protections against repeated failures'
    Assert-True -Condition ($hubProjectRules -match 'путь применения.*до решения или действия' -and $hubProjectRules -match 'маршрут приводит к правилу до решения или действия') -Message 'hub rule filter and readiness criteria must verify that guidance arrives before the affected decision'
    Assert-True -Condition ($aiCollaborationRule -notmatch 'Sol|Terra|Luna|Текущее сопоставление моделей|рекомендуемую модель|усилие рассуждения|модельный пул') -Message 'AI collaboration must not prescribe model selection'
    Assert-True -Condition ($hubProjectRules -match '\.\./profiles/public-repository\.md' -and $hubProjectRules -match 'Публичная модель участия управляется владельцем') -Message 'hub project rules must apply the public repository profile explicitly'
    Assert-True -Condition ($securityRule -match 'Задачи' -and $securityRule -match 'изменения `AGENTS\.md`' -and $securityRule -match 'Принятый локальный `AGENTS\.md`.*установленной цепочки правил' -and $securityRule -match 'контекст подключённого сервиса') -Message 'security rule must distinguish untrusted incoming instructions from the established local instruction chain'
    Assert-True -Condition ($securityRule -match 'недоверенный источник.*контекст или память.*решение агента.*инструмент' -and $securityRule -match 'минимальные права.*одну задачу.*короткий срок' -and $securityRule -match 'вне модели' -and $securityRule -match 'долговременную память' -and $securityRule -match 'MCP') -Message 'security rule must cover agent source-to-impact paths, least privilege, deterministic gates, memory, and tool supply chain'
    Assert-True -Condition ($securityRule -match 'необратимым или высокорисковым действием' -and $securityRule -match 'ещё не охвачено его запросом или согласованным планом' -and $securityRule -match 'изменились объект, получатель, передаваемые данные, область или последствия') -Message 'security approval must be risk-based, respect an already approved exact plan, and require renewed approval when scope changes'
    Assert-True -Condition ($deliveryRule -match '(?m)^## Цепочка поставки\s*$' -and $deliveryRule -match 'граф зависимостей' -and $deliveryRule -match 'Публикуемый артефакт' -and $deliveryRule -match 'пропорциональ') -Message 'delivery rule must structurally cover dependencies, published artifacts, and proportional supply-chain safeguards'
    Assert-True -Condition ($validationWorkflow -match '(?m)^permissions:\s*\r?\n\s+contents:\s*read\s*$' -and $validationWorkflow -match 'actions/checkout@[0-9a-f]{40}' -and $validationWorkflow -match 'persist-credentials:\s*false') -Message 'validation workflow must be read-only and use pinned checkout without persisted credentials'
    Assert-True -Condition ((Test-Path -LiteralPath (Join-Path $hubRoot 'CONTRIBUTING.md')) -and (Test-Path -LiteralPath (Join-Path $hubRoot '.github/SECURITY.md'))) -Message 'public repository entry points must exist'
    Assert-True -Condition ($hubCheck -match 'LICENSE\.md' -and $hubCheck -match 'GitHub-discoverable CONTRIBUTING' -and $hubCheck -match 'workflows/PROJECT_CONNECT_PROMPT\.md' -and $hubCheck -match 'workflows/PROJECT_AUDIT_PROMPT\.md' -and $hubCheck -match 'full 40-character commit SHA' -and $hubCheck -match 'undesiredEnglishProse') -Message 'hub check must enforce public repository hygiene, onboarding workflows, and one-language prose'
    Assert-True -Condition ($hubCheck -match 'hub/BACKLOG\.md' -and $hubCheck -match "'hub/decisions'" -and $hubCheck -match '\.local-docs/') -Message 'hub check must reject owner-only public documents and require an ignored local location'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $hubRoot 'hub/BACKLOG.md')) -and -not (Test-Path -LiteralPath (Join-Path $hubRoot 'hub/decisions'))) -Message 'owner backlog and decision history must not remain public'
    foreach ($topicProperty in $catalog.topics.PSObject.Properties) {
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$topicProperty.Value.file) -and -not [string]::IsNullOrWhiteSpace([string]$topicProperty.Value.description)) -Message "catalog topic '$($topicProperty.Name)' must have file and description"
    }
    Assert-True -Condition ($catalog.schemaVersion -eq '0.1' -and $catalog.topics.'reliability-and-operations'.file -eq 'rules/RELIABILITY_AND_OPERATIONS.md' -and -not [string]::IsNullOrWhiteSpace([string]$catalog.topics.'reliability-and-operations'.description)) -Message 'catalog schema must stay 0.1 and include the stable reliability topic with a description'
    Assert-True -Condition ($null -eq $catalog.topics.PSObject.Properties['language'] -and $null -eq $catalog.topics.PSObject.Properties['plain-language']) -Message 'plain language must not require a separate catalog topic'
    Assert-True -Condition ($rulesReadme -match 'CORE\.md.*обязателен для каждого подключённого проекта' -and $rulesReadme -match 'RELIABILITY_AND_OPERATIONS\.md' -and $rulesReadme -match 'Рабочие процессы конкретных задач') -Message 'rules index must keep CORE mandatory and route task workflows separately'
    foreach ($profileProperty in $catalog.profiles.PSObject.Properties) {
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$profileProperty.Value.description) -and -not [string]::IsNullOrWhiteSpace([string]$profileProperty.Value.file) -and @($profileProperty.Value.topics).Count -gt 0) -Message "catalog profile '$($profileProperty.Name)' must define description, source file, and topic composition"
        $profileContent = Get-Content -LiteralPath (Join-Path $hubRoot ([string]$profileProperty.Value.file)) -Raw -Encoding UTF8
        Assert-True -Condition ($profileContent -match '(?m)^## Назначение\s*$' -and $profileContent -match '(?m)^## Уникальные обязательства\s*$') -Message "profile '$($profileProperty.Name)' must contain purpose and unique obligations"
        Assert-True -Condition ($profileContent -notmatch '(?m)^##? Подключить' -and $profileContent -notmatch '\.\./rules/') -Message "profile '$($profileProperty.Name)' must not duplicate catalog composition"
        Assert-True -Condition ($profileContent -notmatch 'профессионального звучания|короткими прямыми предложениями') -Message "profile '$($profileProperty.Name)' must not duplicate the plain-language rule from CORE"
    }
    Assert-True -Condition (@($profileFiles).Count -eq @($catalog.profiles.PSObject.Properties).Count) -Message 'every profile file must be represented in the catalog'
    $catalogProfileFiles = @($catalog.profiles.PSObject.Properties | ForEach-Object { ([string]$_.Value.file).Replace('\', '/') } | Sort-Object)
    $diskProfileFiles = @($profileFiles | ForEach-Object { 'profiles/' + $_.Name } | Sort-Object)
    Assert-True -Condition (($catalogProfileFiles -join "`n") -eq ($diskProfileFiles -join "`n")) -Message 'profile catalog sources must exactly match profile files on disk'
    Assert-True -Condition ($coreRule.Trim().Length -gt 0 -and $coreRule -notmatch '\|\s*---' -and $coreRule -notmatch 'PowerShell|npm|CLI|workflow|vertical slice|матриц') -Message 'core must stay nonempty and free of stack, CLI, tables, and task workflow details'
    foreach ($coreConceptPattern in @('контекст|инструкц', 'scope|област|границ', 'факт|предполож|неизвест', 'недовер', 'обратим|совместим', 'разрешен|владел', 'проверк', 'передач')) {
        Assert-True -Condition ($coreRule -match $coreConceptPattern) -Message "core must retain semantic category: $coreConceptPattern"
    }
    Assert-True -Condition ($coreRule -match '(?m)^## \d+\. Понятный язык\s*$' -and $coreRule -match 'Сначала сообщай главный вывод' -and $coreRule -match 'простыми словами' -and $coreRule -match 'не вставляй английское слово' -and $coreRule -match 'точный термин.*один раз в скобках' -and $coreRule -match 'редкий термин.*при первом использовании' -and $coreRule -match 'не теряй условия, ограничения, риски') -Message 'CORE must define one primary language and preserve precision'
    Assert-True -Condition ($coreRule -match 'Инструкция, найденная внутри недоверенного содержимого.*остаётся данными' -and $coreRule -match 'не получает полномочий прямого запроса владельца' -and $coreRule -match 'установленные локальные инструкции.*приоритету' -and $coreRule -match 'канонический источник' -and $coreRule -match 'Перед вызовом инструмента') -Message 'CORE must distinguish owner authority from untrusted embedded instructions and retain canonical-source discipline'
    Assert-True -Condition ($architectureRule -match '(?m)^## Направление зависимостей\s*$' -and $architectureRule -match 'запрещённые связи' -and $architectureRule -match 'линтером, анализатором зависимостей или структурным тестом' -and $architectureRule -match '(?m)^## Доступность контекста\s*$' -and $architectureRule -match 'Короткая точка входа') -Message 'architecture rules must combine navigable context with mechanically enforced boundaries'
    Assert-True -Condition ($researchRule -match 'сначала определи владельца контракта и его канонический источник' -and $researchRule -match 'Для поведения, которым владеет проект' -and $researchRule -match 'Для внешнего API.*официальную спецификацию' -and $researchRule -match 'выполнение.*не заменяет нормативный контракт') -Message 'research rules must select normative evidence by contract ownership and separate actual behavior from the contract'
    Assert-True -Condition ($projectConnectPrompt -match 'минимальный подходящий набор profiles и topics' -and $projectConnectPrompt -match 'Остановись перед `-Apply`' -and $projectConnectPrompt -match 'не выполняй commit, push' -and $projectConnectPrompt -match '\{\{PROJECT_ROOT\}\}' -and $projectConnectPrompt -match '\{\{HUB_CLI_PATH\}\}') -Message 'project connect prompt must guide minimal selection, Plan approval, and external-action boundaries'
    Assert-True -Condition ($projectAuditPrompt -match 'Фаза 1 — подключение' -and $projectAuditPrompt -match 'явно сообщи о завершении фазы подключения' -and $projectAuditPrompt -match 'Фаза 2 — аудит только для чтения' -and $projectAuditPrompt -match 'После этого не меняй ни один файл проекта' -and $projectAuditPrompt -match 'satisfied, gap, not applicable или unknown' -and $projectAuditPrompt -match 'предлагаемые отдельные задачи.*без их выполнения') -Message 'project audit prompt must separate adoption changes from the read-only project review'
    Assert-True -Condition ($projectAuditPrompt -match 'парные или похожие сценарии' -and $projectAuditPrompt -match 'один вариант без другого' -and $projectAuditPrompt -match 'путь нового разработчика' -and $projectAuditPrompt -match 'Размер файла считай сигналом' -and $projectAuditPrompt -match 'сгруппированные по классу') -Message 'project audit prompt must compare analogous scenarios, assess human onboarding, and group repeated gaps by system layer'
    Assert-True -Condition ($rootReadme -match 'prompt connect' -and $rootReadme -match 'workflows/PROJECT_AUDIT_PROMPT\.md' -and $rootReadme -match 'Shared rules do not need to be copied manually' -and $templatesReadme -match 'workflows/PROJECT_CONNECT_PROMPT\.md' -and $templatesReadme -match 'workflows/PROJECT_AUDIT_PROMPT\.md') -Message 'onboarding docs must lead with agent-assisted connection and keep workflows separate from templates'
    $topicLengths = @($catalog.topics.PSObject.Properties | ForEach-Object { (Get-Content -LiteralPath (Join-Path $hubRoot ([string]$_.Value.file)) -Raw -Encoding UTF8).Length })
    Assert-True -Condition ($coreRule.Length -lt (($topicLengths | Measure-Object -Maximum).Maximum) -and $coreRule.Length -lt (($topicLengths | Measure-Object -Sum).Sum / 3)) -Message 'core must remain compact relative to thematic rules'
    Assert-True -Condition ($projectStudyRule -match 'учебных документов' -and $projectStudyRule -match 'Исходный код.*конфигурация.*история Git.*только для чтения' -and $projectStudyRule -match 'факт.*вероятный вывод.*неизвестное.*оценка' -and $projectStudyRule -match 'язык следует локальным правилам или запросу') -Message 'project-study must limit writes to study documents and distinguish confirmation statuses without a universal language'
    Assert-True -Condition ($projectStudyRule -match 'по умолчанию локальна' -and $projectStudyRule -match 'явно названной внешней аудитории' -and $projectStudyRule -match 'не требует публиковать обзор проекта' -and $projectStudyRule -match 'не требует отдельного файла') -Message 'project-study must keep results local unless an external audience and benefit justify publication'
    Assert-True -Condition ($projectStudyRule -notmatch '\.project-study/|public-docs/|docs/project-study' -and $projectStudyRule -notmatch '13' -and $projectStudyRule -notmatch '(?m)^```') -Message 'project-study must not impose a public folder, fixed file count, or long prompt templates'
    foreach ($reliabilityHeading in @('Работоспособность', 'Деградация', 'Наблюдаемость', 'Жизнеспособность и готовность', 'Восстановление и инциденты', 'Производительность и предельная нагрузка', 'Область применения')) {
        Assert-True -Condition ($reliabilityRule -match ('(?m)^## ' + [regex]::Escape($reliabilityHeading) + '\s*$')) -Message "reliability topic must retain section: $reliabilityHeading"
    }
    Assert-True -Condition ('reliability-and-operations' -notin @($catalog.profiles.'standard-product'.topics)) -Message 'standard-product must not include reliability by default'
    Assert-True -Condition ('security-and-privacy' -in @($catalog.profiles.'standard-product'.topics) -and 'security-and-privacy' -in @($catalog.profiles.'research-driven'.topics)) -Message 'standard and research profiles must make the full AI security rule available when relevant'
    Assert-True -Condition ($standardProductProfile -match 'проверяемый пользовательский, эксплуатационный или защитный результат' -and $standardProductProfile -match 'Инфраструктурная работа допустима отдельно') -Message 'standard-product must allow independently verifiable infrastructure and protective outcomes'
    Assert-True -Condition ($dataSensitiveProfile -match 'модел[ьи] удаления' -and $dataSensitiveProfile -match 'Срок хранения' -and $dataSensitiveProfile -match 'резервных копий' -and $dataSensitiveProfile -match 'Если система раскрывает публичное представление' -and $dataSensitiveProfile -match 'Если используется предрабочая среда') -Message 'data-sensitive must cover deletion and retention while making public projection and staging conditional'
    Assert-True -Condition ($productRule -match 'основной способ ввода платформы' -and $productRule -match 'web/desktop.*клавиатур' -and $productRule -match 'фокус видим, не перекрыт') -Message 'product accessibility must cover platform input, web/desktop keyboard access, and unobscured focus'
    Assert-True -Condition ($productRule -match 'слова пользователя' -and $productRule -match 'что не получилось.*что сохранилось.*что можно сделать дальше' -and $productRule -match 'доменная терминология.*целевой аудитории') -Message 'product language must use user vocabulary, actionable errors, and justified domain terms'

    $cliPath = Join-Path $hubRoot 'ai-rules.ps1'
    $helpResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('help')
    Assert-True -Condition ($helpResult.ExitCode -eq 0 -and $helpResult.Output -match 'git pull' -and $helpResult.Output -match 'git fetch') -Message 'CLI help must pass and explain the no-fetch boundary'
    $auditPromptResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('prompt', 'audit')
    Assert-True -Condition ($auditPromptResult.ExitCode -eq 0 -and $auditPromptResult.Output -match '^Заверши подключение AI Rules Hub' -and $auditPromptResult.Output -match 'Фаза 1 — подключение' -and $auditPromptResult.Output -match 'Фаза 2 — аудит только для чтения' -and $auditPromptResult.Output -notmatch '```') -Message 'CLI must print the reusable audit prompt without its Markdown wrapper'
    $promptProjectRoot = Join-Path $tempRoot 'prompt project'
    New-Item -ItemType Directory -Path $promptProjectRoot | Out-Null
    $connectPromptResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('prompt', 'connect', '-ProjectRoot', $promptProjectRoot)
    Assert-True -Condition ($connectPromptResult.ExitCode -eq 0 -and $connectPromptResult.Output -match '^Подключи этот проект к AI Rules Hub' -and $connectPromptResult.Output.Contains($promptProjectRoot) -and $connectPromptResult.Output.Contains($cliPath) -and $connectPromptResult.Output -notmatch '\{\{|```') -Message 'CLI must print a project-specific connection prompt without Markdown wrappers or placeholders'
    $unknownPromptResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('prompt', 'missing')
    Assert-True -Condition ($unknownPromptResult.ExitCode -ne 0 -and $unknownPromptResult.Output.Contains("'connect'") -and $unknownPromptResult.Output.Contains("'audit'")) -Message 'CLI prompt command must reject unknown prompt names'
    $profilesResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('list', 'profiles')
    Assert-True -Condition ($profilesResult.ExitCode -eq 0 -and $profilesResult.Output -match 'profiles/standard-product\.md' -and $profilesResult.Output.Contains([string]$catalog.profiles.'standard-product'.description)) -Message 'CLI profile list must use catalog descriptions'
    $topicsResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('list', 'topics')
    Assert-True -Condition ($topicsResult.ExitCode -eq 0 -and $topicsResult.Output -match 'rules/PRODUCT\.md' -and $topicsResult.Output -match 'rules/RELIABILITY_AND_OPERATIONS\.md' -and $topicsResult.Output.Contains([string]$catalog.topics.product.description) -and $topicsResult.Output.Contains([string]$catalog.topics.'reliability-and-operations'.description)) -Message 'CLI topic list must use catalog descriptions and include reliability'
    $unknownCommandResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('unknown-command')
    Assert-True -Condition ($unknownCommandResult.ExitCode -ne 0 -and $unknownCommandResult.Output -match 'unknown-command') -Message 'unknown CLI command must fail clearly'
    $missingProjectRootResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('status')
    Assert-True -Condition ($missingProjectRootResult.ExitCode -ne 0 -and $missingProjectRootResult.Output -match '-ProjectRoot') -Message 'project commands must explain a missing ProjectRoot'
    $unknownSelectionRoot = Join-Path $tempRoot 'unknown selection project'
    New-Item -ItemType Directory -Path $unknownSelectionRoot | Out-Null
    $unknownProfileResult = Invoke-HubScript -ScriptPath $cliPath -Arguments @('init', '-ProjectRoot', $unknownSelectionRoot, '-Profiles', 'missing-profile')
    Assert-True -Condition ($unknownProfileResult.ExitCode -ne 0 -and $unknownProfileResult.Output -match 'missing-profile') -Message 'CLI init must validate profiles through the catalog'

    $validatorPath = Join-Path $hubRoot 'scripts/validate-commit-message.ps1'
    $validMessagePath = Join-Path $tempRoot 'valid-message.txt'
    $invalidMessagePath = Join-Path $tempRoot 'invalid-message.txt'
    $nonEnglishMessagePath = Join-Path $tempRoot 'non-english-message.txt'

    Set-Content -LiteralPath $validMessagePath -Value 'feat(sync): add manifest' -Encoding UTF8
    $validResult = Invoke-HubScript -ScriptPath $validatorPath -Arguments @('-MessageFile', $validMessagePath)
    Assert-True -Condition ($validResult.ExitCode -eq 0) -Message 'valid conventional commit must pass'

    Set-Content -LiteralPath $invalidMessagePath -Value 'feat: add manifest.' -Encoding UTF8
    $invalidResult = Invoke-HubScript -ScriptPath $validatorPath -Arguments @('-MessageFile', $invalidMessagePath)
    Assert-True -Condition ($invalidResult.ExitCode -ne 0) -Message 'commit without scope must fail'

    $nonEnglishMessage = "docs(ai): update guidance`n`nReason $([char]0x043F)"
    Set-Content -LiteralPath $nonEnglishMessagePath -Value $nonEnglishMessage -Encoding UTF8
    $nonEnglishResult = Invoke-HubScript -ScriptPath $validatorPath -Arguments @('-MessageFile', $nonEnglishMessagePath)
    Assert-True -Condition ($nonEnglishResult.ExitCode -ne 0 -and $nonEnglishResult.Output -match 'English') -Message 'commit message with Cyrillic text must fail'

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $hubRoot -c core.hooksPath=.githooks hook run commit-msg -- $validMessagePath 2>&1 | Out-Null
        $validHookExitCode = $LASTEXITCODE
        & git -C $hubRoot -c core.hooksPath=.githooks hook run commit-msg -- $invalidMessagePath 2>&1 | Out-Null
        $invalidHookExitCode = $LASTEXITCODE
        & git -C $hubRoot -c core.hooksPath=.githooks hook run commit-msg -- $nonEnglishMessagePath 2>&1 | Out-Null
        $nonEnglishHookExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Assert-True -Condition ($validHookExitCode -eq 0) -Message 'repository commit-msg hook must invoke validator'
    Assert-True -Condition ($invalidHookExitCode -ne 0) -Message 'repository commit-msg hook must reject invalid message'
    Assert-True -Condition ($nonEnglishHookExitCode -ne 0) -Message 'repository commit-msg hook must reject Cyrillic text'

    $applyHubRoot = Join-Path $tempRoot 'clean apply hub fixture'
    New-Item -ItemType Directory -Path $applyHubRoot | Out-Null
    foreach ($fixtureDirectory in @('profiles', 'rules', 'scripts', 'src', 'sync', 'templates', 'workflows')) {
        Copy-Item -LiteralPath (Join-Path $hubRoot $fixtureDirectory) -Destination $applyHubRoot -Recurse
    }
    Copy-Item -LiteralPath $cliPath -Destination (Join-Path $applyHubRoot 'ai-rules.ps1')
    & git -C $applyHubRoot init --quiet
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean apply fixture must initialize a Git repository'
    & git -C $applyHubRoot config core.autocrlf false
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean apply fixture must keep copied line endings stable'
    & git -C $applyHubRoot add --all
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean apply fixture files must stage'
    & git -C $applyHubRoot -c user.name='AI Rules Hub Tests' -c user.email='tests@example.invalid' commit --quiet -m 'test(sync): create apply fixture'
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean apply fixture must create a commit'
    $applyCliPath = Join-Path $applyHubRoot 'ai-rules.ps1'
    $applySyncPath = Join-Path $applyHubRoot 'scripts/sync-rules.ps1'
    $applyHubRevision = (& git -C $applyHubRoot rev-parse HEAD).Trim()

    $initializerPath = Join-Path $hubRoot 'scripts/init-project-sync.ps1'

    $notInitializedProjectRoot = Join-Path $tempRoot 'not initialized project'
    New-Item -ItemType Directory -Path $notInitializedProjectRoot | Out-Null
    $notInitializedStatus = Invoke-HubScript -ScriptPath $cliPath -Arguments @('status', '-ProjectRoot', $notInitializedProjectRoot)
    Assert-True -Condition ($notInitializedStatus.ExitCode -eq 0 -and $notInitializedStatus.Output -match 'State: not-initialized') -Message 'status must identify a project without manifest'
    $notInitializedDoctor = Invoke-HubScript -ScriptPath $cliPath -Arguments @('doctor', '-ProjectRoot', $notInitializedProjectRoot)
    Assert-True -Condition ($notInitializedDoctor.ExitCode -ne 0 -and $notInitializedDoctor.Output -match '\[ERROR\]') -Message 'project doctor must fail when manifest is missing'

    $invalidJsonProjectRoot = Join-Path $tempRoot 'invalid json project'
    New-Item -ItemType Directory -Path (Join-Path $invalidJsonProjectRoot '.ai-rules') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $invalidJsonProjectRoot '.ai-rules/manifest.json') -Value '{ invalid json' -Encoding UTF8
    $invalidJsonSnapshot = Get-TreeSnapshot -Root $invalidJsonProjectRoot
    $invalidJsonDoctor = Invoke-HubScript -ScriptPath $cliPath -Arguments @('doctor', '-ProjectRoot', $invalidJsonProjectRoot)
    Assert-True -Condition ($invalidJsonDoctor.ExitCode -ne 0 -and $invalidJsonDoctor.Output -match '\[ERROR\]') -Message 'project doctor must fail on invalid manifest JSON'
    Assert-True -Condition ((Get-TreeSnapshot -Root $invalidJsonProjectRoot) -eq $invalidJsonSnapshot) -Message 'project doctor must not rewrite invalid JSON'

    $cliProjectRoot = Join-Path $tempRoot 'CLI project'
    New-Item -ItemType Directory -Path $cliProjectRoot | Out-Null
    $cliInit = Invoke-HubScript -ScriptPath $cliPath -Arguments @(
        'init', '-ProjectRoot', $cliProjectRoot, '-Profiles', 'standard-product'
    )
    Assert-True -Condition ($cliInit.ExitCode -eq 0) -Message "CLI init must pass: $($cliInit.Output)"
    Assert-True -Condition ($cliInit.Output -match 'Следующий шаг ограничен AGENTS\.md, RULESET\.md и PROJECT_RULES\.md' -and $cliInit.Output -match 'Не исправляйте код, документацию, CI, лицензию или настройки проекта') -Message 'CLI init must state the initial adoption scope'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $cliProjectRoot '.ai-rules/manifest.json')) -Message 'CLI init must create manifest'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $cliProjectRoot 'AGENTS.md')) -Message 'CLI init must seed AGENTS.md by default'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $cliProjectRoot '.ai-rules/RULESET.md')) -Message 'CLI init must seed RULESET.md by default'
    Assert-True -Condition ($cliInit.Output -match 'update' -and $cliInit.Output -match '-Apply') -Message 'CLI init must print the onboarding update checklist'
    Assert-True -Condition ($cliInit.Output -match '\.\\ai-rules\.ps1 prompt audit' -and $cliInit.Output -match 'Общие правила переносить вручную не нужно') -Message 'CLI init must route to the post-apply audit prompt command'
    $seededRuleset = Get-Content -LiteralPath (Join-Path $cliProjectRoot '.ai-rules/RULESET.md') -Raw -Encoding UTF8
    Assert-True -Condition ($seededRuleset -match '- `standard-product`.*<почему выбран>') -Message 'CLI init must seed selected profile in backticks with a reason placeholder'
    Assert-True -Condition (([regex]::Matches($seededRuleset, '(?m)^Нет\.$')).Count -eq 2) -Message 'CLI init must mark optional RULESET sections as empty'
    Assert-True -Condition ($seededRuleset -notmatch '<название>|release gate') -Message 'optional RULESET sections must not retain placeholders'
    $seededProjectRules = Get-Content -LiteralPath (Join-Path $cliProjectRoot '.ai-rules/PROJECT_RULES.md') -Raw -Encoding UTF8
    Assert-True -Condition (([regex]::Matches($seededProjectRules, '(?m)^## ')).Count -eq 7 -and $seededProjectRules.Length -lt 2500) -Message 'CLI init must seed the minimal PROJECT_RULES.md'
    $seededManifestText = Get-Content -LiteralPath (Join-Path $cliProjectRoot '.ai-rules/manifest.json') -Raw -Encoding UTF8
    Assert-True -Condition ($seededManifestText -match '(?m)^  "source": \{$' -and $seededManifestText -match '(?m)^  "topics": \[\],$' -and $seededManifestText -match '(?m)^  "profiles": \["standard-product"\]$' -and $seededManifestText -notmatch "`r" -and $seededManifestText -notmatch '(?m)^\s+"[^"]+":[ \t]{2,}') -Message 'initializer must write stable compact LF JSON formatting'
    $repeatCliInit = Invoke-HubScript -ScriptPath $cliPath -Arguments @('init', '-ProjectRoot', $cliProjectRoot)
    Assert-True -Condition ($repeatCliInit.ExitCode -ne 0 -and $repeatCliInit.Output -match 'manifest' -and $repeatCliInit.Output -match 'существует') -Message 'repeat CLI init must fail explicitly'

    $cliProjectBeforeStatus = Get-TreeSnapshot -Root $cliProjectRoot
    $unpinnedStatus = Invoke-HubScript -ScriptPath $cliPath -Arguments @('status', '-ProjectRoot', $cliProjectRoot)
    Assert-True -Condition ($unpinnedStatus.ExitCode -eq 0 -and $unpinnedStatus.Output -match 'State: unpinned') -Message 'status must identify an unpinned manifest'
    Assert-True -Condition ($unpinnedStatus.Output -match 'Direct topics' -and $unpinnedStatus.Output -match 'Effective topics' -and $unpinnedStatus.Output -match 'architecture-and-data' -and $unpinnedStatus.Output -match 'Next:') -Message 'status must show direct, effective, profile-derived topics, and a next action'
    Assert-True -Condition ((Get-TreeSnapshot -Root $cliProjectRoot) -eq $cliProjectBeforeStatus) -Message 'status must not change project files'

    $unpinnedPlan = Invoke-HubScript -ScriptPath $cliPath -Arguments @('plan', '-ProjectRoot', $cliProjectRoot)
    Assert-True -Condition ($unpinnedPlan.ExitCode -eq 0 -and $unpinnedPlan.Output -match 'update' -and $unpinnedPlan.Output -match '-Apply') -Message 'root plan must mark an unpinned plan as preliminary and route to update -Apply'
    Assert-True -Condition ((Get-TreeSnapshot -Root $cliProjectRoot) -eq $cliProjectBeforeStatus) -Message 'root plan must remain read-only'

    $cliApply = Invoke-HubScript -ScriptPath $cliPath -Arguments @('apply', '-ProjectRoot', $cliProjectRoot)
    Assert-True -Condition ($cliApply.ExitCode -ne 0 -and $cliApply.Output -match 'update' -and $cliApply.Output -match '-Apply') -Message 'root apply must reject an unpinned manifest and explain the first update flow'
    Assert-True -Condition ((Get-TreeSnapshot -Root $cliProjectRoot) -eq $cliProjectBeforeStatus) -Message 'rejected unpinned root apply must not change project files'

    $cliDoctorBefore = Get-TreeSnapshot -Root $cliProjectRoot
    $cliDoctor = Invoke-HubScript -ScriptPath $cliPath -Arguments @('doctor', '-ProjectRoot', $cliProjectRoot)
    Assert-True -Condition ($cliDoctor.ExitCode -eq 0 -and $cliDoctor.Output -match '\[WARN\]' -and $cliDoctor.Output -match 'placeholder') -Message "project doctor warnings must keep a zero exit code: $($cliDoctor.Output)"
    Assert-True -Condition ($cliDoctor.Output -match 'целостность подключения AI Rules Hub' -and $cliDoctor.Output -match 'не означает соответствие всего проекта') -Message 'project doctor must distinguish integration integrity from project compliance'
    Assert-True -Condition ((Get-TreeSnapshot -Root $cliProjectRoot) -eq $cliDoctorBefore) -Message 'project doctor must be read-only'

    $syncPath = $applySyncPath
    $cliLowLevelApply = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $cliProjectRoot, '-Mode', 'Apply')
    Assert-True -Condition ($cliLowLevelApply.ExitCode -ne 0 -and $cliLowLevelApply.Output -match 'закреплённую source\.revision' -and $cliLowLevelApply.Output -match 'update -Apply') -Message "low-level Apply must reject an unpinned manifest: $($cliLowLevelApply.Output)"
    Assert-True -Condition ((Get-TreeSnapshot -Root $cliProjectRoot) -eq $cliProjectBeforeStatus) -Message 'rejected low-level unpinned Apply must not change project files'
    $cliInitialUpdate = Invoke-HubScript -ScriptPath $applyCliPath -Arguments @('update', '-ProjectRoot', $cliProjectRoot, '-Apply')
    Assert-True -Condition ($cliInitialUpdate.ExitCode -eq 0) -Message "update -Apply must replace the removed unpinned recovery path: $($cliInitialUpdate.Output)"
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $cliProjectRoot '.ai-rules/upstream/rules/RELIABILITY_AND_OPERATIONS.md'))) -Message 'standard-product must not pull reliability without an explicit topic'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $cliProjectRoot '.ai-rules/upstream/workflows/PROJECT_STUDY.md'))) -Message 'standard-product must not pull project-study without an explicit topic'
    $cliManifestPath = Join-Path $cliProjectRoot '.ai-rules/manifest.json'
    $cliManifest = Get-Content -LiteralPath $cliManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $currentHubRevision = $applyHubRevision
    Assert-True -Condition ($cliManifest.source.revision -eq $currentHubRevision) -Message 'update -Apply must pin the clean hub revision'
    $synchronizedSnapshot = Get-TreeSnapshot -Root $cliProjectRoot
    $synchronizedStatus = Invoke-HubScript -ScriptPath $applyCliPath -Arguments @('status', '-ProjectRoot', $cliProjectRoot)
    Assert-True -Condition ($synchronizedStatus.ExitCode -eq 0 -and $synchronizedStatus.Output -match 'State: synchronized') -Message "status must identify synchronized project: $($synchronizedStatus.Output)"
    Assert-True -Condition ((Get-TreeSnapshot -Root $cliProjectRoot) -eq $synchronizedSnapshot) -Message 'synchronized status must stay read-only'

    $updatePreview = Invoke-HubScript -ScriptPath $applyCliPath -Arguments @('update', '-ProjectRoot', $cliProjectRoot)
    Assert-True -Condition ($updatePreview.ExitCode -eq 0 -and $updatePreview.Output -match $currentHubRevision -and $updatePreview.Output -match '-Apply') -Message 'update preview must show revisions and remain explicit'
    Assert-True -Condition ((Get-TreeSnapshot -Root $cliProjectRoot) -eq $synchronizedSnapshot) -Message 'update preview must not change manifest, lock, or upstream'

    $existingFilesProjectRoot = Join-Path $tempRoot 'project with existing local files'
    $existingFilesRulesRoot = Join-Path $existingFilesProjectRoot '.ai-rules'
    New-Item -ItemType Directory -Path $existingFilesRulesRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $existingFilesProjectRoot 'docs'), (Join-Path $existingFilesProjectRoot 'src'), (Join-Path $existingFilesProjectRoot '.local-docs') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $existingFilesProjectRoot 'README.md') -Value "# Existing project`n`nKeep this public entry point unchanged." -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingFilesProjectRoot 'docs/guide.md') -Value "# Existing guide`n`nCanonical project documentation." -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingFilesProjectRoot 'src/main.txt') -Value 'existing source bytes' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingFilesProjectRoot '.local-docs/owner-notes.md') -Value 'private owner documentation' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingFilesProjectRoot 'AGENTS.md') -Value '# Existing agent rules' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingFilesRulesRoot 'RULESET.md') -Value '# Existing ruleset' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $existingFilesRulesRoot 'PROJECT_RULES.md') -Value '# Existing project rules' -Encoding UTF8
    $existingProjectSurfacePaths = @('README.md', 'docs/guide.md', 'src/main.txt', '.local-docs/owner-notes.md')
    $existingProjectSurfaceBefore = @($existingProjectSurfacePaths | ForEach-Object { [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $existingFilesProjectRoot $_))) })
    $existingFilesInit = Invoke-HubScript -ScriptPath $cliPath -Arguments @('init', '-ProjectRoot', $existingFilesProjectRoot, '-Profiles', 'standard-product')
    Assert-True -Condition ($existingFilesInit.ExitCode -eq 0) -Message "initializer must support an existing local rules directory: $($existingFilesInit.Output)"
    Assert-True -Condition (([regex]::Matches($existingFilesInit.Output, '\[SKIP\]')).Count -eq 3) -Message 'initializer must report each preserved local file explicitly'
    Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $existingFilesProjectRoot 'AGENTS.md') -Raw -Encoding UTF8).Trim() -eq '# Existing agent rules') -Message 'initializer must preserve existing root AGENTS.md'
    Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $existingFilesRulesRoot 'RULESET.md') -Raw -Encoding UTF8).Trim() -eq '# Existing ruleset') -Message 'initializer must preserve existing local RULESET.md'
    Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $existingFilesRulesRoot 'PROJECT_RULES.md') -Raw -Encoding UTF8).Trim() -eq '# Existing project rules') -Message 'initializer must preserve existing local PROJECT_RULES.md'
    $existingProjectSurfaceAfterInit = @($existingProjectSurfacePaths | ForEach-Object { [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $existingFilesProjectRoot $_))) })
    Assert-True -Condition (($existingProjectSurfaceAfterInit -join "`n") -eq ($existingProjectSurfaceBefore -join "`n")) -Message 'CLI init must preserve existing README, docs, and source byte-for-byte'
    $existingFilesSnapshot = Get-TreeSnapshot -Root $existingFilesProjectRoot
    $existingFilesDoctor = Invoke-HubScript -ScriptPath $cliPath -Arguments @('doctor', '-ProjectRoot', $existingFilesProjectRoot)
    Assert-True -Condition ($existingFilesDoctor.ExitCode -eq 0 -and $existingFilesDoctor.Output -match '\[WARN\]' -and $existingFilesDoctor.Output -match 'AGENTS\.md') -Message 'missing AGENTS routes must be a warning with zero exit code'
    Assert-True -Condition ($existingFilesDoctor.Output -match 'AGENTS\.md пока не подключает выбранные профили') -Message 'unpinned project must warn when selected profiles are not routed'
    Assert-True -Condition ((Get-TreeSnapshot -Root $existingFilesProjectRoot) -eq $existingFilesSnapshot) -Message 'profile-routing warning must remain read-only'
    $existingFilesStatus = Invoke-HubScript -ScriptPath $cliPath -Arguments @('status', '-ProjectRoot', $existingFilesProjectRoot)
    $existingFilesPlan = Invoke-HubScript -ScriptPath $cliPath -Arguments @('plan', '-ProjectRoot', $existingFilesProjectRoot)
    Assert-True -Condition ($existingFilesStatus.ExitCode -eq 0 -and $existingFilesPlan.ExitCode -eq 0) -Message 'status and preliminary plan must work for the existing-project fixture'
    Assert-True -Condition ((Get-TreeSnapshot -Root $existingFilesProjectRoot) -eq $existingFilesSnapshot) -Message 'doctor, status, and read-only plan must not change the existing-project fixture'
    $existingProjectSurfaceAfterReads = @($existingProjectSurfacePaths | ForEach-Object { [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $existingFilesProjectRoot $_))) })
    Assert-True -Condition (($existingProjectSurfaceAfterReads -join "`n") -eq ($existingProjectSurfaceBefore -join "`n")) -Message 'doctor, status, and plan must preserve existing README, docs, and source byte-for-byte'

    $legacyProjectRoot = Join-Path $tempRoot 'legacy project'
    New-Item -ItemType Directory -Path $legacyProjectRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $legacyProjectRoot '.ai-rules-hub.json') -Value '{}' -Encoding UTF8
    $legacyInit = Invoke-HubScript -ScriptPath $initializerPath -Arguments @('-ProjectRoot', $legacyProjectRoot)
    Assert-True -Condition ($legacyInit.ExitCode -ne 0) -Message 'initializer must stop on a legacy root manifest'
    Assert-True -Condition ($legacyInit.Output -match 'legacy' -and $legacyInit.Output -match 'явно') -Message 'legacy error must require explicit migration'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $legacyProjectRoot '.ai-rules'))) -Message 'legacy detection must not create the new structure'

    $projectRoot = Join-Path $tempRoot 'target project with spaces'
    New-Item -ItemType Directory -Path $projectRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $projectRoot 'AGENTS.md') -Value '# Local agent rules' -Encoding UTF8

    $initResult = Invoke-HubScript -ScriptPath $initializerPath -Arguments @(
        '-ProjectRoot', $projectRoot,
        '-Topics', 'reliability-and-operations',
        '-Profiles', 'standard-product',
        '-SeedProjectFiles'
    )
    Assert-True -Condition ($initResult.ExitCode -eq 0) -Message "initializer must pass: $($initResult.Output)"
    $localRulesRoot = Join-Path $projectRoot '.ai-rules'
    $manifestPath = Join-Path $localRulesRoot 'manifest.json'
    $rulesetPath = Join-Path $localRulesRoot 'RULESET.md'
    $projectRulesPath = Join-Path $localRulesRoot 'PROJECT_RULES.md'
    $lockPath = Join-Path $localRulesRoot 'lock.json'
    $upstreamRoot = Join-Path $localRulesRoot 'upstream'
    Assert-True -Condition (Test-Path -LiteralPath $localRulesRoot -PathType Container) -Message 'initializer must create local rules directory'
    Assert-True -Condition (Test-Path -LiteralPath $manifestPath) -Message 'initializer must create nested manifest'
    Assert-True -Condition ((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).schemaVersion -eq '0.2') -Message 'initializer must create manifest schema 0.2'
    Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $projectRoot 'AGENTS.md') -Raw -Encoding UTF8).Trim() -eq '# Local agent rules') -Message 'initializer must not overwrite local AGENTS.md'
    Assert-True -Condition (Test-Path -LiteralPath $rulesetPath) -Message 'initializer must seed nested RULESET.md'
    Assert-True -Condition (Test-Path -LiteralPath $projectRulesPath) -Message 'initializer must seed nested PROJECT_RULES.md'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.ai-rules-hub.json'))) -Message 'initializer must not create old root manifest'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.ai-rules-hub.lock.json'))) -Message 'initializer must not create old root lock'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'RULESET.md'))) -Message 'initializer must not create root RULESET.md'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'PROJECT_RULES.md'))) -Message 'initializer must not create root PROJECT_RULES.md'

    $unpinnedManifestBeforeSync = [System.IO.File]::ReadAllText($manifestPath)
    $rulesetBeforeSync = [System.IO.File]::ReadAllText($rulesetPath)
    $projectRulesBeforeSync = [System.IO.File]::ReadAllText($projectRulesPath)

    $syncPath = $applySyncPath
    $initialPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($initialPlan.ExitCode -eq 0) -Message "initial plan must pass for a path with spaces: $($initialPlan.Output)"
    Assert-True -Condition ($initialPlan.Output -match 'Plan' -and $initialPlan.Output -match 'не изменены') -Message 'plan must explain that it is read-only'
    Assert-True -Condition ($initialPlan.Output -match 'Summary: add=') -Message 'plan must print an action summary'
    Assert-True -Condition ($initialPlan.Output -match 'Managed root: \.ai-rules/upstream') -Message 'plan must identify upstream as the managed root'
    Assert-True -Condition (-not (Test-Path -LiteralPath $upstreamRoot)) -Message 'plan must not create upstream directory'
    Assert-True -Condition (-not (Test-Path -LiteralPath $lockPath)) -Message 'plan must not create nested lock'
    Assert-True -Condition ([System.IO.File]::ReadAllText($manifestPath) -eq $unpinnedManifestBeforeSync) -Message 'plan must not change manifest'
    Assert-True -Condition ([System.IO.File]::ReadAllText($rulesetPath) -eq $rulesetBeforeSync) -Message 'plan must not change RULESET.md'
    Assert-True -Condition ([System.IO.File]::ReadAllText($projectRulesPath) -eq $projectRulesBeforeSync) -Message 'plan must not change PROJECT_RULES.md'

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.source.revision = $applyHubRevision
    $pinnedManifestJson = ($manifest | ConvertTo-Json -Depth 6) + "`n"
    [System.IO.File]::WriteAllText($manifestPath, $pinnedManifestJson, (New-Object System.Text.UTF8Encoding($false)))
    $manifestBeforeSync = [System.IO.File]::ReadAllText($manifestPath)

    $applyResult = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Apply')
    Assert-True -Condition ($applyResult.ExitCode -eq 0) -Message "first sync apply must pass: $($applyResult.Output)"

    $managedCorePath = Join-Path $upstreamRoot 'CORE.md'
    $managedProfilePath = Join-Path $upstreamRoot 'profiles/standard-product.md'
    Assert-True -Condition (Test-Path -LiteralPath $managedCorePath) -Message 'sync must copy core'
    Assert-True -Condition (Test-Path -LiteralPath $managedProfilePath) -Message 'sync must copy selected profile'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $upstreamRoot 'rules/PRODUCT.md')) -Message 'profile must pull topic dependencies'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $upstreamRoot 'rules/DOCUMENTATION.md')) -Message 'standard-product must pull documentation architecture rule'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $upstreamRoot 'workflows/PROJECT_STUDY.md'))) -Message 'sync must not copy project-study without an explicit selection'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $upstreamRoot 'rules/RELIABILITY_AND_OPERATIONS.md')) -Message 'sync must copy explicitly selected reliability topic'
    Assert-True -Condition (Test-Path -LiteralPath $lockPath) -Message 'apply must create lock'
    Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $projectRoot 'AGENTS.md') -Raw -Encoding UTF8).Trim() -eq '# Local agent rules') -Message 'apply must not overwrite local AGENTS.md'
    Assert-True -Condition ([System.IO.File]::ReadAllText($manifestPath) -eq $manifestBeforeSync) -Message 'apply must not overwrite manifest'
    Assert-True -Condition ([System.IO.File]::ReadAllText($rulesetPath) -eq $rulesetBeforeSync) -Message 'apply must not overwrite nested RULESET.md'
    Assert-True -Condition ([System.IO.File]::ReadAllText($projectRulesPath) -eq $projectRulesBeforeSync) -Message 'apply must not overwrite nested PROJECT_RULES.md'

    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hubRevision = $applyHubRevision
    Assert-True -Condition ($lock.schemaVersion -eq '0.2') -Message 'lock must use schema 0.2'
    Assert-True -Condition ($lock.manifest -eq '.ai-rules/manifest.json') -Message 'lock must record nested manifest path'
    Assert-True -Condition ($lock.managedRoot -eq '.ai-rules/upstream') -Message 'lock must record upstream as managed root'
    Assert-True -Condition ($lock.source.revision -eq $hubRevision) -Message 'lock must contain exact hub revision'
    Assert-True -Condition ($lock.source.revision -match '^[0-9a-f]{40}$') -Message 'lock revision must be a full commit SHA'
    $coreLockEntry = @($lock.files | Where-Object { $_.target -eq '.ai-rules/upstream/CORE.md' })[0]
    Assert-True -Condition ($null -ne $coreLockEntry) -Message 'lock must contain managed core entry'
    Assert-True -Condition ($coreLockEntry.sha256 -eq (Get-NormalizedSha256 -Path $managedCorePath)) -Message 'lock must contain normalized managed-file SHA-256'

    $secondPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($secondPlan.ExitCode -eq 0) -Message 'second plan must pass'
    Assert-True -Condition ($secondPlan.Output -match 'unchanged') -Message 'second plan must report unchanged files'

    $lockBeforeSecondApply = [System.IO.File]::ReadAllText($lockPath)
    $secondApply = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Apply')
    $lockAfterSecondApply = [System.IO.File]::ReadAllText($lockPath)
    Assert-True -Condition ($secondApply.ExitCode -eq 0) -Message "second apply must pass: $($secondApply.Output)"
    Assert-True -Condition ($secondApply.Output -match 'Lock' -and $secondApply.Output -match 'не изменён') -Message 'idempotent apply must report unchanged lock'
    Assert-True -Condition ($lockAfterSecondApply -eq $lockBeforeSecondApply) -Message 'idempotent apply must not rewrite lock content'

    $coreText = [System.IO.File]::ReadAllText($managedCorePath).Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($managedCorePath, $coreText.Replace("`n", "`r`n"), $utf8WithoutBom)
    $lineEndingPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($lineEndingPlan.ExitCode -eq 0) -Message 'line-ending-only change must not fail plan'
    Assert-True -Condition ($lineEndingPlan.Output -notmatch 'conflict') -Message 'LF and CRLF must have the same managed hash'

    Add-Content -LiteralPath $managedCorePath -Value "`nlocal change" -Encoding UTF8
    $conflictApply = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Apply')
    Assert-True -Condition ($conflictApply.ExitCode -ne 0) -Message 'apply must stop on locally modified managed file'
    Assert-True -Condition ((Get-Content -LiteralPath $managedCorePath -Raw -Encoding UTF8) -match 'local change') -Message 'conflicting target must remain untouched'
    Copy-Item -LiteralPath (Join-Path $hubRoot 'rules/CORE.md') -Destination $managedCorePath -Force

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Content -LiteralPath $managedProfilePath -Value "`nlocal profile change" -Encoding UTF8
    $manifest.profiles = @()
    $manifest.topics = @()
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $orphanPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($orphanPlan.ExitCode -eq 0) -Message "orphan plan must remain read-only and pass: $($orphanPlan.Output)"
    Assert-True -Condition ($orphanPlan.Output -match 'orphan') -Message 'removed selection must report orphan files'
    Assert-True -Condition ($orphanPlan.Output -match 'orphan-modified') -Message 'locally changed deselected file must report orphan-modified'

    $orphanApply = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Apply')
    Assert-True -Condition ($orphanApply.ExitCode -eq 0) -Message 'apply must preserve safe orphan files'
    Assert-True -Condition (Test-Path -LiteralPath $managedProfilePath) -Message 'apply must not delete orphan file'
    Assert-True -Condition ((Get-Content -LiteralPath $managedProfilePath -Raw -Encoding UTF8) -match 'local profile change') -Message 'apply must preserve modified orphan content'

    $orphanLock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $profileLockEntry = @($orphanLock.files | Where-Object { $_.target -eq '.ai-rules/upstream/profiles/standard-product.md' })[0]
    Assert-True -Condition ($profileLockEntry.state -eq 'orphan') -Message 'lock must retain deselected file as orphan'

    $postApplyOrphanPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($postApplyOrphanPlan.Output -match 'orphan') -Message 'lock must retain orphan state after apply'

    $validLockJson = [System.IO.File]::ReadAllText($lockPath)
    $invalidLock = $validLockJson | ConvertFrom-Json
    $invalidLock.files[0].target = '.ai-rules/PROJECT_RULES.md'
    $invalidLock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $lockPath -Encoding UTF8
    $outsideManagedPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($outsideManagedPlan.ExitCode -ne 0) -Message 'locked target outside upstream must fail'
    Assert-True -Condition ($outsideManagedPlan.Output -match 'managed' -and $outsideManagedPlan.Output -match 'upstream') -Message 'outside-managed error must explain the lock boundary'
    [System.IO.File]::WriteAllText($lockPath, $validLockJson, (New-Object System.Text.UTF8Encoding($false)))

    $transactionProjectRoot = Join-Path $tempRoot 'transaction rollback project'
    New-Item -ItemType Directory -Path $transactionProjectRoot | Out-Null
    $transactionInit = Invoke-HubScript -ScriptPath $initializerPath -Arguments @('-ProjectRoot', $transactionProjectRoot, '-Profiles', 'standard-product')
    Assert-True -Condition ($transactionInit.ExitCode -eq 0) -Message "transaction fixture must initialize: $($transactionInit.Output)"
    $transactionManifestPath = Join-Path $transactionProjectRoot '.ai-rules/manifest.json'
    $transactionManifest = Get-Content -LiteralPath $transactionManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $transactionManifest.source.revision = $applyHubRevision
    [System.IO.File]::WriteAllText($transactionManifestPath, (($transactionManifest | ConvertTo-Json -Depth 6) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $transactionUpstreamRoot = Join-Path $transactionProjectRoot '.ai-rules/upstream'
    New-Item -ItemType Directory -Path $transactionUpstreamRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $transactionUpstreamRoot 'rules') -Value 'blocks the second managed directory' -Encoding UTF8
    $transactionSnapshot = Get-TreeSnapshot -Root $transactionProjectRoot
    $failedMidApply = Invoke-HubScript -ScriptPath $applySyncPath -Arguments @('-ProjectRoot', $transactionProjectRoot, '-Mode', 'Apply')
    Assert-True -Condition ($failedMidApply.ExitCode -ne 0 -and $failedMidApply.Output -match 'исходное состояние восстановлено') -Message "Apply must report a successful rollback after a mid-copy failure: $($failedMidApply.Output)"
    Assert-True -Condition ((Get-TreeSnapshot -Root $transactionProjectRoot) -eq $transactionSnapshot) -Message 'mid-copy failure must restore every project file byte-for-byte'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $transactionUpstreamRoot 'profiles') -PathType Container)) -Message 'mid-copy rollback must remove directories created by the failed transaction'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $transactionProjectRoot '.ai-rules/lock.json'))) -Message 'mid-copy failure must not leave a lock file'

    $reparseProjectRoot = Join-Path $tempRoot 'reparse project'
    $reparseTargetRoot = Join-Path $tempRoot 'reparse outside target'
    New-Item -ItemType Directory -Path $reparseProjectRoot, $reparseTargetRoot | Out-Null
    $reparseInit = Invoke-HubScript -ScriptPath $initializerPath -Arguments @('-ProjectRoot', $reparseProjectRoot, '-Profiles', 'standard-product')
    Assert-True -Condition ($reparseInit.ExitCode -eq 0) -Message "reparse fixture must initialize: $($reparseInit.Output)"
    $reparseManifestPath = Join-Path $reparseProjectRoot '.ai-rules/manifest.json'
    $reparseManifest = Get-Content -LiteralPath $reparseManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reparseManifest.source.revision = $applyHubRevision
    [System.IO.File]::WriteAllText($reparseManifestPath, (($reparseManifest | ConvertTo-Json -Depth 6) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $reparseUpstreamPath = Join-Path $reparseProjectRoot '.ai-rules/upstream'
    New-Item -ItemType Junction -Path $reparseUpstreamPath -Target $reparseTargetRoot | Out-Null
    $reparsePlan = Invoke-HubScript -ScriptPath $applySyncPath -Arguments @('-ProjectRoot', $reparseProjectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($reparsePlan.ExitCode -ne 0 -and $reparsePlan.Output -match 'reparse point') -Message "Plan must reject a managed path through a junction: $($reparsePlan.Output)"
    $reparseApply = Invoke-HubScript -ScriptPath $applySyncPath -Arguments @('-ProjectRoot', $reparseProjectRoot, '-Mode', 'Apply')
    Assert-True -Condition ($reparseApply.ExitCode -ne 0 -and $reparseApply.Output -match 'reparse point') -Message 'Apply must reject a managed path through a junction before writing'
    Assert-True -Condition (@(Get-ChildItem -LiteralPath $reparseTargetRoot -Force).Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $reparseProjectRoot '.ai-rules/lock.json'))) -Message 'rejected junction path must leave both the external target and project lock unchanged'

    $cleanHubRoot = Join-Path $tempRoot 'clean hub fixture'
    New-Item -ItemType Directory -Path $cleanHubRoot | Out-Null
    foreach ($fixtureDirectory in @('profiles', 'rules', 'scripts', 'src', 'sync', 'templates', 'workflows')) {
        Copy-Item -LiteralPath (Join-Path $hubRoot $fixtureDirectory) -Destination $cleanHubRoot -Recurse
    }
    Copy-Item -LiteralPath $cliPath -Destination (Join-Path $cleanHubRoot 'ai-rules.ps1')

    $cleanHubCheckPath = Join-Path $cleanHubRoot 'scripts/check-hub.ps1'
    $unregisteredRulePath = Join-Path $cleanHubRoot 'rules/UNREGISTERED_RULE.md'
    Set-Content -LiteralPath $unregisteredRulePath -Value '# Unregistered test rule' -Encoding UTF8
    $unregisteredRuleCheck = Invoke-HubScript -ScriptPath $cleanHubCheckPath
    Assert-True -Condition ($unregisteredRuleCheck.ExitCode -ne 0 -and $unregisteredRuleCheck.Output -match 'Rule file is not registered in catalog: rules/UNREGISTERED_RULE\.md') -Message 'hub check must detect an unregistered topic rule file'
    Remove-Item -LiteralPath $unregisteredRulePath -Force

    $cleanCatalogPath = Join-Path $cleanHubRoot 'sync/catalog.json'
    $cleanCatalogBytes = [System.IO.File]::ReadAllBytes($cleanCatalogPath)
    $duplicateCatalog = Get-Content -LiteralPath $cleanCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $duplicateCatalog.topics.product.file = [string]$duplicateCatalog.topics.quality.file
    $duplicateCatalog | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cleanCatalogPath -Encoding UTF8
    $duplicateTopicCheck = Invoke-HubScript -ScriptPath $cleanHubCheckPath
    Assert-True -Condition ($duplicateTopicCheck.ExitCode -ne 0 -and $duplicateTopicCheck.Output -match 'Multiple catalog topics reference the same rule file') -Message 'hub check must detect duplicate topic file references'
    [System.IO.File]::WriteAllBytes($cleanCatalogPath, $cleanCatalogBytes)

    $reservedCatalog = Get-Content -LiteralPath $cleanCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reservedCatalog.topics.product.file = 'rules/CORE.md'
    $reservedCatalog | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cleanCatalogPath -Encoding UTF8
    $reservedTopicCheck = Invoke-HubScript -ScriptPath $cleanHubCheckPath
    Assert-True -Condition ($reservedTopicCheck.ExitCode -ne 0 -and $reservedTopicCheck.Output -match 'reserved rule file: rules/CORE\.md') -Message 'CORE and README must remain reserved outside catalog topics'
    [System.IO.File]::WriteAllBytes($cleanCatalogPath, $cleanCatalogBytes)

    $cleanManifestSchemaPath = Join-Path $cleanHubRoot 'sync/project-manifest.schema.json'
    $cleanManifestSchemaBytes = [System.IO.File]::ReadAllBytes($cleanManifestSchemaPath)
    $manifestSchema = Get-Content -LiteralPath $cleanManifestSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ('reliability-and-operations' -in @($manifestSchema.properties.topics.items.enum)) -Message 'manifest schema must include every current catalog topic'
    $manifestSchema.properties.topics.items.enum = @($manifestSchema.properties.topics.items.enum | Where-Object { $_ -ne 'reliability-and-operations' })
    $manifestSchema | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cleanManifestSchemaPath -Encoding UTF8
    $missingSchemaTopicCheck = Invoke-HubScript -ScriptPath $cleanHubCheckPath
    Assert-True -Condition ($missingSchemaTopicCheck.ExitCode -ne 0 -and $missingSchemaTopicCheck.Output -match 'Manifest schema topic enum must exactly match catalog topics') -Message 'hub check must reject topic drift between manifest schema and catalog'
    [System.IO.File]::WriteAllBytes($cleanManifestSchemaPath, $cleanManifestSchemaBytes)

    $manifestSchema = Get-Content -LiteralPath $cleanManifestSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifestSchema.properties.profiles.items.enum = @($manifestSchema.properties.profiles.items.enum | Where-Object { $_ -ne 'public-repository' })
    $manifestSchema | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cleanManifestSchemaPath -Encoding UTF8
    $missingSchemaProfileCheck = Invoke-HubScript -ScriptPath $cleanHubCheckPath
    Assert-True -Condition ($missingSchemaProfileCheck.ExitCode -ne 0 -and $missingSchemaProfileCheck.Output -match 'Manifest schema profile enum must exactly match catalog profiles') -Message 'hub check must reject profile drift between manifest schema and catalog'
    [System.IO.File]::WriteAllBytes($cleanManifestSchemaPath, $cleanManifestSchemaBytes)

    & git -C $cleanHubRoot init --quiet
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean update fixture must initialize a Git repository'
    & git -C $cleanHubRoot config core.autocrlf false
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean update fixture must keep copied line endings stable'
    & git -C $cleanHubRoot add --all
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean update fixture files must stage'
    & git -C $cleanHubRoot -c user.name='AI Rules Hub Tests' -c user.email='tests@example.invalid' commit --quiet -m 'test(sync): create clean fixture'
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean update fixture must create a commit'

    $cleanCliPath = Join-Path $cleanHubRoot 'ai-rules.ps1'
    $connectProjectRoot = Join-Path $tempRoot 'connect project'
    New-Item -ItemType Directory -Path $connectProjectRoot | Out-Null
    $prematureConnectApply = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('connect', '-ProjectRoot', $connectProjectRoot, '-Profiles', 'standard-product', '-Apply')
    Assert-True -Condition ($prematureConnectApply.ExitCode -ne 0 -and $prematureConnectApply.Output -match 'Первый Plan ещё не показан' -and -not (Test-Path -LiteralPath (Join-Path $connectProjectRoot '.ai-rules/manifest.json'))) -Message 'connect must not let first-time Apply bypass preview'
    $connectPreview = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('connect', '-ProjectRoot', $connectProjectRoot, '-Profiles', 'standard-product')
    Assert-True -Condition ($connectPreview.ExitCode -eq 0 -and $connectPreview.Output -match 'Локальный слой подготовлен' -and $connectPreview.Output -match 'Предварительный Plan' -and $connectPreview.Output -match 'Файлы проекта не изменены') -Message "connect must initialize project-owned files and show the first managed Plan: $($connectPreview.Output)"
    Assert-True -Condition ((Test-Path -LiteralPath (Join-Path $connectProjectRoot '.ai-rules/manifest.json')) -and -not (Test-Path -LiteralPath (Join-Path $connectProjectRoot '.ai-rules/lock.json'))) -Message 'connect preview must leave managed rules unapplied'
    $connectApply = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('connect', '-ProjectRoot', $connectProjectRoot, '-Profiles', 'standard-product', '-Apply')
    Assert-True -Condition ($connectApply.ExitCode -eq 0 -and $connectApply.Output -match 'Проверка подключения' -and $connectApply.Output -match 'Итоговое состояние' -and $connectApply.Output -match 'State: synchronized') -Message "connect -Apply must verify and report the synchronized result: $($connectApply.Output)"
    $connectSelectionMismatch = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('connect', '-ProjectRoot', $connectProjectRoot, '-Profiles', 'learning-project')
    Assert-True -Condition ($connectSelectionMismatch.ExitCode -ne 0 -and $connectSelectionMismatch.Output -match 'отличается от manifest') -Message 'repeat connect must reject a selection that differs from the project manifest'

    $noProfileProjectRoot = Join-Path $tempRoot 'no profile project'
    New-Item -ItemType Directory -Path $noProfileProjectRoot | Out-Null
    $noProfileInit = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('init', '-ProjectRoot', $noProfileProjectRoot, '-Topics', 'reliability-and-operations')
    Assert-True -Condition ($noProfileInit.ExitCode -eq 0) -Message "project without profiles must initialize: $($noProfileInit.Output)"
    $noProfileSeededRuleset = Get-Content -LiteralPath (Join-Path $noProfileProjectRoot '.ai-rules/RULESET.md') -Raw -Encoding UTF8
    Assert-True -Condition ($noProfileSeededRuleset -match '(?ms)^## Выбранные профили\s*\r?\n\s*- Пока не выбраны\.' -and $noProfileSeededRuleset -match '- `reliability-and-operations`.*<почему подключена отдельно>') -Message 'initializer must seed empty arrays explicitly and selected topic IDs in backticks'
    $noProfileAgentsPath = Join-Path $noProfileProjectRoot 'AGENTS.md'
    $noProfileAgents = [System.IO.File]::ReadAllText($noProfileAgentsPath)
    $noProfileAgents = [regex]::Replace($noProfileAgents, '(?m)^.*\.ai-rules/upstream/profiles/.*\r?\n?', '')
    [System.IO.File]::WriteAllText($noProfileAgentsPath, $noProfileAgents, (New-Object System.Text.UTF8Encoding($false)))
    $noProfileUnpinnedDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $noProfileProjectRoot)
    Assert-True -Condition ($noProfileUnpinnedDoctor.ExitCode -eq 0 -and $noProfileUnpinnedDoctor.Output -notmatch 'выбранные профили') -Message 'profile routing must not be required when no profiles are selected'
    $noProfileApply = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $noProfileProjectRoot, '-Apply')
    Assert-True -Condition ($noProfileApply.ExitCode -eq 0) -Message "project without profiles must apply: $($noProfileApply.Output)"
    $noProfilePinnedDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $noProfileProjectRoot)
    Assert-True -Condition ($noProfilePinnedDoctor.ExitCode -eq 0 -and $noProfilePinnedDoctor.Output -notmatch 'не подключает выбранные профили') -Message 'pinned project without profiles must not require a profile route'
    $noProfileRulesetPath = Join-Path $noProfileProjectRoot '.ai-rules/RULESET.md'
    $noProfileRulesetBytes = [System.IO.File]::ReadAllBytes($noProfileRulesetPath)
    $noProfileRuleset = [System.IO.File]::ReadAllText($noProfileRulesetPath)
    $noProfileRuleset = [regex]::Replace($noProfileRuleset, '(?ms)^## Выбранные профили\s*.*?(?=^## )', '')
    [System.IO.File]::WriteAllText($noProfileRulesetPath, $noProfileRuleset, (New-Object System.Text.UTF8Encoding($false)))
    $noProfileMissingSectionDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $noProfileProjectRoot)
    Assert-True -Condition ($noProfileMissingSectionDoctor.ExitCode -eq 0 -and $noProfileMissingSectionDoctor.Output -notmatch 'не содержит секцию «Выбранные профили»') -Message 'missing profile section must be allowed when manifest profiles are empty'
    [System.IO.File]::WriteAllBytes($noProfileRulesetPath, $noProfileRulesetBytes)

    $updateProjectRoot = Join-Path $tempRoot 'update apply project'
    New-Item -ItemType Directory -Path $updateProjectRoot | Out-Null
    $cleanInit = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('init', '-ProjectRoot', $updateProjectRoot, '-Profiles', 'standard-product,learning-project', '-Topics', 'project-study')
    Assert-True -Condition ($cleanInit.ExitCode -eq 0) -Message "clean CLI init must pass: $($cleanInit.Output)"
    $cleanInitialApply = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot, '-Apply')
    Assert-True -Condition ($cleanInitialApply.ExitCode -eq 0) -Message "first update -Apply must pin and synchronize the project: $($cleanInitialApply.Output)"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $updateProjectRoot '.ai-rules/upstream/workflows/PROJECT_STUDY.md')) -Message 'sync must copy explicitly selected project-study workflow'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $updateProjectRoot '.ai-rules/upstream/rules/RELIABILITY_AND_OPERATIONS.md'))) -Message 'project-study selection must not pull reliability implicitly'

    $updateManifestPath = Join-Path $updateProjectRoot '.ai-rules/manifest.json'
    $updateLockPath = Join-Path $updateProjectRoot '.ai-rules/lock.json'
    $initialCleanHubRevision = (& git -C $cleanHubRoot rev-parse HEAD).Trim()
    $initialUpdateManifest = Get-Content -LiteralPath $updateManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($initialUpdateManifest.source.revision -eq $initialCleanHubRevision) -Message 'first update -Apply must write the initial clean hub revision'
    $initialUpdateLockText = Get-Content -LiteralPath $updateLockPath -Raw -Encoding UTF8
    Assert-True -Condition ($initialUpdateLockText -match '(?m)^  "source": \{$' -and $initialUpdateLockText -match '(?m)^  "profiles": \["learning-project", "standard-product"\],$' -and $initialUpdateLockText -notmatch "`r" -and $initialUpdateLockText -notmatch '(?m)^\s+"[^"]+":[ \t]{2,}') -Message 'sync must write stable compact LF JSON formatting'
    $updateRulesetPath = Join-Path $updateProjectRoot '.ai-rules/RULESET.md'
    $initialRuleset = Get-Content -LiteralPath $updateRulesetPath -Raw -Encoding UTF8
    Assert-True -Condition ($initialRuleset -match '- `standard-product`.*<почему выбран>' -and $initialRuleset -match '- `learning-project`.*<почему выбран>' -and $initialRuleset -match '- `project-study`.*<почему подключена отдельно>') -Message 'RULESET must seed selected profile and direct topic IDs in backticks'
    Assert-True -Condition (([regex]::Matches($initialRuleset, '(?m)^Нет\.$')).Count -eq 2) -Message 'RULESET must use explicit empty values for optional sections'
    $connectedDoctorSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $connectedDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($connectedDoctor.ExitCode -eq 0 -and $connectedDoctor.Output -notmatch '\[ERROR\]') -Message "doctor must accept a correctly connected pinned project: $($connectedDoctor.Output)"
    Assert-True -Condition ($connectedDoctor.Output -match 'подключает все выбранные профили') -Message 'pinned project must accept the general profile route'
    Assert-True -Condition ($connectedDoctor.Output -match 'Manifest и RULESET\.md согласованы' -and $connectedDoctor.Output -notmatch 'architecture-and-data.*не объяснена') -Message 'doctor must require direct selections but not profile-derived effective topics in RULESET'
    Assert-True -Condition ($connectedDoctor.Output -match '(?m)^\[WARN\] В RULESET\.md.*<почему выбран>.*<почему подключена отдельно>' -and $connectedDoctor.Output -notmatch '(?m)^\[WARN\] В RULESET\.md.*(?:<название>|release gate)') -Message 'doctor must warn only about required RULESET decisions'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $connectedDoctorSnapshot) -Message 'doctor must keep a connected project unchanged'

    $cleanPreviewSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $cleanUpdatePreview = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($cleanUpdatePreview.ExitCode -eq 0 -and $cleanUpdatePreview.Output -match 'Целевая revision хаба' -and $cleanUpdatePreview.Output -match 'После проверки выполните ту же команду с -Apply' -and $cleanUpdatePreview.Output -notmatch 'ВНИМАНИЕ') -Message 'clean update preview must retain the normal apply hint'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $cleanPreviewSnapshot) -Message 'clean update preview must remain read-only'

    $dirtyHubFilePath = Join-Path $cleanHubRoot 'rules/CORE.md'
    $dirtyHubFileBytes = [System.IO.File]::ReadAllBytes($dirtyHubFilePath)
    Add-Content -LiteralPath $dirtyHubFilePath -Value "`nDirty preview test change" -Encoding UTF8
    $dirtyPreviewSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $dirtyManifestBytes = [System.IO.File]::ReadAllBytes($updateManifestPath)
    $dirtyLockBytes = [System.IO.File]::ReadAllBytes($updateLockPath)
    $dirtyUpdatePreview = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($dirtyUpdatePreview.ExitCode -eq 0 -and $dirtyUpdatePreview.Output -match 'ВНИМАНИЕ: рабочее дерево хаба содержит незакоммиченные изменения' -and $dirtyUpdatePreview.Output -match 'Preview построен по текущим файлам checkout' -and $dirtyUpdatePreview.Output -match 'может не соответствовать' -and $dirtyUpdatePreview.Output -match 'только указанному commit SHA' -and $dirtyUpdatePreview.Output -match 'Базовая revision checkout' -and $dirtyUpdatePreview.Output -match 'Рабочее дерево хаба изменено: true') -Message 'dirty update preview must explain its working-tree provenance'
    Assert-True -Condition ($dirtyUpdatePreview.Output -notmatch 'После проверки выполните ту же команду с -Apply' -and $dirtyUpdatePreview.Output -match 'сначала сохраните или отмените изменения хаба') -Message 'dirty preview must not offer immediate Apply'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $dirtyPreviewSnapshot -and ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($updateManifestPath))) -eq ([Convert]::ToBase64String($dirtyManifestBytes)) -and ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($updateLockPath))) -eq ([Convert]::ToBase64String($dirtyLockBytes))) -Message 'dirty preview must not change project files, manifest, or lock'
    $dirtyLowLevelApply = Invoke-HubScript -ScriptPath (Join-Path $cleanHubRoot 'scripts/sync-rules.ps1') -Arguments @('-ProjectRoot', $updateProjectRoot, '-Mode', 'Apply')
    Assert-True -Condition ($dirtyLowLevelApply.ExitCode -ne 0 -and $dirtyLowLevelApply.Output -match 'изменённого checkout хаба') -Message 'low-level Apply must reject a dirty source checkout directly'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $dirtyPreviewSnapshot) -Message 'rejected dirty low-level Apply must not change project files'
    $dirtyUpdateApply = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot, '-Apply')
    Assert-True -Condition ($dirtyUpdateApply.ExitCode -ne 0 -and $dirtyUpdateApply.Output -match 'рабочее дерево хаба должно быть чистым' -and (Get-TreeSnapshot -Root $updateProjectRoot) -eq $dirtyPreviewSnapshot) -Message 'dirty update -Apply must remain blocked and read-only'
    [System.IO.File]::WriteAllBytes($dirtyHubFilePath, $dirtyHubFileBytes)

    $updateAgentsPath = Join-Path $updateProjectRoot 'AGENTS.md'
    $originalAgentsBytes = [System.IO.File]::ReadAllBytes($updateAgentsPath)
    $originalAgentsText = [System.IO.File]::ReadAllText($updateAgentsPath)

    $agentsWithoutProfileRoute = $originalAgentsText.Replace('.ai-rules/upstream/profiles/', '.ai-rules/upstream/MISSING_PROFILES/')
    [System.IO.File]::WriteAllText($updateAgentsPath, $agentsWithoutProfileRoute, (New-Object System.Text.UTF8Encoding($false)))
    $missingProfileRouteSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $missingProfileRouteDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($missingProfileRouteDoctor.ExitCode -ne 0 -and $missingProfileRouteDoctor.Output -match '\[ERROR\] Закреплённый проект не подключает выбранные профили AI Rules Hub' -and $missingProfileRouteDoctor.Output -match 'standard-product' -and $missingProfileRouteDoctor.Output -match 'learning-project') -Message 'pinned project without profile routing must fail and list selected profiles'
    $missingProfileRouteStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($missingProfileRouteStatus.Output -match 'State: inconsistent' -and (Get-TreeSnapshot -Root $updateProjectRoot) -eq $missingProfileRouteSnapshot) -Message 'status must report missing profile routing as inconsistent and remain read-only'

    $explicitProfileRoutes = ".ai-rules/upstream/profiles/standard-product.md`n.ai-rules/upstream/profiles/learning-project.md"
    [System.IO.File]::WriteAllText($updateAgentsPath, $originalAgentsText.Replace('.ai-rules/upstream/profiles/', $explicitProfileRoutes), (New-Object System.Text.UTF8Encoding($false)))
    $explicitProfilesDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($explicitProfilesDoctor.ExitCode -eq 0 -and $explicitProfilesDoctor.Output -match 'подключает все выбранные профили') -Message 'pinned project must accept explicit routes to every selected profile'

    [System.IO.File]::WriteAllText($updateAgentsPath, $originalAgentsText.Replace('.ai-rules/upstream/profiles/', '.ai-rules/upstream/profiles/standard-product.md'), (New-Object System.Text.UTF8Encoding($false)))
    $partialProfilesDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($partialProfilesDoctor.ExitCode -ne 0 -and $partialProfilesDoctor.Output -match 'не подключает выбранные профили' -and $partialProfilesDoctor.Output -match 'learning-project') -Message 'routing only one of two selected profiles must be insufficient'
    [System.IO.File]::WriteAllBytes($updateAgentsPath, $originalAgentsBytes)

    $agentsWithoutCoreRoute = ([System.IO.File]::ReadAllText($updateAgentsPath)).Replace('.ai-rules/upstream/CORE.md', '.ai-rules/upstream/MISSING.md') + "`n# Existing user text"
    [System.IO.File]::WriteAllText($updateAgentsPath, $agentsWithoutCoreRoute, (New-Object System.Text.UTF8Encoding($false)))
    $agentsRouteSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $pinnedMissingRouteDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($pinnedMissingRouteDoctor.ExitCode -ne 0 -and $pinnedMissingRouteDoctor.Output -match '\[ERROR\]' -and $pinnedMissingRouteDoctor.Output -match '\.ai-rules/upstream/CORE\.md') -Message 'pinned project missing an AGENTS route must fail doctor'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $agentsRouteSnapshot -and ([System.IO.File]::ReadAllText($updateAgentsPath)).Contains('# Existing user text')) -Message 'doctor must preserve existing AGENTS content'
    $pinnedMissingRouteStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($pinnedMissingRouteStatus.Output -match 'State: inconsistent' -and (Get-TreeSnapshot -Root $updateProjectRoot) -eq $agentsRouteSnapshot) -Message 'status must treat missing pinned AGENTS routes as inconsistent and remain read-only'
    [System.IO.File]::WriteAllBytes($updateAgentsPath, $originalAgentsBytes)

    $originalRulesetBytes = [System.IO.File]::ReadAllBytes($updateRulesetPath)
    $rulesetCases = @(
        [pscustomobject]@{ Name = 'missing selected profile'; Content = $initialRuleset.Replace('`standard-product`', '`profile-not-explained`'); Pattern = 'Профиль standard-product' },
        [pscustomobject]@{ Name = 'missing direct topic'; Content = $initialRuleset.Replace('`project-study`', '`topic-not-explained`'); Pattern = 'Тема project-study' },
        [pscustomobject]@{ Name = 'known unselected profile in profile section'; Content = $initialRuleset.Replace('## Дополнительные темы', "- public-repository — not selected`n`n## Дополнительные темы"); Pattern = 'Выбранные профили.*public-repository.*не выбран' },
        [pscustomobject]@{ Name = 'known unselected topic in topic section'; Content = $initialRuleset.Replace('## Локальные исключения', "- reliability-and-operations — not selected`n`n## Локальные исключения"); Pattern = 'Дополнительные темы.*reliability-and-operations.*не выбрана' },
        [pscustomobject]@{ Name = 'missing profile section'; Content = [regex]::Replace($initialRuleset, '(?ms)^## Выбранные профили\s*.*?(?=^## )', ''); Pattern = 'не содержит секцию «Выбранные профили»' },
        [pscustomobject]@{ Name = 'missing topic section'; Content = [regex]::Replace($initialRuleset, '(?ms)^## Дополнительные темы\s*.*?(?=^## )', ''); Pattern = 'не содержит секцию «Дополнительные темы»' }
    )
    foreach ($rulesetCase in $rulesetCases) {
        [System.IO.File]::WriteAllText($updateRulesetPath, $rulesetCase.Content, (New-Object System.Text.UTF8Encoding($false)))
        $rulesetSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
        $rulesetDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
        Assert-True -Condition ($rulesetDoctor.ExitCode -eq 0 -and $rulesetDoctor.Output -match '\[WARN\]' -and $rulesetDoctor.Output -match $rulesetCase.Pattern) -Message "doctor must warn for RULESET case: $($rulesetCase.Name)"
        Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $rulesetSnapshot) -Message "doctor must not edit RULESET case: $($rulesetCase.Name)"
    }
    $outsideSectionRuleset = $initialRuleset.Replace('## Локальные исключения', "## Локальные исключения`n`n- quality упомянута только как локальное исключение") + "`nПояснение вне секций: public-repository.`n- public-repository — это пример, а не выбор.`n"
    [System.IO.File]::WriteAllText($updateRulesetPath, $outsideSectionRuleset, (New-Object System.Text.UTF8Encoding($false)))
    $outsideSectionSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $outsideSectionDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($outsideSectionDoctor.ExitCode -eq 0 -and $outsideSectionDoctor.Output -notmatch 'public-repository.*не выбран' -and $outsideSectionDoctor.Output -notmatch 'quality.*не выбрана') -Message 'RULESET consistency must ignore known IDs outside selection sections'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $outsideSectionSnapshot) -Message 'section-scoped RULESET check must remain read-only'

    $crossSectionRuleset = $initialRuleset.Replace('## Локальные исключения', "- public-repository — explanatory profile ID`n`n## Локальные исключения")
    [System.IO.File]::WriteAllText($updateRulesetPath, $crossSectionRuleset, (New-Object System.Text.UTF8Encoding($false)))
    $crossSectionDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($crossSectionDoctor.ExitCode -eq 0 -and $crossSectionDoctor.Output -notmatch 'public-repository.*не выбран') -Message 'profile IDs in the topic section must not be analyzed as profile selections'

    $plainTokenRuleset = $initialRuleset.Replace('`standard-product`', 'standard-product')
    [System.IO.File]::WriteAllText($updateRulesetPath, $plainTokenRuleset, (New-Object System.Text.UTF8Encoding($false)))
    $plainTokenDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($plainTokenDoctor.ExitCode -eq 0 -and $plainTokenDoctor.Output -notmatch 'Профиль standard-product.*не объяснён') -Message 'RULESET parser must retain plain-token compatibility while templates use backticks'
    [System.IO.File]::WriteAllBytes($updateRulesetPath, $originalRulesetBytes)

    $updateManagedCorePath = Join-Path $updateProjectRoot '.ai-rules/upstream/CORE.md'
    $originalManagedCoreBytes = [System.IO.File]::ReadAllBytes($updateManagedCorePath)
    $managedCoreText = [System.IO.File]::ReadAllText($updateManagedCorePath).Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($updateManagedCorePath, $managedCoreText.Replace("`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    $normalizedHashDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($normalizedHashDoctor.ExitCode -eq 0 -and $normalizedHashDoctor.Output -notmatch 'Managed-файл изменён') -Message 'doctor and sync must share normalized text hashing'
    [System.IO.File]::WriteAllBytes($updateManagedCorePath, $originalManagedCoreBytes)
    Remove-Item -LiteralPath $updateManagedCorePath -Force
    $missingManagedSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $missingManagedDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($missingManagedDoctor.ExitCode -ne 0 -and $missingManagedDoctor.Output -match 'Managed-файл отсутствует') -Message 'doctor must fail when a managed file is missing'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $missingManagedSnapshot) -Message 'doctor must not restore a missing managed file'
    $missingManagedStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($missingManagedStatus.Output -match 'State: inconsistent' -and (Get-TreeSnapshot -Root $updateProjectRoot) -eq $missingManagedSnapshot) -Message 'status must report a missing managed file without modifying it'
    [System.IO.File]::WriteAllBytes($updateManagedCorePath, $originalManagedCoreBytes)

    $originalUpdateLockBytes = [System.IO.File]::ReadAllBytes($updateLockPath)
    $outsideTargetLock = Get-Content -LiteralPath $updateLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $outsideTargetLock.files[0].target = '.ai-rules/PROJECT_RULES.md'
    $outsideTargetLock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $updateLockPath -Encoding UTF8
    $outsideTargetSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $outsideTargetDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($outsideTargetDoctor.ExitCode -ne 0 -and $outsideTargetDoctor.Output -match 'вне \.ai-rules/upstream') -Message 'doctor must reject lock targets outside managed root'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $outsideTargetSnapshot) -Message 'doctor must not rewrite an invalid lock target'
    [System.IO.File]::WriteAllBytes($updateLockPath, $originalUpdateLockBytes)

    $unknownStateLock = Get-Content -LiteralPath $updateLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $unknownStateLock.files[0].state = 'future-state'
    $unknownStateLock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $updateLockPath -Encoding UTF8
    $unknownStateSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $unknownStateDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($unknownStateDoctor.ExitCode -ne 0 -and $unknownStateDoctor.Output -match 'Неизвестное состояние lock') -Message 'doctor must reject unknown lock states'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $unknownStateSnapshot) -Message 'doctor must not rewrite an unknown lock state'
    [System.IO.File]::WriteAllBytes($updateLockPath, $originalUpdateLockBytes)

    $orphanPath = Join-Path $updateProjectRoot '.ai-rules/upstream/rules/ORPHAN.md'
    Set-Content -LiteralPath $orphanPath -Value '# Orphan fixture' -Encoding UTF8
    $orphanLock = Get-Content -LiteralPath $updateLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $orphanLock.files += [pscustomobject]@{ source = 'rules/ORPHAN.md'; target = '.ai-rules/upstream/rules/ORPHAN.md'; sha256 = (Get-NormalizedSha256 -Path $orphanPath); state = 'orphan' }
    $orphanLock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $updateLockPath -Encoding UTF8
    $orphanSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $orphanDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($orphanDoctor.ExitCode -eq 0 -and $orphanDoctor.Output -match 'Orphan-файл сохранён') -Message 'doctor must report a correct orphan as warning'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $orphanSnapshot) -Message 'doctor must preserve a correct orphan and lock'
    Add-Content -LiteralPath $orphanPath -Value 'local orphan change' -Encoding UTF8
    $modifiedOrphanSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $modifiedOrphanDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($modifiedOrphanDoctor.ExitCode -eq 0 -and $modifiedOrphanDoctor.Output -match 'нельзя удалять автоматически') -Message 'doctor must warn without failing for a modified orphan'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $modifiedOrphanSnapshot) -Message 'doctor must preserve a modified orphan and lock'
    Remove-Item -LiteralPath $orphanPath -Force
    $missingOrphanDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($missingOrphanDoctor.ExitCode -eq 0 -and $missingOrphanDoctor.Output -match 'Orphan-файл отсутствует') -Message 'doctor must warn without failing for a missing orphan'
    [System.IO.File]::WriteAllBytes($updateLockPath, $originalUpdateLockBytes)

    Set-Content -LiteralPath (Join-Path $cleanHubRoot 'fixture-revision.txt') -Value 'second clean revision' -Encoding UTF8
    & git -C $cleanHubRoot add fixture-revision.txt
    & git -C $cleanHubRoot -c user.name='AI Rules Hub Tests' -c user.email='tests@example.invalid' commit --quiet -m 'test(sync): advance fixture revision'
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'clean update fixture must advance to a second revision'
    $secondCleanHubRevision = (& git -C $cleanHubRoot rev-parse HEAD).Trim()
    $updateAvailableSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $updateAvailableStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($updateAvailableStatus.ExitCode -eq 0 -and $updateAvailableStatus.Output -match 'State: update-available') -Message "status must identify a newer hub checkout: $($updateAvailableStatus.Output)"
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $updateAvailableSnapshot) -Message 'update-available status must remain read-only'
    $updateAvailableDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($updateAvailableDoctor.ExitCode -eq 0 -and $updateAvailableDoctor.Output -match '\[WARN\].*более новую revision' -and $updateAvailableDoctor.Output -notmatch '\[ERROR\]') -Message 'doctor must warn, not fail, when the hub is newer'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $updateAvailableSnapshot) -Message 'update-available doctor must remain read-only'

    $updateApply = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot, '-Apply')
    Assert-True -Condition ($updateApply.ExitCode -eq 0 -and $updateApply.Output -match 'State: synchronized') -Message "update -Apply must pass in a clean hub: $($updateApply.Output)"
    $cleanHubRevision = (& git -C $cleanHubRoot rev-parse HEAD).Trim()
    $updatedManifest = Get-Content -LiteralPath $updateManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Condition ($updatedManifest.source.revision -eq $cleanHubRevision -and $updatedManifest.source.revision -match '^[0-9a-f]{40}$') -Message 'update -Apply must write the full current hub SHA'
    $sameRevisionSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $sameRevisionStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($sameRevisionStatus.Output -match 'State: synchronized' -and (Get-TreeSnapshot -Root $updateProjectRoot) -eq $sameRevisionSnapshot) -Message 'same revisions must produce synchronized without writes'

    & git -C $cleanHubRoot checkout --quiet --detach $initialCleanHubRevision
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'relation fixture must checkout the older hub revision'
    $checkoutOlderSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $checkoutOlderStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($checkoutOlderStatus.ExitCode -eq 0 -and $checkoutOlderStatus.Output -match 'State: checkout-older' -and $checkoutOlderStatus.Output -match 'не применяйте update -Apply') -Message 'status must distinguish a hub checkout older than the project'
    $checkoutOlderDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($checkoutOlderDoctor.ExitCode -eq 0 -and $checkoutOlderDoctor.Output -match '\[WARN\].*старее revision проекта' -and $checkoutOlderDoctor.Output -notmatch '\[ERROR\]') -Message 'doctor must warn when checkout is older and still validate the lock snapshot'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $checkoutOlderSnapshot) -Message 'checkout-older status and doctor must remain read-only'

    & git -C $cleanHubRoot checkout --quiet -b relation-diverged $initialCleanHubRevision
    Set-Content -LiteralPath (Join-Path $cleanHubRoot 'diverged-revision.txt') -Value 'diverged revision' -Encoding UTF8
    & git -C $cleanHubRoot add diverged-revision.txt
    & git -C $cleanHubRoot -c user.name='AI Rules Hub Tests' -c user.email='tests@example.invalid' commit --quiet -m 'test(sync): create diverged revision'
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'relation fixture must create a diverged revision'
    $checkoutDivergedSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $checkoutDivergedStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($checkoutDivergedStatus.ExitCode -eq 0 -and $checkoutDivergedStatus.Output -match 'State: checkout-diverged') -Message 'status must distinguish diverged histories'
    $checkoutDivergedDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($checkoutDivergedDoctor.ExitCode -eq 0 -and $checkoutDivergedDoctor.Output -match '\[WARN\].*расходятся' -and $checkoutDivergedDoctor.Output -notmatch '\[ERROR\]') -Message 'doctor must warn for diverged histories after validating lock integrity'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $checkoutDivergedSnapshot) -Message 'checkout-diverged status and doctor must remain read-only'
    & git -C $cleanHubRoot checkout --quiet --detach $secondCleanHubRevision
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'relation fixture must restore the project revision checkout'

    $relationManifestBytes = [System.IO.File]::ReadAllBytes($updateManifestPath)
    $relationLockBytes = [System.IO.File]::ReadAllBytes($updateLockPath)
    $missingRevision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $missingRevisionManifest = Get-Content -LiteralPath $updateManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $missingRevisionManifest.source.revision = $missingRevision
    $missingRevisionManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $updateManifestPath -Encoding UTF8
    $missingRevisionLock = Get-Content -LiteralPath $updateLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $missingRevisionLock.source.revision = $missingRevision
    $missingRevisionLock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $updateLockPath -Encoding UTF8
    $checkoutMismatchSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $checkoutMismatchStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($checkoutMismatchStatus.ExitCode -eq 0 -and $checkoutMismatchStatus.Output -match 'State: checkout-mismatch') -Message 'status must report a locally unavailable revision as checkout-mismatch'
    $checkoutMismatchDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($checkoutMismatchDoctor.ExitCode -eq 0 -and $checkoutMismatchDoctor.Output -match '\[WARN\].*недоступна локально' -and $checkoutMismatchDoctor.Output -notmatch '\[ERROR\]') -Message 'doctor must warn for an unavailable revision while validating lock integrity'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $checkoutMismatchSnapshot) -Message 'checkout-mismatch status and doctor must remain read-only'
    Add-Content -LiteralPath $updateManagedCorePath -Value 'damage while revision is unavailable' -Encoding UTF8
    $unavailableDamageSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $unavailableDamageDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($unavailableDamageDoctor.ExitCode -ne 0 -and $unavailableDamageDoctor.Output -match 'Managed-файл изменён вне AI Rules Hub') -Message 'unavailable revision must not hide managed snapshot damage'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $unavailableDamageSnapshot) -Message 'doctor must not repair damage when revision is unavailable'
    [System.IO.File]::WriteAllBytes($updateManagedCorePath, $originalManagedCoreBytes)
    [System.IO.File]::WriteAllBytes($updateManifestPath, $relationManifestBytes)
    [System.IO.File]::WriteAllBytes($updateLockPath, $relationLockBytes)

    $beforeIdempotentUpdate = Get-TreeSnapshot -Root $updateProjectRoot
    $idempotentUpdate = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot, '-Apply')
    Assert-True -Condition ($idempotentUpdate.ExitCode -eq 0) -Message "repeated update must pass: $($idempotentUpdate.Output)"
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $beforeIdempotentUpdate) -Message 'repeated update on the same revision must be idempotent'

    $updateManagedCorePath = Join-Path $updateProjectRoot '.ai-rules/upstream/CORE.md'
    Add-Content -LiteralPath $updateManagedCorePath -Value "`nlocal conflict" -Encoding UTF8
    $manifestBeforeConflict = [System.IO.File]::ReadAllBytes($updateManifestPath)
    $lockBeforeConflict = [System.IO.File]::ReadAllBytes($updateLockPath)
    $conflictSnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $conflictStatus = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('status', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($conflictStatus.Output -match 'State: inconsistent' -and (Get-TreeSnapshot -Root $updateProjectRoot) -eq $conflictSnapshot) -Message 'status must report a modified managed file without changing it'
    $conflictDoctor = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('doctor', '-ProjectRoot', $updateProjectRoot)
    Assert-True -Condition ($conflictDoctor.ExitCode -ne 0 -and $conflictDoctor.Output -match '\[ERROR\]' -and $conflictDoctor.Output -match 'conflict') -Message 'doctor must return nonzero for a managed conflict'
    $conflictingUpdate = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot, '-Apply')
    Assert-True -Condition ($conflictingUpdate.ExitCode -ne 0 -and $conflictingUpdate.Output -match 'conflict') -Message 'update -Apply must stop before Apply on a managed conflict'
    Assert-True -Condition (([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($updateManifestPath))) -eq ([Convert]::ToBase64String($manifestBeforeConflict))) -Message 'conflicting update must not change manifest'
    Assert-True -Condition (([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($updateLockPath))) -eq ([Convert]::ToBase64String($lockBeforeConflict))) -Message 'conflicting update must not execute Apply or change lock'
    Copy-Item -LiteralPath (Join-Path $cleanHubRoot 'rules/CORE.md') -Destination $updateManagedCorePath -Force

    $failingManifest = Get-Content -LiteralPath $updateManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $failingManifest.source.revision = $null
    $failingManifest.topics = @('project-study', 'reliability-and-operations')
    $failingManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $updateManifestPath -Encoding UTF8
    $manifestBeforeFailedApply = [System.IO.File]::ReadAllBytes($updateManifestPath)
    $failedApplySnapshot = Get-TreeSnapshot -Root $updateProjectRoot
    $failedApplyAddedTopicPath = Join-Path $updateProjectRoot '.ai-rules/upstream/rules/RELIABILITY_AND_OPERATIONS.md'
    Assert-True -Condition (-not (Test-Path -LiteralPath $failedApplyAddedTopicPath)) -Message 'lock-failure fixture must start without the newly selected managed topic'
    Set-ItemProperty -LiteralPath $updateLockPath -Name IsReadOnly -Value $true
    try {
        $failedUpdateApply = Invoke-HubScript -ScriptPath $cleanCliPath -Arguments @('update', '-ProjectRoot', $updateProjectRoot, '-Apply')
    }
    finally {
        Set-ItemProperty -LiteralPath $updateLockPath -Name IsReadOnly -Value $false
    }
    Assert-True -Condition ($failedUpdateApply.ExitCode -ne 0) -Message 'update must expose an underlying Apply failure'
    Assert-True -Condition (([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($updateManifestPath))) -eq ([Convert]::ToBase64String($manifestBeforeFailedApply))) -Message 'failed Apply must restore the original manifest bytes'
    Assert-True -Condition ((Get-TreeSnapshot -Root $updateProjectRoot) -eq $failedApplySnapshot) -Message 'lock write failure must restore manifest, lock, and all managed files byte-for-byte'
    Assert-True -Condition (-not (Test-Path -LiteralPath $failedApplyAddedTopicPath)) -Message 'lock write failure must remove a managed file added earlier in the transaction'

    $manifest.schemaVersion = '0.1'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $oldSchemaPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($oldSchemaPlan.ExitCode -ne 0) -Message 'old manifest schema must fail explicitly'
    $manifest.schemaVersion = '0.2'
    $manifest.source.revision = '1234567'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $shortRevisionPlan = Invoke-HubScript -ScriptPath $syncPath -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Plan')
    Assert-True -Condition ($shortRevisionPlan.ExitCode -ne 0) -Message 'short source revision must fail'
    Assert-True -Condition ($shortRevisionPlan.Output -match '40-' -and $shortRevisionPlan.Output -match 'SHA') -Message 'invalid revision error must explain the required format'

    Write-Host "Tooling tests passed: $assertionCount assertions." -ForegroundColor Green
}
finally {
    $tempRootFull = [System.IO.Path]::GetFullPath($tempRoot)
    $tempPrefix = $tempBase + [System.IO.Path]::DirectorySeparatorChar
    $tempLeaf = Split-Path -Leaf $tempRootFull
    if (
        $tempRootFull.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        $tempLeaf.StartsWith('ai-rules-hub-tests-', [System.StringComparison]::Ordinal)
    ) {
        Remove-Item -LiteralPath $tempRootFull -Recurse -Force
    }
    else {
        Write-Warning "Temporary directory was not removed because its path failed safety validation: $tempRootFull"
    }
}

exit 0

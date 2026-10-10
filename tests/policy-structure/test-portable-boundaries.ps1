[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$catalog = Get-Content -LiteralPath (Join-Path $hubRoot 'sync/catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$implementation = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/IMPLEMENTATION.md') -Raw -Encoding UTF8
$architecture = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/ARCHITECTURE_AND_DATA.md') -Raw -Encoding UTF8
$delivery = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/GIT_AND_DELIVERY.md') -Raw -Encoding UTF8
$quality = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/QUALITY.md') -Raw -Encoding UTF8
$learningProfile = Get-Content -LiteralPath (Join-Path $hubRoot 'profiles/learning-project.md') -Raw -Encoding UTF8
$readme = Get-Content -LiteralPath (Join-Path $hubRoot 'README.md') -Raw -Encoding UTF8

$workflowPaths = @('workflows/PROJECT_CONNECT_PROMPT.md', 'workflows/PROJECT_AUDIT_PROMPT.md', 'workflows/PROJECT_DEEP_AUDIT_PROMPT.md', 'workflows/PROJECT_STUDY_PROMPT.md', 'workflows/PROJECT_STUDY.md', 'workflows/PROJECT_DEEP_AUDIT.md', 'workflows/PARALLEL_DELIVERY.md', 'workflows/PARALLEL_DELIVERY_PROMPT.md')
foreach ($workflowPath in $workflowPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $hubRoot $workflowPath) -PathType Leaf)) { throw "Workflow is missing: $workflowPath" }
}
if (Test-Path -LiteralPath (Join-Path $hubRoot 'rules/PROJECT_STUDY.md')) { throw 'Project study must not remain in portable rules.' }
if (Test-Path -LiteralPath (Join-Path $hubRoot 'templates/PROJECT_CONNECT_PROMPT.md')) { throw 'Connection workflow must not remain a project template.' }
if ([string]$catalog.topics.'project-study'.file -ne 'workflows/PROJECT_STUDY.md') { throw 'Compatible project-study ID must route to the workflow.' }
if ([string]$catalog.topics.'project-audit'.file -ne 'workflows/PROJECT_DEEP_AUDIT.md') { throw 'Project-audit ID must route to the deep-audit workflow.' }
if ([string]$catalog.topics.'parallel-delivery'.file -ne 'workflows/PARALLEL_DELIVERY.md' -or [string]$catalog.topics.'parallel-delivery'.kind -ne 'workflow') { throw 'Parallel-delivery ID must route to the task workflow.' }
if ([string]$catalog.topics.'visual-design-discovery'.file -ne 'workflows/VISUAL_DESIGN_DISCOVERY.md' -or [string]$catalog.topics.'visual-design-discovery'.kind -ne 'workflow') { throw 'Visual discovery must remain a task workflow, not a permanent topic rule.' }
foreach ($profile in $catalog.profiles.PSObject.Properties) {
    foreach ($topic in @($profile.Value.topics)) {
        if ([string]$catalog.topics.$topic.kind -eq 'workflow') { throw "Profile must not select a workflow automatically: $($profile.Name) -> $topic" }
    }
}
if ($implementation -match 'оформляются явными блоками' -or $implementation -notmatch 'точный стиль скобок.*локальным стандартом') { throw 'Portable implementation policy must preserve the invariant without selecting a brace style.' }
if ($architecture -match 'настрой стабильный алиас корня|\.\./\.\./\.\./') { throw 'Portable architecture policy must not prescribe a root alias or fixed import depth.' }
if ($delivery -match 'установи `Husky`|установи.*commitlint') { throw 'Portable delivery policy must not prescribe Node-specific hook tooling.' }
if ($delivery -notmatch 'короткой ветке задачи' -or $delivery -notmatch 'постоянный staging или production' -or $delivery -notmatch 'точный commit и артефакт') { throw 'Portable delivery policy must isolate task work and gate persistent environments on the exact candidate.' }
if ($quality -notmatch 'ожидание `expect` < лимит теста < лимит полного прогона < лимит CI job' -or $quality -notmatch 'Повторное падение одного класса') { throw 'Portable quality policy must align CI time budgets and stop serial fixes after a repeated failure class.' }
if ($learningProfile -notmatch 'устойчивой частью' -or $learningProfile -notmatch 'разового изучения') { throw 'Learning profile must describe a stable project property rather than a task workflow.' }
if ($readme -match '## Detailed connection workflow|## Synchronization states|## Repository structure') { throw 'Public README must remain a short external entry point.' }

# A persistent project may stay small; platform examples do not select architecture.
$bootstrap = Get-Content -LiteralPath (Join-Path $hubRoot 'workflows/PROJECT_BOOTSTRAP.md') -Raw -Encoding UTF8
$product = Get-Content -LiteralPath (Join-Path $hubRoot 'rules/PRODUCT.md') -Raw -Encoding UTF8
$discovery = Get-Content -LiteralPath (Join-Path $hubRoot 'workflows/VISUAL_DESIGN_DISCOVERY.md') -Raw -Encoding UTF8
if ($architecture -match 'Выбери один стартовый архетип' -or $bootstrap -match 'Выбери один минимальный архетип') { throw 'Kit must not require choosing from a closed architecture list.' }
if ($bootstrap -notmatch 'Если конкретная основа и план уже одобрены' -or $bootstrap -notmatch 'до зависимой реализации' -or $bootstrap -notmatch 'Для продукта без графического интерфейса') { throw 'Bootstrap must preserve plan approval, prior authorization and the headless design exemption.' }
if ($product -match '4–6|минимум два' -or $discovery -match 'минимум 2|2–3 направления') { throw 'Visual selection must not impose reference or alternative quotas.' }

# Routing metadata must preserve the action gates without making every read a workflow.
$agents = Get-Content -LiteralPath (Join-Path $hubRoot 'templates/AGENTS.md') -Raw -Encoding UTF8
$taskStart = $agents.IndexOf('Сначала прочитай запрос владельца')
$localRules = $agents.IndexOf('.ai-rules/RULESET.md')
if ($taskStart -lt 0 -or $taskStart -ge $localRules) {
    throw 'The task must establish context before the mandatory rule-reading sequence.'
}
$invariants = @(
    'До планирования и изменений',
    'Читай выбранный профиль целиком',
    'Состав подключённых тем сам по себе не расширяет задачу'
)
foreach ($invariant in $invariants) {
    if (-not $agents.Contains($invariant)) {
        throw "Task-first routing must preserve: $invariant"
    }
}
$routingCases = @(
    @{
        Topic = 'git-and-delivery'
        Gates = @(
            'До изменения веток, индекса или истории Git',
            'внешней операцией',
            'Обычное чтение git status и diff',
            'границы полномочий CORE'
        )
    },
    @{
        Topic = 'product'
        Gates = @(
            'До существенного нового интерфейса или редизайна',
            'малых правок',
            'исключения продуктового правила'
        )
    },
    @{
        Topic = 'architecture-and-data'
        Gates = @(
            'локальный архитектурный контракт',
            'первоначальный выбор обязателен',
            'миграций'
        )
    },
    @{
        Topic = 'security-and-privacy'
        Gates = @(
            'доступом',
            'чувствительными данными',
            'пропорционально риску',
            'не отменяет обязательств выбранного профиля'
        )
    }
)
foreach ($scenario in $routingCases) {
    $condition = [string]$catalog.topics.($scenario.Topic).readWhen
    foreach ($gate in $scenario.Gates) {
        if (-not $condition.Contains($gate)) {
            throw "Routing for $($scenario.Topic) lost its boundary: $gate"
        }
    }
}
Write-Host 'Portable boundary tests passed, including task-first routing and preserved action gates.' -ForegroundColor Green

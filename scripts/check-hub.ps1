[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$errors = [System.Collections.Generic.List[string]]::new()

function Get-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $absolutePath = [System.IO.Path]::GetFullPath($Path)
    return $absolutePath.Substring($repoRoot.Length).TrimStart([char[]]@('\', '/'))
}

$requiredPaths = @(
    '.gitignore',
    'AGENTS.md',
    'CLAUDE.md',
    'README.md',
    'ai-rules.ps1',
    'CONTRIBUTING.md',
    '.github/SECURITY.md',
    'rules/README.md',
    'rules/CORE.md',
    'rules/RELIABILITY_AND_OPERATIONS.md',
    'hub/PROJECT_RULES.md',
    'hub/ARCHITECTURE.md',
    'hub/COMMIT_RULES.md',
    'profiles/README.md',
    'templates/README.md',
    'workflows/PROJECT_CONNECT_PROMPT.md',
    'workflows/PROJECT_AUDIT_PROMPT.md',
    'workflows/PROJECT_STUDY.md',
    'evals/README.md',
    'evals/controls.json',
    'evals/runs/README.md',
    'evals/runs/RESULT_TEMPLATE.json',
    'templates/PROJECT_RULES.full.md',
    'sync/README.md',
    'sync/catalog.json',
    'sync/project-manifest.schema.json',
    'scripts/validate-commit-message.ps1',
    'scripts/sync-rules.ps1',
    'scripts/sync-common.ps1',
    'scripts/init-project-sync.ps1',
    'scripts/show-prompt.ps1',
    'src/Catalog.psm1',
    'src/Contracts.psm1',
    'src/PathsAndHashing.psm1',
    'src/GitState.psm1',
    'src/EffectiveIndex.psm1',
    'src/SyncPlan.psm1',
    'src/ProjectState.psm1',
    'src/Diagnostics.psm1',
    '.githooks/commit-msg',
    '.github/workflows/validate.yml',
    'tests/test-tooling.ps1',
    'tests/run.ps1',
    'tests/contracts/test-contracts.ps1',
    'tests/sync/test-sync-plan.ps1',
    'tests/cli/test-integration.ps1',
    'tests/diagnostics/test-project-state.ps1',
    'tests/policy-structure/test-module-boundaries.ps1',
    'tests/policy-structure/test-portable-boundaries.ps1',
    'tests/policy-structure/test-evals.ps1'
)

foreach ($requiredPath in $requiredPaths) {
    $absolutePath = Join-Path $repoRoot $requiredPath
    if (-not (Test-Path -LiteralPath $absolutePath)) {
        $errors.Add("Missing required path: $requiredPath")
    }
}

$claudeAdapterPath = Join-Path $repoRoot 'CLAUDE.md'
if (Test-Path -LiteralPath $claudeAdapterPath -PathType Leaf) {
    $claudeAdapter = Get-Content -LiteralPath $claudeAdapterPath -Raw -Encoding UTF8
    if ($claudeAdapter.Trim() -ne '@AGENTS.md') {
        $errors.Add('CLAUDE.md must only import the canonical root AGENTS.md.')
    }
}

$forbiddenPublicPaths = @(
    'hub/BACKLOG.md',
    'hub/decisions'
)
foreach ($forbiddenPublicPath in $forbiddenPublicPaths) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $forbiddenPublicPath)) {
        $errors.Add("Owner-only documentation must not be part of the public hub: $forbiddenPublicPath")
    }
}

$gitignorePath = Join-Path $repoRoot '.gitignore'
if (Test-Path -LiteralPath $gitignorePath -PathType Leaf) {
    $gitignoreContent = Get-Content -LiteralPath $gitignorePath -Raw -Encoding UTF8
    $gitignoreLines = @($gitignoreContent -split '\r?\n')
    if ($gitignoreLines -notcontains '.local-docs/') {
        $errors.Add('Local owner documentation directory must stay ignored: .local-docs/')
    }
}

$licenseCandidates = @('LICENSE', 'LICENSE.md', 'LICENSE.txt')
if (-not ($licenseCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf })) {
    $errors.Add('Public repository has no root LICENSE, LICENSE.md, or LICENSE.txt. License selection requires an explicit owner decision.')
}

$githubContributingCandidates = @('CONTRIBUTING.md', '.github/CONTRIBUTING.md')
if (-not ($githubContributingCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf })) {
    $errors.Add('Public repository has no GitHub-discoverable CONTRIBUTING.md.')
}

$securityPolicyPath = Join-Path $repoRoot '.github/SECURITY.md'
if (-not (Test-Path -LiteralPath $securityPolicyPath -PathType Leaf)) {
    $errors.Add('Public repository has no .github/SECURITY.md.')
}

$workflowRoot = Join-Path $repoRoot '.github/workflows'
if (Test-Path -LiteralPath $workflowRoot -PathType Container) {
    $workflowFiles = Get-ChildItem -LiteralPath $workflowRoot -File |
        Where-Object { $_.Extension -in @('.yml', '.yaml') }

    foreach ($workflowFile in $workflowFiles) {
        $workflowRelativePath = Get-RepoRelativePath -Path $workflowFile.FullName
        $workflowContent = Get-Content -LiteralPath $workflowFile.FullName -Raw -Encoding UTF8

        if ($workflowContent -notmatch '(?m)^permissions:\s*\r?\n(?:(?:^[ \t]+[^\r\n]*\r?\n)*)^[ \t]+contents:\s*read\s*(?:#.*)?$') {
            $errors.Add("Workflow must declare top-level read-only contents permission: $workflowRelativePath")
        }
        if ($workflowContent -match '(?im)^\s*permissions:\s*write-all\s*(?:#.*)?$' -or $workflowContent -match '(?im)^\s*[a-z][a-z-]*:\s*write\s*(?:#.*)?$') {
            $errors.Add("Workflow must not declare write permissions: $workflowRelativePath")
        }

        foreach ($actionMatch in [regex]::Matches($workflowContent, '(?m)^\s*(?:-\s*)?uses:\s*(?<reference>[^\s#]+)')) {
            $actionReference = $actionMatch.Groups['reference'].Value
            if ($actionReference.StartsWith('./') -or $actionReference.StartsWith('.\\')) {
                continue
            }

            if ($actionReference.StartsWith('docker://')) {
                if ($actionReference -notmatch '^docker://[^@\s]+@sha256:[0-9a-fA-F]{64}$') {
                    $errors.Add("Docker action must be pinned by sha256 digest in ${workflowRelativePath}: $actionReference")
                }
                continue
            }

            if ($actionReference -notmatch '^[^@\s]+@[0-9a-fA-F]{40}$') {
                $errors.Add("Action must be pinned to a full 40-character commit SHA in ${workflowRelativePath}: $actionReference")
            }
        }

        if ($workflowContent -match 'uses:\s*actions/checkout@' -and $workflowContent -notmatch '(?m)^\s+persist-credentials:\s*false\s*(?:#.*)?$') {
            $errors.Add("actions/checkout must disable persisted credentials in $workflowRelativePath")
        }
    }
}

$markdownFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.md' |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]\.local-docs[\\/]'
    }

$linkPattern = [regex]'\[[^\]]*\]\((?<target>[^)]+)\)'
$undesiredEnglishProse = [ordered]@{
    '\btooling\b' = 'инструменты'
    '\bmanaged(?:-|\b)' = 'управляемый'
    '\bread-only\b' = 'только для чтения'
    '\bplaceholders?\b' = 'незаполненные места'
    '\breleases?\b' = 'выпуск'
    '\bremote fetch\b' = 'удалённая загрузка'
    '\brollout\b' = 'внедрение'
    '\bbaseline\b' = 'исходный уровень или базовый набор'
    '\bdefault\b' = 'по умолчанию'
    '\bsnapshot\b' = 'снимок'
}

foreach ($file in $markdownFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8

    foreach ($match in $linkPattern.Matches($content)) {
        $target = $match.Groups['target'].Value.Trim()

        if ($target.StartsWith('<') -and $target.EndsWith('>')) {
            $target = $target.Substring(1, $target.Length - 2)
        }

        if (
            $target.StartsWith('#') -or
            $target -match '^(?i:https?|mailto|tel):'
        ) {
            continue
        }

        $pathPart = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($pathPart)) {
            continue
        }

        $decodedPath = [Uri]::UnescapeDataString($pathPart)
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $decodedPath))

        if (-not (Test-Path -LiteralPath $candidate)) {
            $relativeFile = Get-RepoRelativePath -Path $file.FullName
            $errors.Add("Broken local link in ${relativeFile}: $target")
        }
    }

    $insideFencedCode = $false
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
        $lineNumber++
        if ($line -match '^\s*(?:```|~~~)') {
            $insideFencedCode = -not $insideFencedCode
            continue
        }
        if ($insideFencedCode) {
            continue
        }

        $proseLine = [regex]::Replace($line, '`[^`]*`', '')
        foreach ($termPattern in $undesiredEnglishProse.Keys) {
            if ($proseLine -match '[А-Яа-яЁё]' -and $proseLine -match "(?i)$termPattern") {
                $relativeFile = Get-RepoRelativePath -Path $file.FullName
                $errors.Add("Смешение языков в ${relativeFile}:$lineNumber. Используйте '$($undesiredEnglishProse[$termPattern])' или оформите точный идентификатор как код.")
            }
        }
    }
}

$rootReadmePath = Join-Path $repoRoot 'README.md'
if (Test-Path -LiteralPath $rootReadmePath -PathType Leaf) {
    $rootReadmeContent = Get-Content -LiteralPath $rootReadmePath -Raw -Encoding UTF8
    $readmeParts = @($rootReadmeContent -split '(?m)^## Kit development\s*$', 2)
    if ($readmeParts.Count -ne 2) {
        $errors.Add('README.md must separate the short user path from maintainer details.')
    }
    else {
        $userReadme = $readmeParts[0]
        if ($userReadme -match '(?i)manifest|lock\.json|revision|profiles|topics|workflow|effective|catalog|upstream|SyncPlan|State:') {
            $errors.Add('README.md user path must not expose internal kit vocabulary.')
        }
        if (([regex]::Matches($userReadme, '(?m)^## ')).Count -ne 3) {
            $errors.Add('README.md user path must contain only installation, connection, and update sections.')
        }
    }
}

$catalog = $null
$catalogPath = Join-Path $repoRoot 'sync/catalog.json'
if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
    try {
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($catalog.schemaVersion -ne '0.1') {
            $errors.Add("Unsupported catalog schemaVersion: $($catalog.schemaVersion)")
        }

        $catalogSources = [System.Collections.Generic.List[string]]::new()
        foreach ($coreFile in @($catalog.core)) {
            $catalogSources.Add([string]$coreFile)
            $coreMetadata = $catalog.coreMetadata.PSObject.Properties[[string]$coreFile]
            if ($null -eq $coreMetadata) {
                $errors.Add("Core '$coreFile' has no routing metadata.")
            }
            elseif (
                [string]$coreMetadata.Value.kind -ne 'core' -or
                [string]::IsNullOrWhiteSpace([string]$coreMetadata.Value.description) -or
                [string]::IsNullOrWhiteSpace([string]$coreMetadata.Value.readWhen)
            ) {
                $errors.Add("Core '$coreFile' has invalid routing metadata.")
            }
        }
        $topicFileOwners = @{}
        foreach ($topicProperty in $catalog.topics.PSObject.Properties) {
            if ([string]::IsNullOrWhiteSpace([string]$topicProperty.Value.file)) {
                $errors.Add("Topic '$($topicProperty.Name)' has no file.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$topicProperty.Value.description)) {
                $errors.Add("Topic '$($topicProperty.Name)' has no description.")
            }
            if ([string]$topicProperty.Value.kind -notin @('rule', 'workflow') -or [string]::IsNullOrWhiteSpace([string]$topicProperty.Value.readWhen)) {
                $errors.Add("Topic '$($topicProperty.Name)' has invalid routing metadata.")
            }
            $topicFile = ([string]$topicProperty.Value.file).Replace('\', '/')
            $catalogSources.Add($topicFile)
            if ($topicFile -in @('rules/README.md', 'rules/CORE.md')) {
                $errors.Add("Catalog topic '$($topicProperty.Name)' references a reserved rule file: $topicFile")
            }
            if (-not [string]::IsNullOrWhiteSpace($topicFile)) {
                if ($topicFileOwners.ContainsKey($topicFile)) {
                    $errors.Add("Multiple catalog topics reference the same rule file: $topicFile")
                }
                else {
                    $topicFileOwners[$topicFile] = [string]$topicProperty.Name
                }
            }
        }
        $profileFileOwners = @{}
        foreach ($profileProperty in $catalog.profiles.PSObject.Properties) {
            if ([string]::IsNullOrWhiteSpace([string]$profileProperty.Value.description)) {
                $errors.Add("Profile '$($profileProperty.Name)' has no description.")
            }
            if ([string]::IsNullOrWhiteSpace([string]$profileProperty.Value.file)) {
                $errors.Add("Profile '$($profileProperty.Name)' has no file.")
            }
            if ([string]$profileProperty.Value.kind -ne 'profile' -or [string]::IsNullOrWhiteSpace([string]$profileProperty.Value.readWhen)) {
                $errors.Add("Profile '$($profileProperty.Name)' has invalid routing metadata.")
            }
            if (@($profileProperty.Value.topics).Count -eq 0) {
                $errors.Add("Profile '$($profileProperty.Name)' has no topic composition.")
            }
            $profileFile = ([string]$profileProperty.Value.file).Replace('\', '/')
            $catalogSources.Add($profileFile)
            if ($profileFile -eq 'profiles/README.md') {
                $errors.Add("Catalog profile '$($profileProperty.Name)' references a reserved profile file: $profileFile")
            }
            if (-not [string]::IsNullOrWhiteSpace($profileFile)) {
                if ($profileFileOwners.ContainsKey($profileFile)) {
                    $errors.Add("Multiple catalog profiles reference the same profile file: $profileFile")
                }
                else {
                    $profileFileOwners[$profileFile] = [string]$profileProperty.Name
                }
            }
            foreach ($profileTopic in @($profileProperty.Value.topics)) {
                if ($null -eq $catalog.topics.PSObject.Properties[[string]$profileTopic]) {
                    $errors.Add("Profile '$($profileProperty.Name)' references unknown topic: $profileTopic")
                }
            }
        }

        foreach ($catalogSource in $catalogSources) {
            if ([System.IO.Path]::IsPathRooted($catalogSource) -or $catalogSource -match '(^|[\\/])\.\.([\\/]|$)') {
                $errors.Add("Catalog source must stay inside the hub: $catalogSource")
                continue
            }
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $catalogSource) -PathType Leaf)) {
                $errors.Add("Catalog source does not exist: $catalogSource")
            }
        }

        $rulesRoot = Join-Path $repoRoot 'rules'
        foreach ($ruleFile in @(Get-ChildItem -LiteralPath $rulesRoot -File -Filter '*.md')) {
            if ($ruleFile.Name -in @('README.md', 'CORE.md')) {
                continue
            }
            $ruleRelativePath = 'rules/' + $ruleFile.Name
            if (-not $topicFileOwners.ContainsKey($ruleRelativePath)) {
                $errors.Add("Rule file is not registered in catalog: $ruleRelativePath")
            }
        }

        $profilesRoot = Join-Path $repoRoot 'profiles'
        foreach ($profileFile in @(Get-ChildItem -LiteralPath $profilesRoot -File -Filter '*.md')) {
            if ($profileFile.Name -eq 'README.md') {
                continue
            }
            $profileRelativePath = 'profiles/' + $profileFile.Name
            if (-not $profileFileOwners.ContainsKey($profileRelativePath)) {
                $errors.Add("Profile file is not registered in catalog: $profileRelativePath")
            }
        }

        foreach ($profileProperty in $catalog.profiles.PSObject.Properties) {
            $profilePath = Join-Path $repoRoot ([string]$profileProperty.Value.file)
            if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
                $profileContent = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8
                if ($profileContent -notmatch '(?m)^## Назначение\s*$' -or $profileContent -notmatch '(?m)^## Уникальные обязательства\s*$') {
                    $errors.Add("Profile '$($profileProperty.Name)' must contain purpose and unique obligations.")
                }
                if ($profileContent -match '(?m)^##? Подключить' -or $profileContent -match '\.\./rules/') {
                    $errors.Add("Profile '$($profileProperty.Name)' must use catalog composition instead of embedded topic links.")
                }
            }
        }
    }
    catch {
        $errors.Add("Invalid sync catalog: $($_.Exception.Message)")
    }
}

$jsonFiles = @(
    'sync/project-manifest.schema.json',
    'sync/project-manifest.example.json'
)
$manifestSchema = $null
foreach ($jsonFile in $jsonFiles) {
    $jsonPath = Join-Path $repoRoot $jsonFile
    if (Test-Path -LiteralPath $jsonPath -PathType Leaf) {
        try {
            $jsonObject = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($jsonFile -eq 'sync/project-manifest.schema.json') {
                $manifestSchema = $jsonObject
            }
        }
        catch {
            $errors.Add("Invalid JSON in ${jsonFile}: $($_.Exception.Message)")
        }
    }
}

if ($null -ne $catalog -and $null -ne $manifestSchema) {
    $catalogTopicIds = @($catalog.topics.PSObject.Properties.Name | Sort-Object -Unique)
    $schemaTopicIdsRaw = @($manifestSchema.properties.topics.items.enum | ForEach-Object { [string]$_ })
    $schemaTopicIds = @($schemaTopicIdsRaw | Sort-Object -Unique)
    if (
        $schemaTopicIdsRaw.Count -ne $schemaTopicIds.Count -or
        ($catalogTopicIds -join "`n") -ne ($schemaTopicIds -join "`n")
    ) {
        $errors.Add('Manifest schema topic enum must exactly match catalog topics.')
    }

    $catalogProfileIds = @($catalog.profiles.PSObject.Properties.Name | Sort-Object -Unique)
    $schemaProfileIdsRaw = @($manifestSchema.properties.profiles.items.enum | ForEach-Object { [string]$_ })
    $schemaProfileIds = @($schemaProfileIdsRaw | Sort-Object -Unique)
    if (
        $schemaProfileIdsRaw.Count -ne $schemaProfileIds.Count -or
        ($catalogProfileIds -join "`n") -ne ($schemaProfileIds -join "`n")
    ) {
        $errors.Add('Manifest schema profile enum must exactly match catalog profiles.')
    }
}

$textFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/]\.local-docs[\\/]' -and (
            $_.Extension -in @('.md', '.ps1', '.json', '.yml', '.yaml') -or
            $_.Name -eq '.gitattributes' -or
            $_.FullName -match '[\\/]\.githooks[\\/]'
        )
    }

foreach ($file in $textFiles) {
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
        $lineNumber++
        if ($line -match '[ \t]+$') {
            $relativeFile = Get-RepoRelativePath -Path $file.FullName
            $errors.Add("Trailing whitespace in ${relativeFile}:$lineNumber")
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host "Hub validation failed with $($errors.Count) error(s):" -ForegroundColor Red
    foreach ($validationError in $errors) {
        Write-Host "- $validationError" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Hub validation passed: $($markdownFiles.Count) Markdown and $($textFiles.Count) text files checked." -ForegroundColor Green

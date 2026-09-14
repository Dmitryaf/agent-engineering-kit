[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string[]]$Topics = @(),

    [string[]]$Profiles = @(),

    [switch]$SeedProjectFiles
)

$ErrorActionPreference = 'Stop'

function Get-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Label должен быть относительным путём: $RelativePath"
    }

    $rootFullPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootFullPath $RelativePath))
    $prefix = $rootFullPath + [System.IO.Path]::DirectorySeparatorChar

    if (-not $candidate.StartsWith($prefix, (Get-AiRulesPathComparison))) {
        throw "$Label выходит за пределы корня проекта: $RelativePath"
    }

    return $candidate
}

function Get-RulesetSeedContent {
    param(
        [Parameter(Mandatory = $true)][string]$TemplatePath,
        [string[]]$SelectedProfiles,
        [string[]]$SelectedTopics
    )

    $content = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
    $newLine = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $profileLines = @(
        if (@($SelectedProfiles).Count -eq 0) {
            '- Пока не выбраны.'
        }
        else {
            foreach ($profile in @($SelectedProfiles | Sort-Object -Unique)) {
                '- `{0}` — `<почему выбран>`' -f $profile
            }
        }
    )
    $topicLines = @(
        if (@($SelectedTopics).Count -eq 0) {
            '- Пока не выбраны.'
        }
        else {
            foreach ($topic in @($SelectedTopics | Sort-Object -Unique)) {
                '- `{0}` — `<почему подключена отдельно>`' -f $topic
            }
        }
    )

    $content = $content.Replace('- `<профиль>` — `<почему выбран>`', ($profileLines -join $newLine))
    return $content.Replace('- `<тема>` — `<почему подключена отдельно>`', ($topicLines -join $newLine))
}

$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$projectRootFull = (Resolve-Path -LiteralPath $ProjectRoot).Path
. (Join-Path $hubRoot 'scripts/sync-common.ps1')
$catalogPath = Join-Path $hubRoot 'sync/catalog.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($catalog.schemaVersion -ne '0.1') {
    throw "Неподдерживаемая catalog schemaVersion: $($catalog.schemaVersion)"
}

$availableTopics = @($catalog.topics.PSObject.Properties.Name)
$availableProfiles = @($catalog.profiles.PSObject.Properties.Name)

$Topics = @(
    foreach ($topicValue in @($Topics)) {
        foreach ($topicPart in ([string]$topicValue -split ',')) {
            if (-not [string]::IsNullOrWhiteSpace($topicPart)) {
                $topicPart.Trim()
            }
        }
    }
)
$Profiles = @(
    foreach ($profileValue in @($Profiles)) {
        foreach ($profilePart in ([string]$profileValue -split ',')) {
            if (-not [string]::IsNullOrWhiteSpace($profilePart)) {
                $profilePart.Trim()
            }
        }
    }
)

foreach ($topic in $Topics) {
    if ($topic -notin $availableTopics) {
        throw "Неизвестная тема '$topic'. Доступны: $($availableTopics -join ', ')"
    }
}

foreach ($profile in $Profiles) {
    if ($profile -notin $availableProfiles) {
        throw "Неизвестный профиль '$profile'. Доступны: $($availableProfiles -join ', ')"
    }
}

$localRulesRoot = Get-PathInsideRoot -Root $projectRootFull -RelativePath '.ai-rules' -Label 'Local rules directory'
$manifestPath = Join-Path $localRulesRoot 'manifest.json'
$unsupportedRootSyncFiles = @(Get-ChildItem -LiteralPath $projectRootFull -Force -File -Filter '.ai-*.json')
foreach ($unsupportedRootSyncFile in $unsupportedRootSyncFiles) {
    throw "Обнаружен неподдерживаемый корневой sync-файл. Просмотрите и перенесите его явно до инициализации: $($unsupportedRootSyncFile.FullName)"
}

if (Test-Path -LiteralPath $manifestPath) {
    throw "Sync manifest уже существует и не будет перезаписан: $manifestPath"
}

if (-not (Test-Path -LiteralPath $localRulesRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $localRulesRoot | Out-Null
    Write-Host "[CREATED] Создан каталог: $localRulesRoot" -ForegroundColor Green
}

$manifest = [ordered]@{
    schemaVersion = '0.2'
    source = [ordered]@{
        repository = 'agent-engineering-kit'
        revision = $null
    }
    topics = @($Topics | Sort-Object -Unique)
    profiles = @($Profiles | Sort-Object -Unique)
}

$manifestJson = (ConvertTo-AiRulesJson -InputObject $manifest -Depth 6) + "`n"
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8WithoutBom)
Write-Host "[CREATED] Создан manifest: $manifestPath" -ForegroundColor Green

if ($SeedProjectFiles) {
    $seedFiles = @(
        [pscustomobject]@{ Name = 'AGENTS.md'; TargetRoot = $projectRootFull },
        [pscustomobject]@{ Name = 'RULESET.md'; TargetRoot = $localRulesRoot },
        [pscustomobject]@{ Name = 'PROJECT_RULES.md'; TargetRoot = $localRulesRoot }
    )

    foreach ($seedFile in $seedFiles) {
        $sourcePath = Join-Path $hubRoot "templates/$($seedFile.Name)"
        $targetPath = Join-Path $seedFile.TargetRoot $seedFile.Name
        if (Test-Path -LiteralPath $targetPath) {
            Write-Host "[SKIP] Пропущен существующий пользовательский файл: $targetPath" -ForegroundColor Yellow
            continue
        }

        if ($seedFile.Name -eq 'RULESET.md') {
            $rulesetContent = Get-RulesetSeedContent -TemplatePath $sourcePath -SelectedProfiles $Profiles -SelectedTopics $Topics
            Set-Content -LiteralPath $targetPath -Value $rulesetContent -Encoding UTF8
        }
        else {
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath
        }
        Write-Host "[CREATED] Создан пользовательский файл: $targetPath" -ForegroundColor Green
    }
}

Write-Host 'Инициализация не применяет правила автоматически.'
Write-Host "Следующий шаг: .\ai-rules.ps1 update -ProjectRoot `"$projectRootFull`""
Write-Host 'После первого update -Apply используйте .\ai-rules.ps1 prompt audit.'

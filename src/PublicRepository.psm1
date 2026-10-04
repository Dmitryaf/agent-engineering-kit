Import-Module (Join-Path $PSScriptRoot 'GitState.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'PathsAndHashing.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Contracts.psm1') -ErrorAction Stop

function Get-AiRulesProjectGitBoundary {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    try {
        $top = @(Invoke-AiRulesGitText -Arguments @('-C', $ProjectRoot, 'rev-parse', '--show-toplevel'))
    }
    catch {
        # A Git failure inside a checkout must not silently disable protection.
        $cursor = $ProjectRoot
        while (-not [string]::IsNullOrWhiteSpace($cursor)) {
            if (Test-Path -LiteralPath (Join-Path $cursor '.git')) { throw 'Git checkout недоступен; локальные исключения не установлены.' }
            $cursor = Split-Path -Parent $cursor
        }
        return $null
    }
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($top[0]).TrimEnd([char[]]@('\', '/')), $ProjectRoot.TrimEnd([char[]]@('\', '/')), (Get-AiRulesPathComparison))) {
        throw 'Для public-repository ProjectRoot должен быть корнем Git checkout.'
    }
    $gitDir = @(Invoke-AiRulesGitText -Arguments @('-C', $ProjectRoot, 'rev-parse', '--git-common-dir'))
    $commonRoot = if ([System.IO.Path]::IsPathRooted($gitDir[0])) { [System.IO.Path]::GetFullPath($gitDir[0]) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $gitDir[0])) }
    $excludePath = Get-AiRulesSafePath -BasePath $commonRoot -ChildPath 'info/exclude' -Label 'Git exclude'
    return [pscustomobject]@{ ExcludePath = $excludePath; CommonRoot = $commonRoot }
}

function Get-AiRulesLocalOnlyPlan {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $boundary = Get-AiRulesProjectGitBoundary -ProjectRoot $ProjectRoot
    if ($null -eq $boundary) { return [pscustomobject]@{ Git = $false; Changed = $false; Path = $null; Content = $null; Boundary = $null } }
    $path = $boundary.ExcludePath
    $content = if (Test-Path -LiteralPath $path -PathType Leaf) { [System.IO.File]::ReadAllText($path) } else { '' }
    $begin = '# BEGIN agent-engineering-kit'
    $end = '# END agent-engineering-kit'
    $beginCount = [regex]::Matches($content, '(?m)^' + [regex]::Escape($begin) + '\r?$').Count
    $endCount = [regex]::Matches($content, '(?m)^' + [regex]::Escape($end) + '\r?$').Count
    $pattern = '(?ms)^' + [regex]::Escape($begin) + '\r?\n.*?^' + [regex]::Escape($end) + '(?:\r?\n|\z)'
    if ($beginCount -ne $endCount -or $beginCount -gt 1 -or ($beginCount -eq 1 -and -not [regex]::IsMatch($content, $pattern))) {
        throw 'Повреждён управляемый блок Kit в Git exclude; исправьте его вручную.'
    }
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $userContent = [regex]::Replace($content, $pattern, '')
    # Put the block last so a preceding user negation cannot re-enable runtime files.
    $prefix = $userContent
    if ($prefix.Length -gt 0 -and -not $prefix.EndsWith("`n")) { $prefix += $newline }
    $managedPatterns = @(
        foreach ($rule in @('/.ai-rules/', '/AGENTS.md', '/.local/')) {
            $alreadyPresent = $userContent -match ('(?m)^' + [regex]::Escape($rule) + '\r?$')
            # Keep a final rule when negations exist; otherwise reuse the user's identical rule.
            if (-not $alreadyPresent -or $userContent -match '(?m)^!') { $rule }
        }
    )
    $block = (@($begin) + $managedPatterns + @($end)) -join $newline
    $nextContent = $prefix + $block + $newline
    return [pscustomobject]@{ Git = $true; Changed = $nextContent -cne $content; Path = $path; Content = $nextContent; Boundary = $boundary }
}

function Set-AiRulesLocalOnlyExclude {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $plan = Get-AiRulesLocalOnlyPlan -ProjectRoot $ProjectRoot
    if (-not $plan.Git -or -not $plan.Changed) { return $plan }
    [void](Get-AiRulesSafePath -BasePath $plan.Boundary.CommonRoot -ChildPath 'info/exclude' -Label 'Git exclude')
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $plan.Path)) | Out-Null
    $hasBom = $false
    if ([System.IO.File]::Exists($plan.Path)) {
        $bytes = [System.IO.File]::ReadAllBytes($plan.Path)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    }
    $temporaryPath = Join-Path (Split-Path -Parent $plan.Path) ('exclude.kit-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $plan.Content, (New-Object System.Text.UTF8Encoding($hasBom)))
        [void](Get-AiRulesSafePath -BasePath $plan.Boundary.CommonRoot -ChildPath 'info/exclude' -Label 'Git exclude')
        if ([System.IO.File]::Exists($plan.Path)) { [System.IO.File]::Replace($temporaryPath, $plan.Path, [NullString]::Value) }
        else { [System.IO.File]::Move($temporaryPath, $plan.Path) }
    }
    finally {
        if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
    }
    return $plan
}

function Get-AiRulesPrivateContextState {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    try {
        $path = Get-AiRulesSafePath -BasePath $ProjectRoot -ChildPath '.ai-rules/private-context.json' -Label 'Private context descriptor'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'not configured' }
        $descriptor = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($field in @('project', 'source', 'recovery')) {
            if ($descriptor.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($descriptor.$field)) { return 'unavailable' }
        }
        if ($descriptor.schemaVersion -ne '0.1' -or -not [System.IO.Path]::IsPathRooted([string]$descriptor.source)) { return 'unavailable' }
        $source = [System.IO.Path]::GetFullPath([string]$descriptor.source).TrimEnd([char[]]@('\', '/'))
        $root = $ProjectRoot.TrimEnd([char[]]@('\', '/'))
        if ([string]::Equals($source, $root, (Get-AiRulesPathComparison)) -or $source.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, (Get-AiRulesPathComparison))) { return 'unavailable' }
        # Do not follow a link into the public checkout and claim an external boundary.
        $cursor = $source
        while (-not [string]::IsNullOrWhiteSpace($cursor)) {
            if (Test-Path -LiteralPath $cursor) {
                if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return 'unavailable' }
            }
            $cursor = Split-Path -Parent $cursor
        }
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { return 'unavailable' }
        return 'configured'
    }
    catch { return 'unavailable' }
}

function Get-AiRulesPublicRepositoryState {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $results = [System.Collections.Generic.List[object]]::new()
    $trackedRuntime = @()
    $potentialDocuments = [System.Collections.Generic.List[string]]::new()
    $publicDocuments = [System.Collections.Generic.List[string]]::new()
    $privateDocuments = [System.Collections.Generic.List[string]]::new()
    $runtime = 'unprotected'
    try {
        $plan = Get-AiRulesLocalOnlyPlan -ProjectRoot $ProjectRoot
        if (-not $plan.Git) { $runtime = 'no Git' }
        else {
            $trackedText = @(Invoke-AiRulesGitText -Arguments @('-C', $ProjectRoot, '-c', 'core.quotePath=false', 'ls-files', '--cached', '-z')) -join "`n"
            $tracked = @($trackedText -split [char]0 | Where-Object { $_.Length -gt 0 })
            $trackedRuntime = @($tracked | Where-Object { $_ -eq 'AGENTS.md' -or $_ -match '^\.(ai-rules|local)/' })
            if ($trackedRuntime.Count -gt 0) { $runtime = 'tracked' }
            elseif (-not $plan.Changed) {
                $ignored = @(Invoke-AiRulesGitText -Arguments @('-C', $ProjectRoot, 'check-ignore', '--no-index', '--', 'AGENTS.md', '.ai-rules/manifest.json', '.local/kit-probe'))
                if ($ignored.Count -eq 3) { $runtime = 'local-only' }
            }
            foreach ($file in @($tracked | Where-Object { $_ -like '*.md' -and $_ -notin $trackedRuntime })) {
                # Check indexed content: a working-tree edit does not remove staged private data.
                $content = @(Invoke-AiRulesGitText -Arguments @('-C', $ProjectRoot, 'show', (':' + $file))) -join "`n"
                $header = [regex]::Match($content.TrimStart([char]0xFEFF), '\A---\r?\n(?<body>.*?)\r?\n---(?:\r?\n|\z)', 'Singleline')
                $private = $header.Success -and $header.Groups['body'].Value -match '(?m)^visibility:[ \t]*(?:private|"private"|''private'')[ \t]*(?:#.*)?$'
                $public = $header.Success -and $header.Groups['body'].Value -match '(?m)^visibility:[ \t]*(?:repository|"repository"|''repository'')[ \t]*(?:#.*)?$'
                if ($private) { $privateDocuments.Add($file) }
                elseif ($file -match '(^|/)(DECISIONS|PROJECT_MAP)\.md$|^(decisions|docs/adr|architecture)/') {
                    if ($public) { $publicDocuments.Add($file) } else { $potentialDocuments.Add($file) }
                }
            }
        }
    }
    catch {
        $runtime = 'unavailable'
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'publication' -Message 'Не удалось проверить локальную границу Git; состояние публикации неизвестно.'))
    }
    if ($trackedRuntime.Count -gt 0) {
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'publication' -Message ('В публичном репозитории отслеживаются внутренние файлы: ' + ($trackedRuntime -join ', ') + '. Exclude не прекращает отслеживание. Используйте local-only для плана перехода.')))
    }
    if ($runtime -eq 'unprotected') {
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'publication' -Message 'Локальные исключения Kit не обеспечены; выполните local-only, затем local-only -Apply.'))
    }
    foreach ($file in $privateDocuments) {
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'publication' -Message "В Git index находится $file с visibility: private. Поле не защищает файл в публичном Git; требуется перенос после аудита."))
    }
    foreach ($file in $potentialDocuments) {
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'publication' -Message "Проверьте аудиторию и необходимость публикации $file; имя документа не доказывает нарушение."))
    }
    $context = Get-AiRulesPrivateContextState -ProjectRoot $ProjectRoot
    if ($context -ne 'configured') {
        $results.Add((New-AiRulesDiagnostic -Level 'WARN' -Category 'private-context' -Message "Private context: $context. Обычная разработка доступна; сохранность долгоживущего приватного контекста не подтверждена."))
    }
    return [pscustomobject]@{
        Runtime = $runtime
        PrivateContext = $context
        TrackedRuntime = $trackedRuntime
        PotentialDocuments = @($potentialDocuments)
        PublicDocuments = @($publicDocuments)
        PrivateDocuments = @($privateDocuments)
        Diagnostics = @($results)
    }
}

Export-ModuleMember -Function @('Get-AiRulesLocalOnlyPlan', 'Set-AiRulesLocalOnlyExclude', 'Get-AiRulesPublicRepositoryState')

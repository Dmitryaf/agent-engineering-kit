Import-Module (Join-Path $PSScriptRoot 'PathsAndHashing.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'GitState.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Catalog.psm1') -ErrorAction Stop

function Read-AekText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-AekText {
    param([string]$Path, [string]$Content)
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-AekAtomicText {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    $temporaryPath = Get-AiRulesSafePath -BasePath $parent -ChildPath ('aek-' + [Guid]::NewGuid().ToString('N') + '.tmp') -Label 'atomic text staging'
    try {
        Write-AekText -Path $temporaryPath -Content $Content
        [void](Get-AiRulesSafePath -BasePath $parent -ChildPath (Split-Path -Leaf $Path) -Label 'atomic text target')
        if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($temporaryPath, $Path, [NullString]::Value) }
        else { [System.IO.File]::Move($temporaryPath, $Path) }
    }
    finally { if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) } }
}

function Get-AekCoreExcerpt {
    param([string]$Core, [string[]]$Sections)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($section in $Sections) {
        $pattern = '(?ms)^## ' + [regex]::Escape($section) + '\n.*?(?=^## |\z)'
        $matches = [regex]::Matches($Core, $pattern)
        if ($matches.Count -ne 1) { throw "CORE section missing or ambiguous: $section" }
        $result.Add($matches[0].Value.TrimEnd())
    }
    return ($result -join "`n`n") + "`n"
}

function Get-AekBundleDigest {
    param($Identity)
    return Get-AiRulesSha256Text -Content (ConvertTo-AiRulesJson -InputObject $Identity)
}

function New-AekReleasePlan {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)
    $sourceRootFull = (Resolve-Path -LiteralPath $SourceRoot).Path
    $gitRoot = ([string](@(Invoke-AiRulesGitText -Arguments @('-C', $sourceRootFull, 'rev-parse', '--show-toplevel'))[0])).Trim()
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($gitRoot), $sourceRootFull, (Get-AiRulesPathComparison))) {
        throw 'SourceRoot must be the Kit repository root.'
    }
    $canonicalArgs = @('rules', 'profiles', 'workflows', 'templates', 'sync/catalog.json', 'sync/README.md', 'LICENSE')
    $dirty = @(Invoke-AiRulesGitText -Arguments (@('-C', $sourceRootFull, 'status', '--porcelain', '--untracked-files=all', '--') + $canonicalArgs))
    if ($dirty.Count -gt 0) { throw 'Canonical sources must match a committed revision. Tooling changes may remain uncommitted.' }
    $revision = (Get-AiRulesHubGitState -HubRoot $sourceRootFull).Revision
    $paths = @(Invoke-AiRulesGitText -Arguments (@('-C', $sourceRootFull, 'ls-files', '--') + $canonicalArgs) | Sort-Object)
    $contents = [ordered]@{}
    foreach ($path in $paths) {
        $safe = Get-AiRulesSafePath -BasePath $sourceRootFull -ChildPath $path -Label 'canonical source'
        if (-not (Test-Path -LiteralPath $safe -PathType Leaf)) { throw "Canonical source missing: $path" }
        $contents[$path] = Read-AekText -Path $safe
    }
    $catalog = Get-AiRulesCatalog -HubRoot $sourceRootFull
    $builderRoot = Split-Path -Parent $PSScriptRoot
    $adapter = (Read-AekText -Path (Join-Path $builderRoot 'adapters/codex/adapter.json')) | ConvertFrom-Json
    $recipe = (Read-AekText -Path (Join-Path $builderRoot 'skills/project-audit.json')) | ConvertFrom-Json
    if ($adapter.id -ne 'codex' -or $adapter.schemaVersion -ne '0.1' -or $recipe.schemaVersion -ne '0.1' -or $recipe.name -ne 'aek-project-audit' -or $recipe.workflow -ne $catalog.topics.'project-audit'.file) {
        throw 'Unsupported adapter or skill recipe.'
    }
    $sourceEntries = @($contents.Keys | ForEach-Object { [ordered]@{ path = $_; sha256 = Get-AiRulesSha256Text -Content $contents[$_] } })
    $contents['adapter.json'] = (ConvertTo-AiRulesJson -InputObject $adapter) + "`n"
    $contents['bootstrap.md'] = Get-AekCoreExcerpt -Core $contents['rules/CORE.md'] -Sections $adapter.coreSections
    $skillRoot = 'skills/' + $recipe.name
    # Keep the exact canonical workflow and its relative links inside the skill.
    foreach ($path in @($contents.Keys | Where-Object { $_ -match '^(rules|profiles|workflows|templates|sync)/' })) {
        $contents["$skillRoot/references/$path"] = $contents[$path]
    }
    $workflowHash = Get-AiRulesSha256Text -Content $contents[$recipe.workflow]
    $skillText = @(
        '---', "name: $($recipe.name)", "description: $($recipe.description)", '---', '',
        "<!-- Generated from $($recipe.workflow); source SHA-256: $workflowHash. Do not edit. -->", '',
        '# Project audit', '',
        'The shared project connection already selects project-audit. Read the canonical workflow below and apply its audit procedure.',
        'The snapshot connection paragraph describes only legacy setup; do not create or update a snapshot manifest, lock, or upstream for this shared connection.', '',
        "[Canonical audit workflow](references/$($recipe.workflow))", '',
        'Resolve this resource link relative to the directory containing this SKILL.md. Apply the procedure and report contract in that resource.', '',
        'Read the selected project profiles and relevant topics using the project entry point. Preserve its authority and local constraints.', '',
        'Audit and policy resources are bundled here. Administrative links to repository setup, tooling, contribution guidance, and eval infrastructure remain reference-only; they do not authorize snapshot onboarding or running hub tools from this skill.'
    ) -join "`n"
    $contents["$skillRoot/SKILL.md"] = $skillText + "`n"
    $builder = @('src/SharedInstall.psm1', 'src/CodexAdapter.psm1', 'src/PathsAndHashing.psm1', 'src/Catalog.psm1', 'src/GitState.psm1', 'src/PublicRepository.psm1', 'src/Contracts.psm1', 'scripts/shared-kit.ps1', 'adapters/codex/adapter.json', 'skills/project-audit.json') | ForEach-Object {
        [ordered]@{ path = $_; sha256 = Get-AiRulesSha256 -Path (Join-Path $builderRoot $_) }
    }
    $entries = @($contents.Keys | Sort-Object | ForEach-Object { [ordered]@{ path = $_; sha256 = Get-AiRulesSha256Text -Content $contents[$_] } })
    $identity = [ordered]@{ schemaVersion = '0.1'; sourceRevision = $revision; builder = @($builder); sources = $sourceEntries; files = $entries }
    $digest = Get-AekBundleDigest -Identity $identity
    $releaseId = 'r-' + $revision.Substring(0, 12) + '-' + $digest.Substring(0, 20)
    $manifest = [ordered]@{ schemaVersion = '0.1'; releaseId = $releaseId; digest = $digest; identity = $identity }
    $contents['release.json'] = (ConvertTo-AiRulesJson -InputObject $manifest) + "`n"
    $dirtyAfter = @(Invoke-AiRulesGitText -Arguments (@('-C', $sourceRootFull, 'status', '--porcelain', '--untracked-files=all', '--') + $canonicalArgs))
    if ($dirtyAfter.Count -gt 0 -or (Get-AiRulesHubGitState -HubRoot $sourceRootFull).Revision -ne $revision) { throw 'Canonical sources changed while building the release.' }
    return [pscustomobject]@{ ReleaseId = $releaseId; Manifest = $manifest; Contents = $contents }
}

function Get-AekReleasePath {
    param([string]$InstallRoot, [string]$ReleaseId)
    if ($ReleaseId -notmatch '^r-[0-9a-f]{12}-[0-9a-f]{20}$') { throw 'Invalid release ID.' }
    return Get-AiRulesSafePath -BasePath $InstallRoot -ChildPath "releases/$ReleaseId" -Label 'release'
}

function Test-AekRelease {
    param([Parameter(Mandatory = $true)][string]$ReleaseRoot)
    $manifestPath = Get-AiRulesSafePath -BasePath $ReleaseRoot -ChildPath 'release.json' -Label 'release metadata'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Shared installation unavailable: release.json missing.' }
    $manifest = (Read-AekText -Path $manifestPath) | ConvertFrom-Json
    if ($manifest.schemaVersion -ne '0.1' -or $manifest.identity.schemaVersion -ne '0.1' -or $manifest.identity.sourceRevision -notmatch '^[0-9a-f]{40}$') { throw 'Invalid release metadata.' }
    $digest = Get-AekBundleDigest -Identity $manifest.identity
    $expectedId = 'r-' + $manifest.identity.sourceRevision.Substring(0, 12) + '-' + $digest.Substring(0, 20)
    if ($manifest.digest -ne $digest -or $manifest.releaseId -ne $expectedId -or (Split-Path -Leaf $ReleaseRoot) -ne $expectedId) { throw 'Release identity integrity failed.' }
    $expectedPaths = [System.Collections.Generic.HashSet[string]]::new((Get-AiRulesPathStringComparer))
    [void]$expectedPaths.Add('release.json')
    foreach ($entry in @($manifest.identity.files)) {
        if (-not $expectedPaths.Add([string]$entry.path)) { throw 'Duplicate release file.' }
        $path = Get-AiRulesSafePath -BasePath $ReleaseRoot -ChildPath $entry.path -Label 'release file'
        if ($entry.sha256 -notmatch '^[0-9a-f]{64}$' -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-AiRulesSha256 -Path $path) -ne $entry.sha256) {
            throw "Release integrity failed: $($entry.path)"
        }
    }
    foreach ($required in @('rules/CORE.md', 'sync/catalog.json', 'adapter.json', 'bootstrap.md', 'skills/aek-project-audit/SKILL.md', 'skills/aek-project-audit/references/workflows/PROJECT_DEEP_AUDIT.md')) {
        if (-not $expectedPaths.Contains($required)) { throw "Required release file missing: $required" }
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $ReleaseRoot -Recurse -Force)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Release contains a reparse point.' }
        if (-not $item.PSIsContainer) {
            $relative = $item.FullName.Substring([System.IO.Path]::GetFullPath($ReleaseRoot).TrimEnd([char[]]@('\', '/')).Length + 1).Replace('\', '/')
            if (-not $expectedPaths.Contains($relative)) { throw "Unexpected release file: $relative" }
        }
    }
    return $manifest
}

function Install-AekRelease {
    param($Plan, [string]$InstallRoot)
    $root = [System.IO.Path]::GetFullPath($InstallRoot)
    $destination = Get-AekReleasePath -InstallRoot $root -ReleaseId $Plan.ReleaseId
    if (Test-Path -LiteralPath $destination) {
        $existing = Test-AekRelease -ReleaseRoot $destination
        if ($existing.digest -ne $Plan.Manifest.digest) { throw 'Refusing to overwrite an immutable release.' }
        return $destination
    }
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
    $stage = Get-AiRulesSafePath -BasePath $root -ChildPath ('.stage-' + [Guid]::NewGuid().ToString('N').Substring(0, 12)) -Label 'install staging'
    [void][System.IO.Directory]::CreateDirectory($stage)
    try {
        $stagedRelease = Join-Path $stage $Plan.ReleaseId
        [void][System.IO.Directory]::CreateDirectory($stagedRelease)
        foreach ($path in $Plan.Contents.Keys) {
            Write-AekText -Path (Get-AiRulesSafePath -BasePath $stagedRelease -ChildPath $path -Label 'staged file') -Content $Plan.Contents[$path]
        }
        [void](Test-AekRelease -ReleaseRoot $stagedRelease)
        if (Test-Path -LiteralPath $destination) { throw 'Release destination appeared during installation; refusing to overwrite it.' }
        Move-Item -LiteralPath $stagedRelease -Destination (Split-Path -Parent $destination) -ErrorAction Stop
        [void](Test-AekRelease -ReleaseRoot $destination)
    }
    finally {
        # Only remove our now-empty staging container; never recursively delete releases.
        if (Test-Path -LiteralPath $stage -PathType Container) {
            if (@(Get-ChildItem -LiteralPath $stage -Force).Count -eq 0) { [System.IO.Directory]::Delete($stage, $false) }
        }
    }
    return $destination
}

function Set-AekSelectedRelease {
    param([string]$InstallRoot, [string]$ReleaseId)
    $root = [System.IO.Path]::GetFullPath($InstallRoot)
    $release = Get-AekReleasePath -InstallRoot $root -ReleaseId $ReleaseId
    $manifest = Test-AekRelease -ReleaseRoot $release
    $selectedPath = Get-AiRulesSafePath -BasePath $root -ChildPath 'selected.json' -Label 'selected release'
    Write-AekAtomicText -Path $selectedPath -Content ((ConvertTo-AiRulesJson -InputObject ([ordered]@{ schemaVersion = '0.1'; releaseId = $ReleaseId; digest = $manifest.digest })) + "`n")
}

function Resolve-AekRelease {
    param([string]$InstallRoot, [string]$ReleaseId)
    $selected = $null
    if ([string]::IsNullOrWhiteSpace($ReleaseId)) {
        $selectedPath = Get-AiRulesSafePath -BasePath $InstallRoot -ChildPath 'selected.json' -Label 'selected release'
        if (-not (Test-Path -LiteralPath $selectedPath -PathType Leaf)) { throw 'No selected release. Install or explicitly select a release first.' }
        $selected = (Read-AekText -Path $selectedPath) | ConvertFrom-Json
        if ($selected.schemaVersion -ne '0.1') { throw 'Invalid selected release metadata.' }
        $ReleaseId = [string]$selected.releaseId
    }
    $path = Get-AekReleasePath -InstallRoot $InstallRoot -ReleaseId $ReleaseId
    $manifest = Test-AekRelease -ReleaseRoot $path
    if ($null -ne $selected -and $selected.digest -ne $manifest.digest) { throw 'Selected release digest mismatch.' }
    return [pscustomobject]@{ Root = $path; Manifest = $manifest }
}

Export-ModuleMember -Function 'New-AekReleasePlan', 'Install-AekRelease', 'Test-AekRelease', 'Resolve-AekRelease', 'Set-AekSelectedRelease', 'Get-AekReleasePath', 'Read-AekText', 'Write-AekText', 'Write-AekAtomicText', 'Get-AekCoreExcerpt'

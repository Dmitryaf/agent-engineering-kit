Import-Module (Join-Path $PSScriptRoot 'SharedInstall.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'PathsAndHashing.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Catalog.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'GitState.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'PublicRepository.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Diagnostics.psm1') -ErrorAction Stop

$aekBlockStart = '<!-- AEK SHARED BEGIN -->'
$aekBlockEnd = '<!-- AEK SHARED END -->'

function Get-AekFileState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Expected a regular project file.' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function New-AekCodexBlock {
    param($Release, [string[]]$Profiles, [string[]]$Topics, [string]$LocalRules)
    $catalog = Get-AiRulesCatalog -HubRoot $Release.Root
    Assert-AiRulesSelections -Catalog $catalog -SelectedProfiles $Profiles -SelectedTopics $Topics
    $effective = @(Get-AiRulesEffectiveTopics -Catalog $catalog -SelectedProfiles $Profiles -SelectedTopics $Topics)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($aekBlockStart)
    $lines.Add('## Agent Engineering Kit: experimental shared connection')
    $lines.Add('')
    $lines.Add("Pinned release: ``$($Release.Manifest.releaseId)``; canonical revision: ``$($Release.Manifest.identity.sourceRevision)``.")
    $lines.Add('Generated from canonical sources. Change the connection through shared-kit; preserve the surrounding project instructions.')
    $lines.Add('')
    $lines.Add((Read-AekText -Path (Join-Path $Release.Root 'bootstrap.md')).TrimEnd())
    $lines.Add('')
    $lines.Add('### Read before working')
    $lines.Add('')
    $lines.Add("Read project-owned local rules: ``$LocalRules``. If absent, report the missing local context; do not invent project commands.")
    $lines.Add("The shared release must exist at ``$($Release.Root)``. If unavailable, state that the Kit context is unavailable; do not claim it is loaded or create a snapshot fallback.")
    $lines.Add("For the rest of CORE, read ``$($Release.Root)/rules/CORE.md``. Read every selected profile:")
    foreach ($profile in $Profiles) { $lines.Add("- ``$($Release.Root)/$($catalog.profiles.PSObject.Properties[$profile].Value.file)``") }
    if ($Profiles.Count -eq 0) { $lines.Add('- No profile selected.') }
    $lines.Add('')
    $lines.Add('### Task-specific reading routes')
    $lines.Add('')
    foreach ($topic in $effective) {
        $metadata = $catalog.topics.PSObject.Properties[$topic].Value
        if ($topic -eq 'project-audit') {
            $lines.Add("- ``$topic`` ($($metadata.kind)): $($metadata.readWhen) Use ``aek-project-audit``; read ``.agents/skills/aek-project-audit/SKILL.md`` and its linked canonical resource relative to that skill directory.")
        }
        else { $lines.Add("- ``$topic`` ($($metadata.kind)): $($metadata.readWhen) Read ``$($Release.Root)/$($metadata.file)``.") }
    }
    $lines.Add('')
    if ('project-audit' -in $Topics) {
        $lines.Add('For an explicitly requested deep audit, use the discovered aek-project-audit skill. This connection already selects the workflow; the canonical snapshot onboarding paragraph does not apply to shared mode.')
    }
    $lines.Add('A profile or available topic does not authorize unrelated work. Requested, installed, accessible, and actually read context are different; actual reading remains unknown unless observed.')
    $lines.Add($aekBlockEnd)
    return ($lines -join "`n") + "`n"
}

function Get-AekSharedConnectionPlan {
    param([string]$ProjectRoot, [string]$InstallRoot, [string]$ReleaseId, [string[]]$Profiles, [string[]]$Topics, [string]$LocalRules = '.ai-rules/PROJECT_RULES.md')
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $install = [System.IO.Path]::GetFullPath($InstallRoot)
    if ([string]::Equals($root, $install, (Get-AiRulesPathComparison)) -or $install.StartsWith($root.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar, (Get-AiRulesPathComparison))) { throw 'Shared installation must be outside the connected project.' }
    if (Test-Path -LiteralPath (Join-Path $root '.ai-rules/manifest.json')) { throw 'Snapshot connection exists. No automatic migration to shared mode.' }
    $configPath = Get-AiRulesSafePath -BasePath $root -ChildPath '.ai-rules/shared.json' -Label 'shared config'
    $agentsPath = Get-AiRulesSafePath -BasePath $root -ChildPath 'AGENTS.md' -Label 'Codex entry point'
    [void](Get-AiRulesSafePath -BasePath $root -ChildPath $LocalRules -Label 'project local rules')
    if (Test-Path -LiteralPath (Join-Path $root 'AGENTS.override.md')) { throw 'AGENTS.override.md shadows the adapter. Resolve the instruction entry point explicitly first.' }
    $existingConfig = $null
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $existingConfig = (Read-AekText -Path $configPath) | ConvertFrom-Json
        if ($existingConfig.schemaVersion -ne '0.1' -or $existingConfig.mode -ne 'shared' -or $existingConfig.adapter -ne 'codex') { throw 'Unsupported existing shared connection.' }
        # Phase 1 never silently repins a connected project when selected changes.
        if ([string]::IsNullOrWhiteSpace($ReleaseId)) { $ReleaseId = [string]$existingConfig.releaseId }
        if ($ReleaseId -ne $existingConfig.releaseId -or $install -ne $existingConfig.installRoot) { throw 'Existing connection is pinned. Reconnection to another release is outside Phase 1.' }
    }
    $release = Resolve-AekRelease -InstallRoot $install -ReleaseId $ReleaseId
    $block = New-AekCodexBlock -Release $release -Profiles $Profiles -Topics $Topics -LocalRules $LocalRules
    $original = if (Test-Path -LiteralPath $agentsPath -PathType Leaf) { Read-AekText -Path $agentsPath } else { '' }
    $blockPattern = '(?s)' + [regex]::Escape($aekBlockStart) + '.*?' + [regex]::Escape($aekBlockEnd) + '\n?'
    $blocks = [regex]::Matches($original, $blockPattern)
    $startCount = [regex]::Matches($original, [regex]::Escape($aekBlockStart)).Count
    $endCount = [regex]::Matches($original, [regex]::Escape($aekBlockEnd)).Count
    if ($startCount -ne $endCount -or $startCount -gt 1 -or ($startCount -eq 1 -and $blocks.Count -ne 1)) { throw 'Malformed or duplicated managed AGENTS block.' }
    if ($blocks.Count -eq 1) {
        if ($null -eq $existingConfig -or (Get-AiRulesSha256Text -Content $blocks[0].Value) -ne $existingConfig.entryPointHash) { throw 'Managed AGENTS block changed locally; refusing to overwrite it.' }
        $agents = $original.Substring(0, $blocks[0].Index) + $block + $original.Substring($blocks[0].Index + $blocks[0].Length)
    }
    else {
        if ($null -ne $existingConfig) { throw 'Managed AGENTS block missing; repair requires explicit review.' }
        $agents = $block + $(if ($original.Length -gt 0) { "`n" + $original } else { '' })
    }
    if ([System.Text.Encoding]::UTF8.GetByteCount($agents) -gt 32768) { throw 'AGENTS exceeds the default Codex instruction budget; refusing to risk truncating the mandatory block.' }
    $skillRootPath = Get-AiRulesSafePath -BasePath $root -ChildPath '.agents/skills' -Label 'skills root'
    $skillPath = Join-Path $skillRootPath 'aek-project-audit'
    $skillTarget = Join-Path $release.Root 'skills/aek-project-audit'
    if ('project-audit' -in $Topics) {
        if (Test-Path -LiteralPath $skillPath) {
            $item = Get-Item -LiteralPath $skillPath -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -or -not $item.Target -or [System.IO.Path]::GetFullPath([string]@($item.Target)[0]) -ne [System.IO.Path]::GetFullPath($skillTarget)) {
                throw 'Existing skill directory does not point to the pinned release; refusing to replace it.'
            }
        }
    }
    elseif (Test-Path -LiteralPath $skillPath) { throw 'Existing audit skill would remain active without selection; no implicit removal.' }
    $config = [ordered]@{
        schemaVersion = '0.1'; mode = 'shared'; adapter = 'codex'; policy = 'pinned'
        installRoot = $install; releaseId = $release.Manifest.releaseId; releaseDigest = $release.Manifest.digest
        profiles = @($Profiles); topics = @($Topics); localRules = $LocalRules
        entryPointHash = Get-AiRulesSha256Text -Content $block
    }
    return [pscustomobject]@{ Root = $root; ConfigPath = $configPath; Config = $config; OriginalConfigState = (Get-AekFileState -Path $configPath); AgentsPath = $agentsPath; AgentsContent = $agents; OriginalAgents = $original; OriginalAgentsState = (Get-AekFileState -Path $agentsPath); SkillPath = $skillPath; SkillTarget = $skillTarget; IncludeSkill = ('project-audit' -in $Topics); Public = ('public-repository' -in $Profiles) }
}

function Connect-AekCodexProject {
    param($Plan)
    if ((Get-AekFileState -Path $Plan.AgentsPath) -ne $Plan.OriginalAgentsState -or (Get-AekFileState -Path $Plan.ConfigPath) -ne $Plan.OriginalConfigState) { throw 'Project entry point or connection changed after planning; build a new plan.' }
    # Revalidate the pinned release, instruction override, and discovery link before mutation.
    $fresh = Get-AekSharedConnectionPlan -ProjectRoot $Plan.Root -InstallRoot $Plan.Config.installRoot -ReleaseId $Plan.Config.releaseId -Profiles $Plan.Config.profiles -Topics $Plan.Config.topics -LocalRules $Plan.Config.localRules
    if ($fresh.AgentsContent -cne $Plan.AgentsContent -or $fresh.OriginalConfigState -ne $Plan.OriginalConfigState -or $fresh.OriginalAgentsState -ne $Plan.OriginalAgentsState) { throw 'Connection plan is stale; build a new plan.' }
    $createdLink = $false
    $originalConfig = if (Test-Path -LiteralPath $Plan.ConfigPath) { [System.IO.File]::ReadAllBytes($Plan.ConfigPath) } else { $null }
    $originalAgents = if (Test-Path -LiteralPath $Plan.AgentsPath) { [System.IO.File]::ReadAllBytes($Plan.AgentsPath) } else { $null }
    try {
        if ($Plan.IncludeSkill -and -not (Test-Path -LiteralPath $Plan.SkillPath)) {
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Plan.SkillPath))
            $linkType = if ([System.IO.Path]::DirectorySeparatorChar -eq [char]'\') { 'Junction' } else { 'SymbolicLink' }
            [void](New-Item -ItemType $linkType -Path $Plan.SkillPath -Target $Plan.SkillTarget -ErrorAction Stop)
            $createdLink = $true
        }
        if ($Plan.Public) {
            $excludePlan = Set-AiRulesLocalOnlyExclude -ProjectRoot $Plan.Root
            # Additional adapter runtime is local-only; preserve unrelated excludes.
            $excludePath = $excludePlan.Path
            if (-not [string]::IsNullOrWhiteSpace($excludePath)) {
                $exclude = Read-AekText -Path $excludePath
                $begin = '# BEGIN agent-engineering-kit codex'
                $end = '# END agent-engineering-kit codex'
                $pattern = '(?ms)^' + [regex]::Escape($begin) + '\n.*?^' + [regex]::Escape($end) + '(?:\n|\z)'
                if ([regex]::Matches($exclude, [regex]::Escape($begin)).Count -ne [regex]::Matches($exclude, $pattern).Count -or [regex]::Matches($exclude, [regex]::Escape($end)).Count -ne [regex]::Matches($exclude, $pattern).Count -or [regex]::Matches($exclude, $pattern).Count -gt 1) { throw 'Malformed Codex block in Git exclude.' }
                $userExclude = [regex]::Replace($exclude, $pattern, '')
                Write-AekAtomicText -Path $excludePath -Content ($userExclude.TrimEnd() + "`n$begin`n/.agents/skills/aek-project-audit`n$end`n")
            }
        }
        Write-AekAtomicText -Path $Plan.AgentsPath -Content $Plan.AgentsContent
        Write-AekAtomicText -Path $Plan.ConfigPath -Content ((ConvertTo-AiRulesJson -InputObject $Plan.Config) + "`n")
    }
    catch {
        if ($null -ne $originalAgents) { [System.IO.File]::WriteAllBytes($Plan.AgentsPath, $originalAgents) }
        elseif (Test-Path -LiteralPath $Plan.AgentsPath -PathType Leaf) { [System.IO.File]::Delete($Plan.AgentsPath) }
        if ($null -ne $originalConfig) { [System.IO.File]::WriteAllBytes($Plan.ConfigPath, $originalConfig) }
        elseif (Test-Path -LiteralPath $Plan.ConfigPath -PathType Leaf) { [System.IO.File]::Delete($Plan.ConfigPath) }
        # Delete only the newly created directory link, never its target.
        if ($createdLink) { [System.IO.Directory]::Delete($Plan.SkillPath, $false) }
        throw
    }
}

function Get-AekSharedProjectStatus {
    param([string]$ProjectRoot)
    $result = [ordered]@{ mode = 'shared'; requested = $null; installed = 'unknown'; available = 'unknown'; loaded = 'unknown'; diagnostics = @() }
    try {
        $root = (Resolve-Path -LiteralPath $ProjectRoot).Path
        if (Test-Path -LiteralPath (Join-Path $root '.ai-rules/manifest.json')) { throw 'Snapshot manifest exists; use legacy status. Shared mode does not migrate it.' }
        $path = Get-AiRulesSafePath -BasePath $root -ChildPath '.ai-rules/shared.json' -Label 'shared config'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Shared project connection missing.' }
        $config = (Read-AekText -Path $path) | ConvertFrom-Json
        if ($config.schemaVersion -ne '0.1' -or $config.mode -ne 'shared' -or $config.adapter -ne 'codex' -or $config.policy -ne 'pinned') { throw 'Invalid shared connection.' }
        $result.requested = $config.releaseId
        $release = Resolve-AekRelease -InstallRoot $config.installRoot -ReleaseId $config.releaseId
        if ($release.Manifest.digest -ne $config.releaseDigest) { throw 'Pinned release digest mismatch.' }
        $result.installed = $release.Manifest.releaseId
        $result.sourceRevision = $release.Manifest.identity.sourceRevision
        $expected = New-AekCodexBlock -Release $release -Profiles $config.profiles -Topics $config.topics -LocalRules $config.localRules
        $agentsPath = Get-AiRulesSafePath -BasePath $root -ChildPath 'AGENTS.md' -Label 'Codex entry point'
        if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) { throw 'AGENTS.md missing.' }
        $agents = Read-AekText -Path $agentsPath
        if ([regex]::Matches($agents, [regex]::Escape($aekBlockStart)).Count -ne 1 -or [regex]::Matches($agents, [regex]::Escape($aekBlockEnd)).Count -ne 1) { throw 'Malformed or duplicated managed AGENTS block.' }
        if (-not $agents.Contains($expected) -or (Get-AiRulesSha256Text -Content $expected) -ne $config.entryPointHash) { throw 'Managed AGENTS block differs from pinned sources.' }
        if ([System.Text.Encoding]::UTF8.GetByteCount($agents) -gt 32768) { throw 'AGENTS exceeds the default instruction budget.' }
        if (Test-Path -LiteralPath (Join-Path $root 'AGENTS.override.md')) { throw 'AGENTS.override.md shadows the adapter.' }
        if ('project-audit' -in @($config.topics)) {
            $skillPath = Join-Path $root '.agents/skills/aek-project-audit'
            $skill = Get-Item -LiteralPath $skillPath -Force -ErrorAction Stop
            $target = Join-Path $release.Root 'skills/aek-project-audit'
            if (($skill.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -or [System.IO.Path]::GetFullPath([string]@($skill.Target)[0]) -ne [System.IO.Path]::GetFullPath($target)) { throw 'Skill discovery link does not target the pinned release.' }
        }
        $local = Get-AiRulesSafePath -BasePath $root -ChildPath $config.localRules -Label 'local context'
        if (-not (Test-Path -LiteralPath $local -PathType Leaf)) { $result.diagnostics += 'Local rules missing; preserve or create project-owned context explicitly.' }
        $result.diagnostics += @(Get-AiRulesProjectToolWarnings -ProjectRoot $root)
        if ('public-repository' -in @($config.profiles)) {
            $publication = Get-AiRulesPublicRepositoryState -ProjectRoot $root
            $result.privateContext = $publication.PrivateContext
            if (@($publication.TrackedRuntime).Count -gt 0) { $result.diagnostics += 'Public runtime already tracked; excludes do not remove it from index or history.' }
            $trackedSkill = @(Invoke-AiRulesGitText -Arguments @('-C', $root, 'ls-files', '--', '.agents/skills/aek-project-audit'))
            if ($trackedSkill.Count -gt 0) { $result.diagnostics += 'Public audit skill link already tracked; excludes do not remove it from index or history.' }
            # The legacy exclusion planner cannot recognise the separate adapter block.
            # Verify effective Git rules directly, including higher-priority .gitignore negations.
            try {
                $ignored = @(Invoke-AiRulesGitText -Arguments @('-C', $root, 'check-ignore', '--no-index', '--', 'AGENTS.md', '.ai-rules/shared.json', '.local/kit-probe', '.agents/skills/aek-project-audit'))
                if ($ignored.Count -ne 4) { $result.diagnostics += 'Public runtime exclusions are ineffective; inspect Git ignore overrides before publication.' }
            }
            catch { $result.diagnostics += 'Public runtime exclusions could not be verified.' }
            foreach ($file in @($publication.PrivateDocuments)) { $result.diagnostics += "Private document is in Git index: $file. Visibility metadata does not protect publication." }
            foreach ($file in @($publication.PotentialDocuments)) { $result.diagnostics += "Review document audience before publication: $file." }
            if ($publication.PrivateContext -ne 'configured') { $result.diagnostics += "Private context recovery is not verified: $($publication.PrivateContext)." }
        }
        $result.available = 'filesystem-verified; Codex discovery and tool access not observed'
    }
    catch { $result.diagnostics += $_.Exception.Message }
    return [pscustomobject]$result
}

Export-ModuleMember -Function 'Get-AekSharedConnectionPlan', 'Connect-AekCodexProject', 'Get-AekSharedProjectStatus', 'New-AekCodexBlock'

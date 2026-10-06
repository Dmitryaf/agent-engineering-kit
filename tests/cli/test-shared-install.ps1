[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$powerShellExe = (Get-Process -Id $PID).Path
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$tempRoot = Join-Path $tempBase ('kit-shared-tests-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object System.Text.UTF8Encoding($false)
$count = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:count++
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    $errorText = $null
    try { & $Action | Out-Null } catch { $errorText = $_.Exception.Message }
    Assert-True (-not [string]::IsNullOrWhiteSpace($errorText) -and $errorText -match $Pattern) "$Message; actual: $errorText"
}

function Write-FixtureText {
    param([string]$Path, [string]$Content)
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Invoke-FixtureGit {
    param([string]$Root, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& git -C $Root @Arguments 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "Fixture Git failed: $($Arguments -join ' ') $output" }
    return $output
}

function Invoke-SharedCli {
    param([string[]]$Arguments, [bool]$Success = $true)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hubRoot 'scripts/shared-kit.ps1') @Arguments 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    Assert-True (($code -eq 0) -eq $Success) "CLI exit for $($Arguments -join ' '): $output"
    return $output
}

function New-FixtureGit {
    param([string]$Root)
    [void][System.IO.Directory]::CreateDirectory($Root)
    [void](Invoke-FixtureGit $Root @('init', '-q'))
    [void](Invoke-FixtureGit $Root @('config', 'core.autocrlf', 'false'))
    [void](Invoke-FixtureGit $Root @('config', 'user.name', 'Kit Tests'))
    [void](Invoke-FixtureGit $Root @('config', 'user.email', 'tests@example.invalid'))
}

function Get-FixtureSnapshot {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return '(absent)' }
    $rows = [System.Collections.Generic.List[string]]::new()
    function Visit-FixtureDirectory {
        param([string]$Directory)
        foreach ($item in @(Get-ChildItem -LiteralPath $Directory -Force | Sort-Object Name)) {
            if ($item.Name -eq '.git') { continue }
            $relative = $item.FullName.Substring($Root.Length).Replace('\', '/')
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $rows.Add("link:$relative->$($item.Target)")
            }
            elseif ($item.PSIsContainer) { $rows.Add("dir:$relative"); Visit-FixtureDirectory -Directory $item.FullName }
            else { $rows.Add("file:${relative}:" + (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash) }
        }
    }
    Visit-FixtureDirectory -Directory $Root
    return ($rows -join "`n")
}

try {
    [void][System.IO.Directory]::CreateDirectory($tempRoot)
    $sourceRoot = Join-Path $tempRoot 'canonical-source'
    $installRoot = Join-Path $tempRoot 'installation'
    New-FixtureGit -Root $sourceRoot
    foreach ($directory in @('rules', 'profiles', 'workflows', 'templates', 'sync')) {
        Copy-Item -LiteralPath (Join-Path $hubRoot $directory) -Destination $sourceRoot -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $hubRoot 'LICENSE') -Destination $sourceRoot
    [void](Invoke-FixtureGit $sourceRoot @('add', '--all'))
    [void](Invoke-FixtureGit $sourceRoot @('commit', '-qm', 'test(sync): create canonical fixture'))
    $sourceRevision = [string](@(Invoke-FixtureGit $sourceRoot @('rev-parse', 'HEAD'))[0])
    Import-Module (Join-Path $hubRoot 'src/SharedInstall.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $hubRoot 'src/CodexAdapter.psm1') -Force -ErrorAction Stop

    $sourceSnapshot = Get-FixtureSnapshot -Root $sourceRoot
    [void](Invoke-SharedCli @('install', '-SourceRoot', $sourceRoot, '-InstallRoot', $installRoot))
    Assert-True (-not (Test-Path -LiteralPath $installRoot) -and (Get-FixtureSnapshot $sourceRoot) -eq $sourceSnapshot) 'install preview must create no files and preserve canonical source'
    $plan = New-AekReleasePlan -SourceRoot $sourceRoot
    $repeatedPlan = New-AekReleasePlan -SourceRoot $sourceRoot
    Assert-True ($plan.ReleaseId -eq $repeatedPlan.ReleaseId -and $plan.Manifest.digest -eq $repeatedPlan.Manifest.digest) 'same committed sources and builder must produce the same release identity'
    Assert-True ($plan.Manifest.identity.sourceRevision -eq $sourceRevision -and $plan.Manifest.identity.builder.Count -gt 0) 'release identity must include full canonical SHA and actual builder identity'
    $releaseRoot = Install-AekRelease -Plan $plan -InstallRoot $installRoot
    Set-AekSelectedRelease -InstallRoot $installRoot -ReleaseId $plan.ReleaseId
    $releaseSnapshot = Get-FixtureSnapshot $releaseRoot
    [void](Install-AekRelease -Plan $plan -InstallRoot $installRoot)
    [void](Invoke-SharedCli @('install', '-SourceRoot', $sourceRoot, '-InstallRoot', $installRoot, '-Apply'))
    Assert-True ((Get-FixtureSnapshot $releaseRoot) -eq $releaseSnapshot) 'repeated installation must preserve the immutable release'
    $release = Resolve-AekRelease -InstallRoot $installRoot
    Assert-True ($release.Manifest.releaseId -eq $plan.ReleaseId -and $release.Manifest.digest -eq $plan.Manifest.digest) 'selected release must resolve to the verified identity'

    $core = Read-AekText -Path (Join-Path $sourceRoot 'rules/CORE.md')
    $adapter = Read-AekText -Path (Join-Path $releaseRoot 'adapter.json') | ConvertFrom-Json
    $bootstrap = Read-AekText -Path (Join-Path $releaseRoot 'bootstrap.md')
    foreach ($section in $adapter.coreSections) {
        $canonical = [regex]::Match($core, '(?ms)^## ' + [regex]::Escape($section) + '\n.*?(?=^## |\z)').Value.TrimEnd()
        Assert-True ($canonical.Length -gt 0 -and $bootstrap.Contains($canonical)) "bootstrap section must be exact canonical text: $section"
    }
    $skillRoot = Join-Path $releaseRoot 'skills/aek-project-audit'
    Assert-True ((Read-AekText (Join-Path $skillRoot 'references/workflows/PROJECT_DEEP_AUDIT.md')) -eq (Read-AekText (Join-Path $sourceRoot 'workflows/PROJECT_DEEP_AUDIT.md'))) 'skill workflow resource must equal its canonical source'
    Assert-True ((Test-Path (Join-Path $skillRoot 'references/workflows/PROJECT_AUDIT_PROMPT.md')) -and (Test-Path (Join-Path $skillRoot 'references/rules/RESEARCH_AND_EVIDENCE.md'))) 'skill must retain local relative workflow links and research dependencies'
    $skillText = Read-AekText (Join-Path $skillRoot 'SKILL.md')
    Assert-True ($skillText -match '(?m)^name: aek-project-audit$' -and $skillText -match 'references/workflows/PROJECT_DEEP_AUDIT.md' -and $skillText -match 'do not create or update a snapshot') 'skill entry must route to canonical workflow without legacy onboarding'

    $releaseCore = Join-Path $releaseRoot 'rules/CORE.md'
    $originalCoreBytes = [System.IO.File]::ReadAllBytes($releaseCore)
    [System.IO.File]::AppendAllText($releaseCore, "`nchanged outside installer", $utf8)
    Assert-Rejected { Test-AekRelease -ReleaseRoot $releaseRoot } 'integrity' 'modified release must fail integrity'
    $tamperedSnapshot = Get-FixtureSnapshot $releaseRoot
    Assert-Rejected { Install-AekRelease -Plan $plan -InstallRoot $installRoot } 'integrity|immutable' 'reinstallation must refuse to repair an existing modified release'
    Assert-True ((Get-FixtureSnapshot $releaseRoot) -eq $tamperedSnapshot) 'rejected reinstallation must not overwrite the modified release'
    [System.IO.File]::WriteAllBytes($releaseCore, $originalCoreBytes)
    [System.IO.File]::Delete($releaseCore)
    Assert-Rejected { Test-AekRelease -ReleaseRoot $releaseRoot } 'integrity' 'missing release file must fail integrity'
    [System.IO.File]::WriteAllBytes($releaseCore, $originalCoreBytes)
    $extraFile = Join-Path $releaseRoot 'unexpected.md'
    Write-FixtureText $extraFile '# Unexpected release content'
    Assert-Rejected { Test-AekRelease -ReleaseRoot $releaseRoot } 'Unexpected release file' 'extra release file must fail integrity'
    [System.IO.File]::Delete($extraFile)

    $sourceCore = Join-Path $sourceRoot 'rules/CORE.md'
    $sourceCoreBytes = [System.IO.File]::ReadAllBytes($sourceCore)
    [System.IO.File]::AppendAllText($sourceCore, "`nnot committed", $utf8)
    Assert-Rejected { New-AekReleasePlan -SourceRoot $sourceRoot } 'committed' 'dirty canonical sources must not produce a release'
    [void](Invoke-SharedCli -Arguments @('install', '-SourceRoot', $sourceRoot, '-InstallRoot', $installRoot, '-Apply') -Success $false)
    Assert-True ((Get-FixtureSnapshot $releaseRoot) -eq $releaseSnapshot) 'dirty install rejection must preserve the existing release'
    [System.IO.File]::WriteAllBytes($sourceCore, $sourceCoreBytes)

    $projectRoot = Join-Path $tempRoot 'private-project'
    [void][System.IO.Directory]::CreateDirectory($projectRoot)
    Write-FixtureText (Join-Path $projectRoot 'AGENTS.md') "# Owner instructions`nPreserve this project instruction.`n"
    Write-FixtureText (Join-Path $projectRoot '.ai-rules/PROJECT_RULES.md') '# Unique local constraints'
    $localHash = (Get-FileHash (Join-Path $projectRoot '.ai-rules/PROJECT_RULES.md')).Hash
    $projectSnapshot = Get-FixtureSnapshot $projectRoot
    Assert-Rejected { Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot (Join-Path $projectRoot 'inside-install') -Profiles @('standard-product') -Topics @() } 'outside' 'shared installation must remain outside the project'
    [void](Invoke-SharedCli @('connect', '-InstallRoot', $installRoot, '-ProjectRoot', $projectRoot, '-Topics', 'project-audit'))
    [void](Invoke-SharedCli @('connect', '-InstallRoot', $installRoot, '-ProjectRoot', $projectRoot, '-Profiles', 'standard-product,public-repository', '-Topics', 'quality,project-audit'))
    Assert-True ((Get-FixtureSnapshot $projectRoot) -eq $projectSnapshot) 'connect preview must preserve the entire project'
    $connection = Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit')
    Assert-True ($connection.AgentsContent.Contains('.agents/skills/aek-project-audit/SKILL.md') -and -not $connection.AgentsContent.Contains($releaseRoot + '/workflows/PROJECT_DEEP_AUDIT.md')) 'selected audit must route through the Skill resource rather than a competing plain workflow path'
    Connect-AekCodexProject -Plan $connection
    $agentsPath = Join-Path $projectRoot 'AGENTS.md'
    $configPath = Join-Path $projectRoot '.ai-rules/shared.json'
    Assert-True ((Read-AekText $agentsPath).Contains('Preserve this project instruction.') -and (Get-FileHash (Join-Path $projectRoot '.ai-rules/PROJECT_RULES.md')).Hash -eq $localHash) 'connect must preserve owner instructions and unique local rules'
    Assert-True (-not (Test-Path (Join-Path $projectRoot '.ai-rules/manifest.json')) -and -not (Test-Path (Join-Path $projectRoot '.ai-rules/lock.json')) -and -not (Test-Path (Join-Path $projectRoot '.ai-rules/upstream'))) 'shared connection must create no snapshot infrastructure'
    $skillLink = Get-Item -LiteralPath $connection.SkillPath -Force
    Assert-True (($skillLink.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -and [System.IO.Path]::GetFullPath([string]@($skillLink.Target)[0]) -eq [System.IO.Path]::GetFullPath($skillRoot)) 'skill discovery must be a directory link to the pinned release, not a project copy'
    $status = Get-AekSharedProjectStatus -ProjectRoot $projectRoot
    Assert-True ($status.requested -eq $plan.ReleaseId -and $status.installed -eq $plan.ReleaseId -and $status.available -ne 'unknown' -and $status.loaded -eq 'unknown') 'filesystem verification must not claim actual agent loading'
    $connectedSnapshot = Get-FixtureSnapshot $projectRoot
    Connect-AekCodexProject -Plan (Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit'))
    [void](Invoke-SharedCli @('connect', '-InstallRoot', $installRoot, '-ProjectRoot', $projectRoot, '-Topics', 'project-audit', '-Apply'))
    Assert-True ((Get-FixtureSnapshot $projectRoot) -eq $connectedSnapshot) 'repeated connection must preserve project content and link identity'
    [void](Invoke-SharedCli @('status', '-ProjectRoot', $projectRoot))

    $stalePlan = Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit')
    $savedAgents = [System.IO.File]::ReadAllBytes($agentsPath)
    [System.IO.File]::AppendAllText($agentsPath, "`nNew owner instruction after preview.`n", $utf8)
    $staleSnapshot = Get-FixtureSnapshot $projectRoot
    Assert-Rejected { Connect-AekCodexProject -Plan $stalePlan } 'after planning|stale' 'stale preview must preserve newly added surrounding owner instructions'
    Assert-True ((Get-FixtureSnapshot $projectRoot) -eq $staleSnapshot) 'stale AGENTS rejection must leave all project files intact'
    [System.IO.File]::WriteAllBytes($agentsPath, $savedAgents)
    $stalePlan = Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit')
    $savedConfig = [System.IO.File]::ReadAllBytes($configPath)
    [System.IO.File]::AppendAllText($configPath, "`n ", $utf8)
    $staleSnapshot = Get-FixtureSnapshot $projectRoot
    Assert-Rejected { Connect-AekCodexProject -Plan $stalePlan } 'after planning|stale' 'stale preview must preserve a connection changed after planning'
    Assert-True ((Get-FixtureSnapshot $projectRoot) -eq $staleSnapshot) 'stale config rejection must leave all project files intact'
    [System.IO.File]::WriteAllBytes($configPath, $savedConfig)

    $originalAgents = [System.IO.File]::ReadAllBytes($agentsPath)
    Write-FixtureText $agentsPath ((Read-AekText $agentsPath).Replace('Generated from canonical sources.', 'Locally changed managed instructions.'))
    Assert-Rejected { Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit') } 'changed locally' 'locally modified managed block must not be overwritten'
    Assert-True ((Get-AekSharedProjectStatus $projectRoot).available -eq 'unknown') 'modified managed block must not be reported as available'
    [System.IO.File]::WriteAllBytes($agentsPath, $originalAgents)
    Write-FixtureText (Join-Path $projectRoot 'AGENTS.override.md') '# Shadowing instructions'
    Assert-Rejected { Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit') } 'override' 'shadowing entry point must be rejected'
    Assert-True ((Get-AekSharedProjectStatus $projectRoot).available -eq 'unknown') 'shadowing entry point must remain unavailable'
    [System.IO.File]::Delete((Join-Path $projectRoot 'AGENTS.override.md'))
    Write-FixtureText (Join-Path $projectRoot '.ai-rules/manifest.json') '{"schemaVersion":"0.2"}'
    $mixedSnapshot = Get-FixtureSnapshot $projectRoot
    Assert-Rejected { Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit') } 'Snapshot' 'existing snapshot manifest must prohibit shared migration'
    Assert-True ((Get-AekSharedProjectStatus $projectRoot).available -eq 'unknown' -and (Get-FixtureSnapshot $projectRoot) -eq $mixedSnapshot) 'mixed-mode diagnosis must be read-only and unknown'
    [System.IO.File]::Delete((Join-Path $projectRoot '.ai-rules/manifest.json'))

    $qualityPath = Join-Path $sourceRoot 'rules/QUALITY.md'
    [System.IO.File]::AppendAllText($qualityPath, "`n<!-- New canonical fixture version. -->`n", $utf8)
    [void](Invoke-FixtureGit $sourceRoot @('add', 'rules/QUALITY.md'))
    [void](Invoke-FixtureGit $sourceRoot @('commit', '-qm', 'test(sync): advance canonical fixture'))
    $nextPlan = New-AekReleasePlan -SourceRoot $sourceRoot
    [void](Install-AekRelease -Plan $nextPlan -InstallRoot $installRoot)
    $selectedPath = Join-Path $installRoot 'selected.json'
    $selectedHash = (Get-FileHash $selectedPath).Hash
    [void](Invoke-SharedCli @('select', '-InstallRoot', $installRoot, '-ReleaseId', $nextPlan.ReleaseId))
    Assert-True ((Get-FileHash $selectedPath).Hash -eq $selectedHash) 'select preview must preserve selection metadata'
    [void](Invoke-SharedCli @('select', '-InstallRoot', $installRoot, '-ReleaseId', $nextPlan.ReleaseId, '-Apply'))
    $reconnect = Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -Profiles @('standard-product') -Topics @('project-audit')
    Assert-True ($nextPlan.ReleaseId -ne $plan.ReleaseId -and $reconnect.Config.releaseId -eq $plan.ReleaseId) 'selecting a new release must preserve the existing project pin'
    Assert-Rejected { Get-AekSharedConnectionPlan -ProjectRoot $projectRoot -InstallRoot $installRoot -ReleaseId $nextPlan.ReleaseId -Profiles @('standard-product') -Topics @('project-audit') } 'pinned' 'Phase 1 must reject silently repinning an existing project'
    Assert-True ((Get-FixtureSnapshot $releaseRoot) -eq $releaseSnapshot -and (Get-FixtureSnapshot $projectRoot) -eq $connectedSnapshot) 'new selection must preserve old release and connected project'
    $newProject = Join-Path $tempRoot 'new-project'
    [void][System.IO.Directory]::CreateDirectory($newProject)
    $newConnection = Get-AekSharedConnectionPlan -ProjectRoot $newProject -InstallRoot $installRoot -Profiles @('standard-product') -Topics @()
    Assert-True ($newConnection.Config.releaseId -eq $nextPlan.ReleaseId) 'new connections must resolve the selected release'

    $publicRoot = Join-Path $tempRoot 'public-project'
    New-FixtureGit -Root $publicRoot
    Write-FixtureText (Join-Path $publicRoot 'AGENTS.md') '# Already tracked owner instructions'
    Write-FixtureText (Join-Path $publicRoot '.ai-rules/PROJECT_RULES.md') '# Already tracked local rules'
    [void](Invoke-FixtureGit $publicRoot @('add', '--all'))
    [void](Invoke-FixtureGit $publicRoot @('commit', '-qm', 'test(sync): create tracked public fixture'))
    Write-FixtureText (Join-Path $publicRoot '.git/info/exclude') "# Owner excludes`n/owner-state/`n"
    $index = @(Invoke-FixtureGit $publicRoot @('ls-files', '--stage')) -join "`n"
    $publicLocalHash = (Get-FileHash (Join-Path $publicRoot '.ai-rules/PROJECT_RULES.md')).Hash
    $publicConnection = Get-AekSharedConnectionPlan -ProjectRoot $publicRoot -InstallRoot $installRoot -Profiles @('public-repository') -Topics @('project-audit')
    Connect-AekCodexProject -Plan $publicConnection
    $exclude = Read-AekText (Join-Path $publicRoot '.git/info/exclude')
    Assert-True ($exclude.Contains('/owner-state/') -and $exclude.Contains('/.ai-rules/') -and $exclude.Contains('/.agents/skills/aek-project-audit')) 'public connection must preserve owner excludes and exclude all generated runtime routes'
    Assert-True ((@(Invoke-FixtureGit $publicRoot @('ls-files', '--stage')) -join "`n") -eq $index -and (Get-FileHash (Join-Path $publicRoot '.ai-rules/PROJECT_RULES.md')).Hash -eq $publicLocalHash) 'public connection must not untrack files or overwrite local rules'
    $ignored = @(Invoke-FixtureGit $publicRoot @('check-ignore', '--no-index', '--', 'AGENTS.md', '.ai-rules/shared.json', '.agents/skills/aek-project-audit'))
    Assert-True ($ignored.Count -eq 3) 'all public runtime paths must actually be ignored'
    $publicStatus = Get-AekSharedProjectStatus -ProjectRoot $publicRoot
    Assert-True ($publicStatus.available -ne 'unknown' -and ($publicStatus.diagnostics -join '; ') -match 'tracked.*index or history') 'public status must remain verified while diagnosing tracked runtime rather than claim exclude removes it'
    Write-FixtureText (Join-Path $publicRoot '.gitignore') '!AGENTS.md'
    $overrideStatus = Get-AekSharedProjectStatus -ProjectRoot $publicRoot
    Assert-True (($overrideStatus.diagnostics -join '; ') -match 'exclusions.*ineffective') "public status must detect higher-priority Git ignore overrides; actual: $($overrideStatus | ConvertTo-Json -Compress)"

    $quarantine = Join-Path $tempRoot 'temporarily-unavailable-release'
    Move-Item -LiteralPath $releaseRoot -Destination $quarantine
    $missingStatus = Get-AekSharedProjectStatus -ProjectRoot $projectRoot
    Assert-True ($missingStatus.requested -eq $plan.ReleaseId -and $missingStatus.installed -eq 'unknown' -and $missingStatus.available -eq 'unknown' -and $missingStatus.loaded -eq 'unknown') 'missing installation must preserve requested identity and report unknown availability'
    [void](Invoke-SharedCli -Arguments @('status', '-ProjectRoot', $projectRoot) -Success $false)
    Assert-True (-not (Test-Path (Join-Path $projectRoot '.ai-rules/upstream'))) 'missing installation must not create a snapshot fallback'
    Move-Item -LiteralPath $quarantine -Destination $releaseRoot
    [System.IO.Directory]::Delete($connection.SkillPath, $false)
    Assert-True ((Test-Path -LiteralPath (Join-Path $skillRoot 'SKILL.md')) -and (Get-FixtureSnapshot $releaseRoot) -eq $releaseSnapshot) 'removing a discovery link must leave the shared target intact'
    Write-Host "Shared install and connection tests passed: $count assertions." -ForegroundColor Green
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'kit-shared-tests-*') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}

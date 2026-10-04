[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$powerShellExe = (Get-Process -Id $PID).Path
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$tempRoot = Join-Path $tempBase ('kit-public-tests-' + [Guid]::NewGuid().ToString('N'))
$count = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:count++
}
function Write-Text {
    param([string]$Path, [string]$Content)
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}
function Invoke-Git {
    param([string]$Root, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& git -C $Root @Arguments 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "Git fixture failed: $($Arguments -join ' ') $output" }
    return $output
}
function Invoke-Cli {
    param([string[]]$Arguments, [bool]$ExpectSuccess = $true)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = (& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureHub 'ai-rules.ps1') @Arguments 2>&1 | Out-String); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    Assert-True (($code -eq 0) -eq $ExpectSuccess) "CLI exit: $($Arguments -join ' ') $output"
    return $output
}
function New-Project {
    param([string]$Name)
    $root = Join-Path $tempRoot $Name
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    [void](Invoke-Git $root @('init', '-q'))
    [void](Invoke-Git $root @('config', 'user.name', 'Synthetic Fixture'))
    [void](Invoke-Git $root @('config', 'user.email', 'fixture@example.invalid'))
    Write-Text (Join-Path $root 'README.md') '# Synthetic public project'
    [void](Invoke-Git $root @('add', 'README.md'))
    [void](Invoke-Git $root @('commit', '-qm', 'fixture'))
    return $root
}
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
try {
    $fixtureHub = Join-Path $tempRoot 'hub'
    foreach ($file in @(& git -C $hubRoot ls-files --cached --others --exclude-standard)) {
        $source = Join-Path $hubRoot $file
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $target = Join-Path $fixtureHub $file
            [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            Copy-Item -LiteralPath $source -Destination $target
        }
    }
    [void](Invoke-Git $fixtureHub @('init', '-q'))
    [void](Invoke-Git $fixtureHub @('config', 'user.name', 'Synthetic Fixture'))
    [void](Invoke-Git $fixtureHub @('config', 'user.email', 'fixture@example.invalid'))
    [void](Invoke-Git $fixtureHub @('add', '.'))
    [void](Invoke-Git $fixtureHub @('commit', '-qm', 'fixture'))
    Import-Module (Join-Path $fixtureHub 'src/PublicRepository.psm1') -Force

    $project = New-Project 'public project'
    $head = (Invoke-Git $project @('rev-parse', 'HEAD')) -join ''
    $indexHash = (Get-FileHash -LiteralPath (Join-Path $project '.git/index')).Hash
    Write-Text (Join-Path $project '.gitignore') "node_modules/`n"
    $ignoreHash = (Get-FileHash -LiteralPath (Join-Path $project '.gitignore')).Hash
    $exclude = Join-Path $project '.git/info/exclude'
    $userExclude = "# user rule`r`ncache/`r`n!/AGENTS.md`r`n"
    Write-Text $exclude $userExclude
    [void](Invoke-Cli @('connect', '-ProjectRoot', $project, '-Profiles', 'public-repository'))
    Assert-True ((Get-Content $exclude -Raw).StartsWith($userExclude)) 'user exclude and CRLF preserved'
    $excludeHash = (Get-FileHash -LiteralPath $exclude).Hash
    [void](Invoke-Cli @('connect', '-ProjectRoot', $project, '-Apply'))
    Assert-True (@(Invoke-Git $project @('check-ignore', '--', 'AGENTS.md', '.ai-rules/lock.json', '.ai-rules/upstream/CORE.md', '.local/probe')).Count -eq 4) 'runtime and derived upstream are ignored'
    Assert-True ((Get-FileHash -LiteralPath $exclude).Hash -eq $excludeHash) 'second connection is byte-idempotent'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $project '.gitignore')).Hash -eq $ignoreHash) 'public gitignore unchanged'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $project '.git/index')).Hash -eq $indexHash) 'connection does not change index'
    Assert-True (((Invoke-Git $project @('rev-parse', 'HEAD')) -join '') -eq $head) 'connection preserves history'
    $status = Invoke-Cli @('status', '-ProjectRoot', $project)
    Assert-True ($status -match 'Agent runtime files: local-only' -and $status -match 'Private context: not configured' -and $status -match 'State: synchronized') 'missing context allows synchronized development without claiming saved context'
    $doctor = Invoke-Cli @('doctor', '-ProjectRoot', $project)
    Assert-True ($doctor -match 'Private context: not configured') 'doctor exposes missing private context'
    $privateSource = Join-Path $tempRoot 'private-source'
    [System.IO.Directory]::CreateDirectory($privateSource) | Out-Null
    $descriptorPath = Join-Path $project '.ai-rules/private-context.json'
    $descriptor = @{ schemaVersion = '0.1'; project = 'synthetic-public-project'; source = $privateSource; recovery = 'Restore from the owner private versioned source' }
    Write-Text $descriptorPath ($descriptor | ConvertTo-Json)
    $status = Invoke-Cli @('status', '-ProjectRoot', $project)
    Assert-True ($status -match 'Private context: configured' -and -not $status.Contains($privateSource)) 'available context does not print its private path'
    [void](Invoke-Git $project @('add', '.'))
    $tracked = Invoke-Git $project @('ls-files')
    Assert-True (-not (($tracked -join "`n") -match 'AGENTS|ai-rules|local/')) 'ordinary git add cannot publish runtime or private descriptor'
    $descriptor.source = Join-Path $tempRoot 'missing-private-source'
    Write-Text $descriptorPath ($descriptor | ConvertTo-Json)
    Assert-True ((Invoke-Cli @('status', '-ProjectRoot', $project)) -match 'Private context: unavailable') 'missing source is unavailable'
    $descriptor.source = Join-Path $project '.local'
    [System.IO.Directory]::CreateDirectory($descriptor.source) | Out-Null
    Write-Text $descriptorPath ($descriptor | ConvertTo-Json)
    Assert-True ((Invoke-Cli @('status', '-ProjectRoot', $project)) -match 'Private context: unavailable') 'in-project local context cannot claim external canonical storage'

    # Legacy public projects have runtime already in the index, even after ignore rules.
    Write-Text (Join-Path $project 'decisions/public.md') "---`nvisibility: repository`n---`nPublic API rationale"
    Write-Text (Join-Path $project 'decisions/private.md') "---`nvisibility: private`n---`nSynthetic internal rationale"
    Write-Text (Join-Path $project 'PROJECT_MAP.md') '# Needs an audience review'
    [void](Invoke-Git $project @('add', '-f', 'AGENTS.md', '.ai-rules', 'decisions', 'PROJECT_MAP.md'))
    # The staged private document is still public even if its working copy is edited.
    Write-Text (Join-Path $project 'decisions/private.md') "---`nvisibility: repository`n---`nWorking tree edit"
    $publication = Get-AiRulesPublicRepositoryState -ProjectRoot $project
    Assert-True ($publication.Runtime -eq 'tracked' -and $publication.TrackedRuntime.Count -gt 2) 'tracked runtime is detected'
    Assert-True ('decisions/public.md' -in $publication.PublicDocuments -and 'decisions/public.md' -notin $publication.PotentialDocuments) 'intentional public technical decision is accepted'
    Assert-True ('decisions/private.md' -in $publication.PrivateDocuments) 'private front matter in index does not protect publication'
    Assert-True ('PROJECT_MAP.md' -in $publication.PotentialDocuments) 'uncertain map is audited rather than blacklisted'
    $legacyIndex = (Get-FileHash -LiteralPath (Join-Path $project '.git/index')).Hash
    $legacyFile = (Get-FileHash -LiteralPath (Join-Path $project '.ai-rules/PROJECT_RULES.md')).Hash
    $plan = Invoke-Cli @('local-only', '-ProjectRoot', $project)
    Assert-True ($plan -match 'rm --cached' -and $plan -match 'literal-pathspecs' -and $plan.Contains("git -C '$project'")) 'migration instruction names the target checkout, not the current hub'
    [void](Invoke-Cli @('local-only', '-ProjectRoot', $project, '-Apply'))
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $project '.git/index')).Hash -eq $legacyIndex) 'migration apply does not change index'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $project '.ai-rules/PROJECT_RULES.md')).Hash -eq $legacyFile) 'migration preserves local unique rules'
    Assert-True (((Invoke-Git $project @('rev-parse', 'HEAD')) -join '') -eq $head) 'migration does not rewrite history or commit'
    Write-Text $exclude $userExclude
    $beforePlan = (Get-FileHash -LiteralPath $exclude).Hash
    [void](Invoke-Cli @('local-only', '-ProjectRoot', $project))
    Assert-True ((Get-FileHash -LiteralPath $exclude).Hash -eq $beforePlan) 'local-only plan is read-only'
    [void](Invoke-Cli @('local-only', '-ProjectRoot', $project, '-Apply'))
    Assert-True ((Get-FileHash -LiteralPath $exclude).Hash -eq $excludeHash) 'local-only apply restores the managed block'

    $privateProject = New-Project 'private project'
    $privateExclude = Join-Path $privateProject '.git/info/exclude'
    $privateExcludeHash = (Get-FileHash -LiteralPath $privateExclude).Hash
    [void](Invoke-Cli @('connect', '-ProjectRoot', $privateProject, '-Profiles', 'standard-product'))
    [void](Invoke-Cli @('connect', '-ProjectRoot', $privateProject, '-Apply'))
    Assert-True ((Get-FileHash -LiteralPath $privateExclude).Hash -eq $privateExcludeHash) 'private project exclude unchanged'
    [void](Invoke-Git $privateProject @('add', 'AGENTS.md', '.ai-rules'))
    Assert-True (@(Invoke-Git $privateProject @('ls-files', '.ai-rules')).Count -gt 2) 'private project retains tracked model'
    [void](Invoke-Cli @('local-only', '-ProjectRoot', $privateProject) $false)

    # A fresh clone gets public files only and can connect again; unique rules need private restore.
    $clone = Join-Path $tempRoot 'fresh clone'
    [void](Invoke-Git $tempRoot @('clone', '-q', $project, $clone))
    Assert-True (-not (Test-Path (Join-Path $clone '.ai-rules')) -and -not (Test-Path (Join-Path $clone 'AGENTS.md'))) 'fresh clone needs no runtime in public history'
    [void](Invoke-Cli @('connect', '-ProjectRoot', $clone, '-Profiles', 'public-repository'))
    [void](Invoke-Cli @('connect', '-ProjectRoot', $clone, '-Apply'))
    Assert-True ((Invoke-Cli @('status', '-ProjectRoot', $clone)) -match 'State: synchronized') 'fresh clone reconnects locally'

    # Restore canonical unique rules and pinned configuration without storing upstream in Git.
    Write-Text (Join-Path $privateSource 'agent/PROJECT_RULES.md') '# Owner unique rule restored from private source'
    foreach ($name in @('manifest.json', 'lock.json', 'RULESET.md')) {
        Copy-Item -LiteralPath (Join-Path $project ('.ai-rules/' + $name)) -Destination (Join-Path $privateSource ('agent/' + $name))
    }
    Copy-Item -LiteralPath (Join-Path $project 'AGENTS.md') -Destination (Join-Path $privateSource 'agent/AGENTS.md')
    $restoredClone = Join-Path $tempRoot 'restored clone'
    [void](Invoke-Git $tempRoot @('clone', '-q', $project, $restoredClone))
    [void](Invoke-Cli @('connect', '-ProjectRoot', $restoredClone, '-Profiles', 'public-repository'))
    foreach ($name in @('manifest.json', 'lock.json', 'RULESET.md', 'PROJECT_RULES.md')) {
        Copy-Item -LiteralPath (Join-Path $privateSource ('agent/' + $name)) -Destination (Join-Path $restoredClone ('.ai-rules/' + $name)) -Force
    }
    Copy-Item -LiteralPath (Join-Path $privateSource 'agent/AGENTS.md') -Destination (Join-Path $restoredClone 'AGENTS.md') -Force
    [void](Invoke-Cli @('apply', '-ProjectRoot', $restoredClone))
    Assert-True ((Get-Content (Join-Path $restoredClone '.ai-rules/PROJECT_RULES.md') -Raw) -match 'Owner unique rule') 'private canonical rule is preserved on restoration'
    $originalLock = Get-Content (Join-Path $project '.ai-rules/lock.json') -Raw | ConvertFrom-Json
    $restoredLock = Get-Content (Join-Path $restoredClone '.ai-rules/lock.json') -Raw | ConvertFrom-Json
    Assert-True (($originalLock.files | ConvertTo-Json -Compress) -eq ($restoredLock.files | ConvertTo-Json -Compress)) 'derived rules are rebuilt with the same locked hashes'

    # Worktrees use Git's common exclude, not a fabricated .git directory in the checkout.
    $worktreeRoot = Join-Path $tempRoot 'linked worktree'
    [void](Invoke-Git $privateProject @('worktree', 'add', '-q', '--detach', $worktreeRoot, 'HEAD'))
    [void](Invoke-Cli @('connect', '-ProjectRoot', $worktreeRoot, '-Profiles', 'public-repository'))
    [void](Invoke-Cli @('connect', '-ProjectRoot', $worktreeRoot, '-Apply'))
    Assert-True ((Get-Item -LiteralPath (Join-Path $worktreeRoot '.git') -Force).PSIsContainer -eq $false) 'worktree .git remains a file'
    Assert-True ((Invoke-Cli @('status', '-ProjectRoot', $worktreeRoot)) -match 'Agent runtime files: local-only') 'linked worktree runtime is locally ignored'
    Assert-True ((Get-Content $privateExclude -Raw) -match '# BEGIN agent-engineering-kit') 'worktree uses shared common exclude'

    # Explicit unignore in public gitignore must not be mistaken for protection.
    Write-Text (Join-Path $clone '.gitignore') "!/AGENTS.md`n"
    Assert-True ((Invoke-Cli @('status', '-ProjectRoot', $clone)) -match 'Agent runtime files: unprotected') 'effective ignore override is detected'

    $nested = Join-Path $clone 'nested-project'
    [System.IO.Directory]::CreateDirectory($nested) | Out-Null
    [void](Invoke-Cli @('connect', '-ProjectRoot', $nested, '-Profiles', 'public-repository') $false)
    Assert-True (-not (Test-Path (Join-Path $nested '.ai-rules'))) 'nested root fails before materializing runtime'

    Write-Text (Join-Path $project 'decisions/quoted.md') "---`nvisibility: 'private' # explicit private declaration`n---`nSynthetic"
    [void](Invoke-Git $project @('add', 'decisions/quoted.md'))
    Assert-True ('decisions/quoted.md' -in (Get-AiRulesPublicRepositoryState -ProjectRoot $project).PrivateDocuments) 'quoted private visibility is diagnosed'

    # Existing equivalent user rules need no duplicate inside the managed block.
    $dedupProject = New-Project 'existing excludes'
    $dedupExclude = Join-Path $dedupProject '.git/info/exclude'
    Write-Text $dedupExclude "# user excludes`n/.ai-rules/`n/AGENTS.md`n/.local/`n"
    [void](Invoke-Cli @('connect', '-ProjectRoot', $dedupProject, '-Profiles', 'public-repository'))
    $dedupContent = Get-Content $dedupExclude -Raw
    foreach ($pattern in @('/.ai-rules/', '/AGENTS.md', '/.local/')) {
        Assert-True ([regex]::Matches($dedupContent, [regex]::Escape($pattern)).Count -eq 1) 'identical user exclusion not unnecessarily duplicated'
    }
    Assert-True ((Invoke-Cli @('status', '-ProjectRoot', $dedupProject)) -match 'Agent runtime files: local-only') 'equivalent user excludes protect local runtime'

    $noGit = Join-Path $tempRoot 'without Git'
    [System.IO.Directory]::CreateDirectory($noGit) | Out-Null
    [void](Invoke-Cli @('connect', '-ProjectRoot', $noGit, '-Profiles', 'public-repository'))
    [void](Invoke-Cli @('connect', '-ProjectRoot', $noGit, '-Apply'))
    Assert-True (-not (Test-Path (Join-Path $noGit '.git')) -and (Test-Path (Join-Path $noGit '.ai-rules/lock.json'))) 'no Git checkout works without fabricating exclude'
    Write-Text $exclude '# BEGIN agent-engineering-kit'
    [void](Invoke-Cli @('local-only', '-ProjectRoot', $project, '-Apply') $false)
    Assert-True ((Get-Content $exclude -Raw) -eq '# BEGIN agent-engineering-kit') 'malformed user block is not overwritten'
    Write-Host "Public repository tests passed: $count assertions."
}
finally {
    $full = [System.IO.Path]::GetFullPath($tempRoot)
    if ($full.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $full).StartsWith('kit-public-tests-')) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

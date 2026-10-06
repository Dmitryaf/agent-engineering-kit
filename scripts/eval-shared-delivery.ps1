[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$SourceRevision = 'HEAD',
    [string]$WorkRoot,
    [string]$CodexExecutable = 'codex',
    [ValidatePattern('^[A-Za-z0-9_.:/-]+$')][string]$Model,
    [ValidateRange(30, 3600)][int]$TimeoutSeconds = 600,
    [switch]$Execute,
    [switch]$UseRipgrepForReads,
    [ValidateSet('permanent-rule-and-local-context', 'task-lazy-quality-and-research', 'explicit-project-audit')][string]$ScenarioId,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$hubRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $SourceRoot) { $SourceRoot = $hubRoot }
$sourceRootFull = (Resolve-Path -LiteralPath $SourceRoot).Path
$scenariosPath = Join-Path $hubRoot 'evals/delivery/scenarios.json'
$scenariosDocument = Get-Content -LiteralPath $scenariosPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-Digest {
    param([string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return (($algorithm.ComputeHash($utf8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $algorithm.Dispose() }
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Write-Json {
    param([string]$Path, $Value)
    Write-Text -Path $Path -Content (($Value | ConvertTo-Json -Depth 30) + "`n")
}

function Invoke-Git {
    param([string[]]$GitArguments)
    $previousPreference = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; $output = @(& git @GitArguments 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) {
        if ($runRoot) { Write-Text -Path (Join-Path $runRoot 'git-failure.private.log') -Content ($output -join "`n") }
        throw 'Fixture Git operation failed; inspect the private Git log. No behavioral success is inferred.'
    }
    return ($output -join "`n")
}

function Get-NormalizedFileDigest {
    param([string]$Path)
    return Get-Digest ([IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n"))
}

function Test-CanonicalParity {
    param($Scenario, [string]$Mode, [string]$Project)
    $paths = @($catalog.core)
    $topicNames = @($Scenario.topics)
    foreach ($profileName in @($Scenario.profiles)) {
        $profile = $catalog.profiles.PSObject.Properties[$profileName].Value
        $paths += [string]$profile.file
        $topicNames += @($profile.topics)
    }
    foreach ($topicName in @($topicNames | Sort-Object -Unique)) { $paths += [string]$catalog.topics.PSObject.Properties[$topicName].Value.file }
    $evidence = @()
    foreach ($relative in @($paths | Sort-Object -Unique)) {
        $expected = Get-NormalizedFileDigest (Join-Path $cleanSource $relative)
        if ($Mode -eq 'snapshot') {
            $mapped = if ($relative -eq 'rules/CORE.md') { 'CORE.md' } else { $relative }
            $installed = Join-Path $Project ".ai-rules/upstream/$mapped"
        }
        else { $installed = Join-Path $releaseRoot $relative }
        if (-not (Test-Path -LiteralPath $installed -PathType Leaf) -or (Get-NormalizedFileDigest $installed) -ne $expected) { throw "Canonical parity failed: $Mode/$relative" }
        if ($Mode -eq 'shared' -and 'project-audit' -in $Scenario.topics) {
            $reference = Join-Path $releaseRoot "skills/aek-project-audit/references/$relative"
            if (-not (Test-Path -LiteralPath $reference -PathType Leaf) -or (Get-NormalizedFileDigest $reference) -ne $expected) { throw "Skill reference parity failed: $relative" }
        }
        $evidence += [pscustomobject]@{ path = $relative; sha256 = $expected }
    }
    foreach ($local in @('.ai-rules/PROJECT_RULES.md','.ai-rules/RULESET.md')) {
        if ((Get-NormalizedFileDigest (Join-Path $Project $local)) -ne $localExpected[$local]) { throw 'Tooling changed project-owned local context.' }
    }
    if ($Mode -eq 'snapshot') {
        $lock = Get-Content -LiteralPath (Join-Path $Project '.ai-rules/lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($lock.source.revision -ne $revision -or $lock.source.dirty) { throw 'Snapshot is not pinned to the clean canonical revision.' }
    }
    else {
        $connection = Get-Content -LiteralPath (Join-Path $Project '.ai-rules/shared.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($connection.releaseId -ne $releaseManifest.releaseId -or $connection.releaseDigest -ne $releaseManifest.digest) { throw 'Shared connection is not pinned to the verified release.' }
    }
    return @($evidence)
}

function Invoke-Tooling {
    param([string]$ScriptPath, [string[]]$ToolArguments, [string]$LogPath)
    $shell = (Get-Process -Id $PID).Path
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $shell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ToolArguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    Write-Text -Path $LogPath -Content ($output -join "`n")
    if ($code -ne 0) { throw 'Fixture tooling failed; inspect the private tooling log. No success is inferred.' }
}

function Get-FileInventory {
    param([string]$Root)
    $files = @()
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
            if ($entry.Name -eq '.git') { continue }
            $relative = $entry.FullName.Substring($Root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $files += [pscustomobject]@{ path = $relative; sha256 = '<directory-link>' }
            }
            elseif ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
            else { $files += [pscustomobject]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } }
        }
    }
    return @($files | Sort-Object path)
}

function Get-SafeConfiguredScalars {
    $taskHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
    $configPath = Join-Path $taskHome 'config.toml'
    $scalars = [ordered]@{}
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        # Inspect only safe top-level model fields. Never copy config or authentication.
        foreach ($line in [IO.File]::ReadAllLines($configPath)) {
            if ($line -match '^\s*\[') { break }
            if ($line -match '^\s*(model|model_reasoning_effort)\s*=\s*["'']([A-Za-z0-9_.:/-]+)["'']\s*(?:#.*)?$') {
                $scalars[$matches[1]] = $matches[2]
            }
        }
    }
    $ambient = @()
    foreach ($relative in @('AGENTS.md', 'AGENTS.override.md')) {
        $path = Join-Path $taskHome $relative
        $ambient += [pscustomobject]@{
            source = "codex-home/$relative"
            present = (Test-Path -LiteralPath $path -PathType Leaf)
            sha256 = $(if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null })
        }
    }
    return [pscustomobject]@{ scalars = $scalars; ambient = $ambient }
}

function Quote-ProcessArgument {
    param([string]$Argument)
    # ProcessStartInfo.Arguments requires native quoting on Windows PowerShell 5.1.
    return '"' + ([regex]::Replace(([regex]::Replace($Argument, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}

function Invoke-CodexRun {
    param([string]$Executable, [string[]]$CliArguments, [string]$Task, [string]$Project, [string]$OutputRoot)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (($CliArguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' ')
    $start.WorkingDirectory = $Project
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $utf8
    $start.StandardErrorEncoding = $utf8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $taskBytes = $utf8.GetBytes($Task)
        $process.StandardInput.BaseStream.Write($taskBytes, 0, $taskBytes.Length)
        $process.StandardInput.BaseStream.Flush()
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $timedOut = $true; $process.Kill() }
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        Write-Text -Path (Join-Path $OutputRoot 'events.jsonl') -Content $stdout
        Write-Text -Path (Join-Path $OutputRoot 'stderr.txt') -Content $stderr
        return [pscustomobject]@{ stdout = $stdout; exitCode = $process.ExitCode; timedOut = $timedOut; elapsedMs = $watch.ElapsedMilliseconds }
    }
    finally { $watch.Stop(); $process.Dispose() }
}

function Get-ObservedResult {
    param($Execution, [string]$OutputRoot)
    $commands = @()
    $sourceMentions = New-Object 'System.Collections.Generic.HashSet[string]'
    $usage = $null
    $actualModel = $null
    $final = $null
    $parseErrors = 0
    $turnFailed = $false
    foreach ($line in ($Execution.stdout -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json }
        catch { $parseErrors++; continue }
        if ($event.type -eq 'turn.completed') { $usage = $event.usage }
        if ($event.type -eq 'turn.failed' -or $event.type -eq 'error') { $turnFailed = $true }
        if ($event.model -and [string]$event.model -match '^[A-Za-z0-9_.:/-]+$') { $actualModel = [string]$event.model }
        if ($event.type -eq 'item.completed' -and $event.item.type -eq 'agent_message') { $final = [string]$event.item.text }
        if ($event.type -eq 'item.completed' -and $event.item.type -eq 'command_execution') {
            $commands += $event.item
            foreach ($name in @('CORE.md','QUALITY.md','RESEARCH_AND_EVIDENCE.md','PROJECT_RULES.md','RULESET.md','PROJECT_DEEP_AUDIT.md','SKILL.md','workflow.md','INDEX.md')) {
                if ([string]$event.item.command -match [regex]::Escape($name)) { [void]$sourceMentions.Add($name) }
            }
        }
    }
    Write-Json -Path (Join-Path $OutputRoot 'command-evidence.private.json') -Value @($commands)
    if ($null -ne $final) { Write-Text -Path (Join-Path $OutputRoot 'final-from-events.txt') -Content $final }
    $safeUsage = $null
    if ($null -ne $usage) {
        $safeUsage = [ordered]@{}
        foreach ($key in @('input_tokens','cached_input_tokens','output_tokens')) {
            if ($null -ne $usage.$key -and [string]$usage.$key -match '^\d+$') { $safeUsage[$key] = [long]$usage.$key }
        }
    }
    return [pscustomobject]@{
        exitCode = $Execution.exitCode; timedOut = $Execution.timedOut; elapsedMs = $Execution.elapsedMs
        eventParseErrors = $parseErrors; turnFailureObserved = $turnFailed; actualModel = $actualModel
        commandCount = $commands.Count; sourceMentions = @($sourceMentions | Sort-Object)
        sourceEvidenceMeaning = 'Command mentions only; a human must inspect output/order to establish reading.'
        usage = $safeUsage; finalPresent = ($null -ne $final); finalSha256 = $(if ($null -ne $final) { Get-Digest $final } else { $null })
        eventsSha256 = (Get-FileHash -LiteralPath (Join-Path $OutputRoot 'events.jsonl') -Algorithm SHA256).Hash.ToLowerInvariant()
        taskSuccess = $null; humanReview = 'pending'
    }
}

if ($scenariosDocument.schemaVersion -ne '0.1' -or @($scenariosDocument.scenarios).Count -ne 3) { throw 'Expected exactly three paired delivery scenarios.' }
$ids = @()
foreach ($scenario in $scenariosDocument.scenarios) {
    if ($scenario.id -notmatch '^[a-z0-9-]+$' -or $scenario.id -in $ids) { throw 'Scenario IDs must be safe and unique.' }
    $ids += $scenario.id
    if ([string]::IsNullOrWhiteSpace($scenario.task) -or @($scenario.reviewCriteria).Count -eq 0) { throw 'Task and separate human criteria are required.' }
    foreach ($file in $scenario.files.PSObject.Properties) {
        if ($file.Name -match '(^[./\\]|(^|[/\\])\.\.([/\\]|$)|:)' -or $file.Name -match '(^|[/\\])\.git([/\\]|$)') { throw 'Fixture file path must be relative and confined.' }
    }
}
if ($ValidateOnly) { Write-Output 'Delivery scenarios validated; no fixture or agent was started.'; return }

if (-not $WorkRoot) { $WorkRoot = Join-Path $hubRoot '.local-docs/delivery-eval' }
$workRootFull = [IO.Path]::GetFullPath($WorkRoot)
$privatePrefix = [IO.Path]::GetFullPath((Join-Path $hubRoot '.local-docs')).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
if (-not $workRootFull.StartsWith($privatePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Raw fixtures and logs must stay under this workspace .local-docs directory.' }
$ancestor = $workRootFull
while ($ancestor -and $ancestor.Length -ge $hubRoot.Length) {
    if (Test-Path -LiteralPath $ancestor) {
        if (((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Private output ancestors must not be filesystem links.' }
    }
    $ancestor = Split-Path -Parent $ancestor
}
$sharedScript = Join-Path $hubRoot 'scripts/shared-kit.ps1'
if (-not (Test-Path -LiteralPath $sharedScript -PathType Leaf)) { throw 'The reviewed shared-kit prototype is required before fixture preparation.' }
$runRoot = Join-Path $workRootFull ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$cleanSource = Join-Path $runRoot 'source'
$revision = (Invoke-Git @('-C', $sourceRootFull, 'rev-parse', "$SourceRevision^{commit}")).Trim()
[void](Invoke-Git @('clone','--local','--no-hardlinks','--no-checkout','--',$sourceRootFull,$cleanSource))
[void](Invoke-Git @('-C',$cleanSource,'checkout','--detach',$revision))
$installRoot = Join-Path $runRoot 'installation'
Invoke-Tooling -ScriptPath $sharedScript -ToolArguments @('install','-InstallRoot',$installRoot,'-SourceRoot',$cleanSource,'-Apply') -LogPath (Join-Path $runRoot 'install.private.log')
$selectedRelease = Get-Content -LiteralPath (Join-Path $installRoot 'selected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$releaseRoot = Join-Path $installRoot "releases/$($selectedRelease.releaseId)"
$releaseManifest = Get-Content -LiteralPath (Join-Path $releaseRoot 'release.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($releaseManifest.identity.sourceRevision -ne $revision) { throw 'Installed shared release does not match the clean source revision.' }
$catalog = Get-Content -LiteralPath (Join-Path $cleanSource 'sync/catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$configured = Get-SafeConfiguredScalars
$modelSource = 'configured safe scalar or CLI default'
if ($Model) { $configured.scalars['model'] = $Model; $modelSource = 'explicit same-model override for all paired attempts' }
$cliPath = $null
$cliVersion = $null
if ($Execute) {
    $cliPath = (Get-Command $CodexExecutable -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    if ([IO.Path]::GetExtension($cliPath) -in @('.cmd','.bat','.ps1')) { throw 'Choose the native Codex executable; shell wrappers are not used.' }
    $cliVersion = (@(& $cliPath --version 2>$null) -join '').Trim()
    $helpText = (@(& $cliPath exec --help 2>$null) -join "`n")
    foreach ($required in @('--ignore-user-config','--json','--ephemeral','--sandbox')) {
        if (-not $helpText.Contains($required)) { throw 'The installed CLI lacks a required paired-run flag.' }
    }
}
$attempts = @()
$index = 0
foreach ($scenario in @($scenariosDocument.scenarios | Where-Object { -not $ScenarioId -or $_.id -eq $ScenarioId })) {
    $index++
    $taskText = [string]$scenario.task
    if ($UseRipgrepForReads) { $taskText = "Reading the synthetic project files and already connected Kit resources is authorized. Use individual rg -n commands for reading; do not chain them with other commands. Preserve the analysis scope and prohibition on writes.`n`n" + $taskText }
    $order = if (($index % 2) -eq 1) { @('snapshot','shared') } else { @('shared','snapshot') }
    foreach ($mode in $order) {
        $project = Join-Path $runRoot "$($scenario.id)/$mode/project"
        $outputRoot = Join-Path $runRoot "$($scenario.id)/$mode/evidence"
        New-Item -ItemType Directory -Path $project,$outputRoot -Force | Out-Null
        foreach ($file in $scenario.files.PSObject.Properties) { Write-Text (Join-Path $project $file.Name) ([string]$file.Value) }
        Write-Text (Join-Path $project '.ai-rules/PROJECT_RULES.md') ([string]$scenario.localContext)
        Write-Text (Join-Path $project '.ai-rules/RULESET.md') "# Fixture selections`nProfiles: $($scenario.profiles -join ', ')`nTopics: $($scenario.topics -join ', ')`nNo local exceptions.`n"
        $localExpected = @{}
        foreach ($local in @('.ai-rules/PROJECT_RULES.md','.ai-rules/RULESET.md')) { $localExpected[$local] = Get-NormalizedFileDigest (Join-Path $project $local) }
        [void](Invoke-Git @('-C',$project,'init'))
        [void](Invoke-Git @('-C',$project,'add','--all'))
        [void](Invoke-Git @('-C',$project,'-c','core.hooksPath=','-c','user.name=Kit Synthetic Eval','-c','user.email=kit-eval@example.invalid','commit','-m','Synthetic fixture base'))
        Write-Text (Join-Path $project 'OWNER_NOTES.md') ([string]$scenario.ownerChange)
        $arguments = @('connect','-ProjectRoot',$project,'-Profiles',($scenario.profiles -join ','),'-Apply')
        if (@($scenario.topics).Count -gt 0) { $arguments += @('-Topics',($scenario.topics -join ',')) }
        if ($mode -eq 'snapshot') { $scriptPath = Join-Path $cleanSource 'ai-rules.ps1' }
        else { $scriptPath = $sharedScript; $arguments += @('-InstallRoot',$installRoot) }
        $previewArguments = @($arguments | Where-Object { $_ -ne '-Apply' })
        Invoke-Tooling -ScriptPath $scriptPath -ToolArguments $previewArguments -LogPath (Join-Path $outputRoot 'connect-preview.private.log')
        Invoke-Tooling -ScriptPath $scriptPath -ToolArguments $arguments -LogPath (Join-Path $outputRoot 'connect.private.log')
        foreach ($command in @('doctor','status')) {
            Invoke-Tooling -ScriptPath $scriptPath -ToolArguments @($command,'-ProjectRoot',$project) -LogPath (Join-Path $outputRoot "$command.private.log")
        }
        $canonicalEvidence = Test-CanonicalParity -Scenario $scenario -Mode $mode -Project $project
        $before = Get-FileInventory $project
        $statusBefore = Invoke-Git @('-C',$project,'status','--porcelain')
        Write-Json (Join-Path $outputRoot 'before.private.json') $before
        Write-Text (Join-Path $outputRoot 'task.txt') $taskText
        $attempt = [ordered]@{
            scenario = $scenario.id; mode = $mode; order = [array]::IndexOf($order,$mode) + 1
            taskSha256 = Get-Digest $taskText
            fixtureSha256 = Get-Digest (($scenario.files | ConvertTo-Json -Compress -Depth 10) + $scenario.localContext + $scenario.ownerChange)
            sourceRevision = $revision; state = 'prepared'; observation = $null; projectUnchanged = $null
            canonicalFiles = @($canonicalEvidence); localContextSha256 = $localExpected['.ai-rules/PROJECT_RULES.md']
        }
        if ($Execute) {
            $cliArguments = @('exec','--ignore-user-config','--ephemeral','--json','--sandbox','read-only','-c','approval_policy="never"','-C',$project,'-o',(Join-Path $outputRoot 'last-message.txt'))
            foreach ($key in $configured.scalars.Keys) { $cliArguments += @('-c',($key + '="' + $configured.scalars[$key] + '"')) }
            $cliArguments += '-'
            Write-Json (Join-Path $outputRoot 'invocation.private.json') $cliArguments
            Write-Output "Running $($scenario.id): $mode (read-only, approval never)."
            $execution = Invoke-CodexRun -Executable $cliPath -CliArguments $cliArguments -Task $taskText -Project $project -OutputRoot $outputRoot
            $attempt.observation = Get-ObservedResult -Execution $execution -OutputRoot $outputRoot
            $attempt.state = if ($execution.timedOut) { 'timed-out' } elseif ($execution.exitCode -ne 0) { 'execution-failed' } else { 'completed-awaiting-review' }
            $after = Get-FileInventory $project
            Write-Json (Join-Path $outputRoot 'after.private.json') $after
            $attempt.projectUnchanged = (($before | ConvertTo-Json -Compress -Depth 10) -eq ($after | ConvertTo-Json -Compress -Depth 10)) -and ($statusBefore -eq (Invoke-Git @('-C',$project,'status','--porcelain')))
        }
        $attempts += [pscustomobject]$attempt
        Write-Json (Join-Path $runRoot 'summary.json') ([ordered]@{
            schemaVersion='0.1'; sourceRevision=$revision; scenariosSha256=(Get-FileHash -LiteralPath $scenariosPath -Algorithm SHA256).Hash.ToLowerInvariant()
            releaseId=$releaseManifest.releaseId; releaseDigest=$releaseManifest.digest
            runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant(); cliVersion=$cliVersion
            readingConstraint=$(if ($UseRipgrepForReads) { 'identical explicit single-command rg read constraint in every paired task' } else { 'none' })
            scenarioFilter=$ScenarioId
            configuredScalars=$configured.scalars; modelSelection=$modelSource; modelResolution=$(if ($configured.scalars.Contains('model')) { 'safe scalar applied equally through config override' } else { 'not resolved; CLI default, actual model may remain unknown' })
            security=[ordered]@{ sandbox='read-only'; approval='never'; userConfig='ignored'; auth='native existing CODEX_HOME; credentials not read or copied'; ambientGuidance=$configured.ambient }
            attempts=$attempts; humanReview='pending'; causalClaim='none'
            limitations=@('Ambient global guidance/skills may remain; equal configuration is not proof of identical runtime permissions.','One pair per scenario is diagnostic, not causal evidence of general quality.','Command source mentions do not by themselves prove loading.','Raw logs and final text are private; review before publishing even the digest.','Doctor/status establish fixture installation, not agent behavior.')
        })
    }
}
Write-Output "Private paired-run artifacts: $runRoot"
Write-Output $(if ($Execute) { 'Attempts collected; task success and rule reading require human review.' } else { 'Fixtures prepared only; no agent or API request was started. Use -Execute only after review.' })

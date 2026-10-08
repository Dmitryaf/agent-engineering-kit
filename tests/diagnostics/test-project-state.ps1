[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$projectRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ai-rules-project-state-$([Guid]::NewGuid().ToString('N'))"

try {
    New-Item -ItemType Directory -Path $projectRoot | Out-Null
    Import-Module (Join-Path $hubRoot 'src/ProjectState.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $hubRoot 'src/Diagnostics.psm1') -Force -ErrorAction Stop
    $state = Get-AiRulesProjectState -HubRoot $hubRoot -ProjectRoot $projectRoot
    $assessment = Get-AiRulesStatusAssessment -ProjectState $state

    if ($state.PSObject.TypeNames[0] -ne 'AiRules.ProjectState') { throw 'ProjectState module must return the typed contract.' }
    if ($state.Found.Manifest) { throw 'Empty fixture must not report a manifest.' }
    if ($assessment.State -ne 'not-initialized') { throw 'Diagnostics must classify an empty fixture as not-initialized.' }
    [void][System.IO.Directory]::CreateDirectory((Join-Path $projectRoot '.ai-rules/upstream'))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $projectRoot '.agent/releases'))
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $packagePath = Join-Path $projectRoot 'package.json'
    $ignorePath = Join-Path $projectRoot '.prettierignore'
    [System.IO.File]::WriteAllText($packagePath, '{"scripts":{"format:check":"prettier . --check --ignore-unknown"}}', $utf8)
    $before = (Get-FileHash -LiteralPath $packagePath).Hash
    $warnings = @(Get-AiRulesProjectToolWarnings -ProjectRoot $projectRoot)
    if ($warnings.Count -ne 2 -or ($warnings -join ' ') -notmatch '\.ai-rules/' -or ($warnings -join ' ') -notmatch '\.agent/releases/') { throw 'Root formatter must warn about both unexcluded runtime directories.' }
    if (Test-Path -LiteralPath $ignorePath) { throw 'Tool diagnostics must not create project configuration.' }
    if ((Get-FileHash -LiteralPath $packagePath).Hash -ne $before) { throw 'Tool diagnostics must preserve package.json.' }
    [System.IO.File]::WriteAllText($ignorePath, "/.ai-rules/`n.agent/releases/`n", $utf8)
    if (@(Get-AiRulesProjectToolWarnings -ProjectRoot $projectRoot).Count -ne 0) { throw 'Explicit exclusions must clear the warnings.' }
    [System.IO.File]::AppendAllText($ignorePath, '!**/catalog.json', $utf8)
    if (@(Get-AiRulesProjectToolWarnings -ProjectRoot $projectRoot).Count -ne 2) { throw 'Negated exclusions must remain unconfirmed.' }
    [System.IO.File]::WriteAllText($packagePath, '{"scripts":{"format:check":"prettier src tests --check"}}', $utf8)
    if (@(Get-AiRulesProjectToolWarnings -ProjectRoot $projectRoot).Count -ne 0) { throw 'A scoped formatter must not produce a root-scan warning.' }
    Write-Host 'Project state and diagnostics tests passed: 9 assertions.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $projectRoot) { Remove-Item -LiteralPath $projectRoot -Recurse -Force }
}

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
    Write-Host 'Project state and diagnostics tests passed: 3 assertions.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $projectRoot) { Remove-Item -LiteralPath $projectRoot -Recurse -Force }
}

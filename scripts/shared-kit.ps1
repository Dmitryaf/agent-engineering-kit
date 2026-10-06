[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('install', 'connect', 'select', 'status', 'doctor')][string]$Command = 'status',
    [string]$InstallRoot,
    [string]$ProjectRoot,
    [string]$SourceRoot,
    [string]$ReleaseId,
    [string[]]$Profiles = @('standard-product'),
    [string[]]$Topics = @(),
    [string]$LocalRules = '.ai-rules/PROJECT_RULES.md',
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) { $SourceRoot = Split-Path -Parent $PSScriptRoot }
$Profiles = @($Profiles | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
$Topics = @($Topics | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
Import-Module (Join-Path $PSScriptRoot '../src/SharedInstall.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../src/CodexAdapter.psm1') -ErrorAction Stop
try {
    switch ($Command) {
        'install' {
            if ([string]::IsNullOrWhiteSpace($InstallRoot)) { throw 'Specify -InstallRoot.' }
            $plan = New-AekReleasePlan -SourceRoot $SourceRoot
            Write-Host "Experimental shared release: $($plan.ReleaseId)"
            Write-Host "Canonical revision: $($plan.Manifest.identity.sourceRevision)"
            Write-Host "Integrity: $($plan.Manifest.digest)"
            if ($Apply) {
                $path = Install-AekRelease -Plan $plan -InstallRoot $InstallRoot
                Set-AekSelectedRelease -InstallRoot $InstallRoot -ReleaseId $plan.ReleaseId
                Write-Host "Installed and selected: $path"
            }
            else { Write-Host 'Preview only. Use -Apply to install and select for new connections.' }
        }
        'select' {
            if ([string]::IsNullOrWhiteSpace($InstallRoot) -or [string]::IsNullOrWhiteSpace($ReleaseId)) { throw 'Specify -InstallRoot and -ReleaseId.' }
            [void](Resolve-AekRelease -InstallRoot $InstallRoot -ReleaseId $ReleaseId)
            if ($Apply) { Set-AekSelectedRelease -InstallRoot $InstallRoot -ReleaseId $ReleaseId }
            Write-Host "Selected for new connections$(if (-not $Apply) { ' (preview)' }): $ReleaseId"
            Write-Host 'Existing pinned projects and running sessions are unchanged.'
        }
        'connect' {
            if ([string]::IsNullOrWhiteSpace($ProjectRoot) -or [string]::IsNullOrWhiteSpace($InstallRoot)) { throw 'Specify -ProjectRoot and -InstallRoot.' }
            $plan = Get-AekSharedConnectionPlan -ProjectRoot $ProjectRoot -InstallRoot $InstallRoot -ReleaseId $ReleaseId -Profiles $Profiles -Topics $Topics -LocalRules $LocalRules
            Write-Host "Mode: shared; policy: pinned; release: $($plan.Config.releaseId)"
            Write-Host 'Project files: AGENTS.md managed block and .ai-rules/shared.json; project-owned local rules are preserved.'
            if ($plan.IncludeSkill) { Write-Host 'Skill: project-scoped link to the pinned shared release.' }
            if ($Apply) { Connect-AekCodexProject -Plan $plan; Write-Host 'Connected. Start a new Codex session in the project.' }
            else { Write-Host 'Preview only. Use -Apply to connect.' }
        }
        { $_ -in @('status', 'doctor') } {
            if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { throw 'Specify -ProjectRoot.' }
            $status = Get-AekSharedProjectStatus -ProjectRoot $ProjectRoot
            $status | ConvertTo-Json -Depth 8
            if ($status.available -eq 'unknown') { exit 1 }
        }
    }
}
catch { Write-Error $_.Exception.Message; exit 1 }

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Import-Module (Join-Path $hubRoot 'src/Contracts.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $hubRoot 'src/Catalog.psm1') -Force -ErrorAction Stop

$entries = @(
    [pscustomobject]@{ Action = 'unchanged' },
    [pscustomobject]@{ Action = 'conflict' }
)
$plan = New-AiRulesSyncPlan -ProjectRoot 'C:\fixture' -HubRoot $hubRoot -Catalog ([pscustomobject]@{}) -Manifest ([pscustomobject]@{}) -HubRevision $null -HubDirty $null -ExpectedRevision $null -Topics @() -Profiles @() -Entries $entries -PreviousLock $null
$diagnostic = New-AiRulesDiagnostic -Level 'WARN' -Category 'contract' -Message 'fixture'
$state = New-AiRulesProjectState -Properties @{ State = 'fixture' }

if ($plan.PSObject.TypeNames[0] -ne 'AiRules.SyncPlan') { throw 'Sync plan type name is not stable.' }
if ($plan.Summary['unchanged'] -ne 1 -or $plan.Summary['conflict'] -ne 1 -or -not $plan.HasConflicts) { throw 'Sync plan summary contract is invalid.' }
if ($diagnostic.PSObject.TypeNames[0] -ne 'AiRules.Diagnostic' -or $diagnostic.Category -ne 'contract') { throw 'Diagnostic contract is invalid.' }
if ($state.PSObject.TypeNames[0] -ne 'AiRules.ProjectState') { throw 'Project state type name is not stable.' }

$catalog = Get-AiRulesCatalog -HubRoot $hubRoot
Assert-AiRulesSelections -Catalog $catalog -SelectedProfiles @('standard-product') -SelectedTopics @('')

Write-Host 'Contract tests passed: 5 assertions.' -ForegroundColor Green

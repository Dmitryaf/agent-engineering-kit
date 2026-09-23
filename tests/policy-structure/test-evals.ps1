[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$assertionCount = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertionCount++
}

$expectedControlIds = @(
    'scope.no-unrelated-changes',
    'owner.explicit-apply',
    'sync.preview-readonly',
    'sync.preserve-conflicts',
    'data.preserve-unknown',
    'evidence.separate-fact-assumption',
    'verification.risk-based',
    'context.load-relevant-only'
)
$controlsDocument = Get-Content -LiteralPath (Join-Path $hubRoot 'evals/controls.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$controlIds = @($controlsDocument.controls | ForEach-Object { [string]$_.id })
Assert-True ($controlsDocument.schemaVersion -eq '0.1') 'controls schema version must be 0.1'
Assert-True ($controlIds.Count -eq 8) 'exactly eight controls are required'
Assert-True ((@($controlIds | Sort-Object) -join "`n") -eq (@($expectedControlIds | Sort-Object) -join "`n")) 'control IDs must match the stage contract'
Assert-True (@($controlIds | Sort-Object -Unique).Count -eq $controlIds.Count) 'control IDs must be unique'
foreach ($control in @($controlsDocument.controls)) {
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$control.intent)) "control intent is required: $($control.id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$control.passCriterion)) "pass criterion is required: $($control.id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$control.violationCriterion)) "violation criterion is required: $($control.id)"
}

$caseFiles = @(Get-ChildItem -LiteralPath (Join-Path $hubRoot 'evals/cases') -File -Filter '*.json' | Sort-Object Name)
Assert-True ($caseFiles.Count -eq 15) 'exactly fifteen representative cases are required'
$caseIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$positiveCoverage = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$negativeCoverage = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($caseFile in $caseFiles) {
    $case = Get-Content -LiteralPath $caseFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($case.schemaVersion -eq '0.1') "case schema version must be 0.1: $($caseFile.Name)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$case.id)) "case ID is required: $($caseFile.Name)"
    Assert-True ($caseIds.Add([string]$case.id)) "case ID must be unique: $($case.id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$case.fixture.description)) "fixture description is required: $($case.id)"
    Assert-True (@($case.fixture.initialState).Count -gt 0) "fixture state is required: $($case.id)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$case.task)) "task is required: $($case.id)"
    Assert-True (@($case.expectedChecks).Count -gt 0) "expected checks are required: $($case.id)"
    Assert-True (@($case.prohibitedActions).Count -gt 0) "prohibited actions are required: $($case.id)"
    Assert-True (@($case.controlExpectations).Count -gt 0) "control expectations are required: $($case.id)"
    foreach ($expectation in @($case.controlExpectations)) {
        $controlId = [string]$expectation.controlId
        Assert-True ($controlId -in $controlIds) "case references an unknown control: $controlId"
        Assert-True (@($expectation.positiveSignals).Count -gt 0) "positive signals are required: $($case.id)/$controlId"
        Assert-True (@($expectation.negativeSignals).Count -gt 0) "negative signals are required: $($case.id)/$controlId"
        [void]$positiveCoverage.Add($controlId)
        [void]$negativeCoverage.Add($controlId)
    }
}
foreach ($controlId in $controlIds) {
    Assert-True ($positiveCoverage.Contains($controlId)) "control needs a positive case signal: $controlId"
    Assert-True ($negativeCoverage.Contains($controlId)) "control needs a negative case signal: $controlId"
}

$deepAuditCasePath = Join-Path $hubRoot 'evals/cases/13-deep-audit-boundary-coverage.json'
$deepAuditCase = Get-Content -LiteralPath $deepAuditCasePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($deepAuditCase.id -eq 'deep-audit-boundary-coverage') 'deep-audit case ID must stay stable'
Assert-True (@($deepAuditCase.fixture.failureSequence).Count -ge 5) 'deep-audit fixture must define the cross-component failure sequence'
$deepAuditFixtureRoot = Join-Path $hubRoot ([string]$deepAuditCase.fixture.path)
Assert-True (Test-Path -LiteralPath $deepAuditFixtureRoot -PathType Container) 'deep-audit fixture path must exist'
foreach ($fixturePath in @('service-manifest.json', 'src/routes.js', 'src/workers/registry.js', 'src/api/create-order.js', 'src/queue/leased-jobs.js', 'src/workers/payment.js', 'src/adapters/gateway.js', 'test/create-order.test.js', 'test/leased-jobs.test.js', 'test/payment.test.js')) {
    Assert-True (Test-Path -LiteralPath (Join-Path $deepAuditFixtureRoot $fixturePath) -PathType Leaf) "deep-audit fixture file is required: $fixturePath"
}
Assert-True (-not (Test-Path -LiteralPath (Join-Path $deepAuditFixtureRoot 'src/admin/export.js'))) 'deep-audit fixture must keep the inventory gap observable'
$deepAuditText = $deepAuditCase | ConvertTo-Json -Depth 10
foreach ($requiredControlId in @('evidence.separate-fact-assumption', 'verification.risk-based', 'context.load-relevant-only')) {
    Assert-True ($requiredControlId -in @($deepAuditCase.controlExpectations.controlId)) "deep-audit case must reuse control: $requiredControlId"
}
Assert-True ($deepAuditText -match 'not-checked' -and $deepAuditText -match 'admin/export') 'deep-audit case must keep untested scope visible'
Assert-True ($deepAuditText -match 'gateway' -and $deepAuditText -match 'payment-1' -and $deepAuditText -match 'idempotency') 'deep-audit case must expose the repeated external effect'

$successiveAuditCasePath = Join-Path $hubRoot 'evals/cases/14-successive-audit-fixture-provenance.json'
$successiveAuditCase = Get-Content -LiteralPath $successiveAuditCasePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($successiveAuditCase.id -eq 'successive-audit-fixture-provenance') 'successive-audit case ID must stay stable'
$successiveAuditText = $successiveAuditCase | ConvertTo-Json -Depth 10
Assert-True ($successiveAuditText -match 'previous-register' -and $successiveAuditText -match 'unknown' -and $successiveAuditText -match 'not-checked') 'successive-audit case must preserve prior coverage limits'
Assert-True ($successiveAuditText -match 'adjacent-event' -and $successiveAuditText -match 'official-schema' -and $successiveAuditText -match 'observed-event') 'successive-audit case must expose fixture provenance'
foreach ($requiredControlId in @('evidence.separate-fact-assumption', 'verification.risk-based', 'context.load-relevant-only')) {
    Assert-True ($requiredControlId -in @($successiveAuditCase.controlExpectations.controlId)) "successive-audit case must reuse control: $requiredControlId"
}

$protectedPromotionCasePath = Join-Path $hubRoot 'evals/cases/15-protected-branch-ci-promotion.json'
$protectedPromotionCase = Get-Content -LiteralPath $protectedPromotionCasePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($protectedPromotionCase.id -eq 'protected-branch-ci-promotion') 'protected-promotion case ID must stay stable'
$protectedPromotionText = $protectedPromotionCase | ConvertTo-Json -Depth 10
Assert-True ($protectedPromotionText -match 'task' -and $protectedPromotionText -match 'branch Preview' -and $protectedPromotionText -match 'develop') 'protected-promotion case must isolate diagnostic work from the integration branch'
Assert-True ($protectedPromotionText -match 'source commit' -and $protectedPromotionText -match 'staging' -and $protectedPromotionText -match 'pending') 'protected-promotion case must gate the persistent environment on the exact candidate'
Assert-True ($protectedPromotionText -match 'CI job' -and $protectedPromotionText -match 'timeout' -and $protectedPromotionText -match 'retry') 'protected-promotion case must stop serial timeout patches after a repeated failure class'
foreach ($requiredControlId in @('scope.no-unrelated-changes', 'owner.explicit-apply', 'evidence.separate-fact-assumption', 'verification.risk-based')) {
    Assert-True ($requiredControlId -in @($protectedPromotionCase.controlExpectations.controlId)) "protected-promotion case must reuse control: $requiredControlId"
}

$resultTemplate = Get-Content -LiteralPath (Join-Path $hubRoot 'evals/runs/RESULT_TEMPLATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($resultTemplate.schemaVersion -eq '0.2') 'result template schema version must be 0.2'
foreach ($field in @('runId', 'caseId', 'subject', 'taskSuccess', 'controlResults', 'inventoryResults', 'coverageResults', 'violations', 'unrelatedChangedFiles', 'unknownDataPreserved', 'checksRun', 'evidence', 'notes')) {
    Assert-True ($null -ne $resultTemplate.PSObject.Properties[$field]) "result template field is required: $field"
}
foreach ($field in @('agent', 'hubRevision', 'workflowRevision', 'fixtureRevision', 'environment')) {
    Assert-True ($null -ne $resultTemplate.subject.PSObject.Properties[$field]) "result subject field is required: $field"
}
foreach ($field in @('platform', 'runner', 'workspaceAccess', 'networkAccess', 'shellCommands')) {
    Assert-True ($null -ne $resultTemplate.subject.environment.PSObject.Properties[$field]) "result environment field is required: $field"
}
$controlResultTemplate = @($resultTemplate.controlResults)[0]
foreach ($field in @('controlId', 'status', 'evidence', 'notes')) {
    Assert-True ($null -ne $controlResultTemplate.PSObject.Properties[$field]) "control result field is required: $field"
}
Assert-True ($controlResultTemplate.status -in @('pass', 'violation', 'unknown', 'not-observed')) 'control result status must use the documented vocabulary'
$inventoryResultTemplate = @($resultTemplate.inventoryResults)[0]
foreach ($field in @('item', 'source', 'disposition', 'mapRefs', 'evidence', 'notes')) {
    Assert-True ($null -ne $inventoryResultTemplate.PSObject.Properties[$field]) "inventory result field is required: $field"
}
Assert-True ($inventoryResultTemplate.disposition -in @('mapped', 'excluded', 'unknown')) 'inventory result disposition must use the documented vocabulary'
$coverageResultTemplate = @($resultTemplate.coverageResults)[0]
foreach ($field in @('area', 'property', 'status', 'evidence', 'notes')) {
    Assert-True ($null -ne $coverageResultTemplate.PSObject.Properties[$field]) "coverage result field is required: $field"
}
Assert-True ($coverageResultTemplate.status -in @('checked-no-finding', 'finding', 'not-applicable', 'unknown', 'not-checked')) 'coverage result status must use the documented vocabulary'

$storedRunFiles = @(Get-ChildItem -LiteralPath (Join-Path $hubRoot 'evals/runs') -File -Filter '*.json' | Where-Object { $_.Name -ne 'RESULT_TEMPLATE.json' })
Assert-True ($storedRunFiles.Count -ge 2) 'at least one observed eval run pair is required'
foreach ($runFile in $storedRunFiles) {
    $runText = Get-Content -LiteralPath $runFile.FullName -Raw -Encoding UTF8
    $run = $runText | ConvertFrom-Json
    Assert-True ($run.schemaVersion -eq '0.2') "stored run schema version must be 0.2: $($runFile.Name)"
    Assert-True ($caseIds.Contains([string]$run.caseId)) "stored run must reference a known case: $($runFile.Name)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$run.subject.agent)) "stored run must identify its agent: $($runFile.Name)"
    Assert-True ([string]$run.subject.hubRevision -match '^[0-9a-f]{40}$') "stored run must identify a full hub revision: $($runFile.Name)"
    Assert-True ([string]$run.subject.workflowRevision -match '^(none|sha256:[0-9a-f]{64})$') "stored run must identify an exact workflow revision or none: $($runFile.Name)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$run.subject.fixtureRevision)) "stored run must identify its fixture: $($runFile.Name)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$run.subject.environment.platform)) "stored run must identify its platform: $($runFile.Name)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$run.subject.environment.runner)) "stored run must identify its runner: $($runFile.Name)"
    Assert-True ([string]$run.subject.environment.workspaceAccess -in @('read-only', 'workspace-write', 'full')) "stored run has an invalid workspace access value: $($runFile.Name)"
    Assert-True ([string]$run.subject.environment.networkAccess -in @('blocked', 'restricted', 'allowed', 'unknown')) "stored run has an invalid network access value: $($runFile.Name)"
    Assert-True ([string]$run.subject.environment.shellCommands -in @('blocked', 'allowed', 'mixed', 'unknown')) "stored run has an invalid shell command value: $($runFile.Name)"
    Assert-True ($run.taskSuccess -is [bool]) "stored run taskSuccess must be boolean: $($runFile.Name)"
    foreach ($controlResult in @($run.controlResults)) {
        Assert-True ([string]$controlResult.controlId -in $controlIds) "stored run references an unknown control: $($runFile.Name)"
        Assert-True ([string]$controlResult.status -in @('pass', 'violation', 'unknown', 'not-observed')) "stored run has an invalid control status: $($runFile.Name)"
    }
    foreach ($inventoryResult in @($run.inventoryResults)) {
        Assert-True ([string]$inventoryResult.disposition -in @('mapped', 'excluded', 'unknown')) "stored run has an invalid inventory disposition: $($runFile.Name)"
    }
    foreach ($coverageResult in @($run.coverageResults)) {
        Assert-True ([string]$coverageResult.status -in @('checked-no-finding', 'finding', 'not-applicable', 'unknown', 'not-checked')) "stored run has an invalid coverage status: $($runFile.Name)"
    }
    Assert-True ($runText -notmatch '(?i)[a-z]:\\users\\|/users/') "stored run must not contain a local user path: $($runFile.Name)"
}

$deepAuditRuns = @($storedRunFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.caseId -eq 'deep-audit-boundary-coverage' })
$deepAuditControl = @($deepAuditRuns | Where-Object { $_.runId -eq 'deep-audit-20260916-control' })[0]
$deepAuditTreatment = @($deepAuditRuns | Where-Object { $_.runId -eq 'deep-audit-20260916-treatment' })[0]
Assert-True ($deepAuditControl.subject.workflowRevision -eq 'none') 'deep-audit control must explicitly record that no workflow was used'
Assert-True ($deepAuditTreatment.subject.workflowRevision -match '^sha256:[0-9a-f]{64}$') 'deep-audit treatment must record the workflow content digest'
Assert-True ($deepAuditControl.subject.environment.shellCommands -ne $deepAuditTreatment.subject.environment.shellCommands) 'deep-audit pair must expose the observed shell-command confound structurally'

Write-Host "Eval structure tests passed: $assertionCount assertions." -ForegroundColor Green

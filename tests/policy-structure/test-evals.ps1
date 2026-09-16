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
Assert-True ($caseFiles.Count -eq 13) 'exactly thirteen representative cases are required'
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
$deepAuditText = $deepAuditCase | ConvertTo-Json -Depth 10
foreach ($requiredControlId in @('evidence.separate-fact-assumption', 'verification.risk-based', 'context.load-relevant-only')) {
    Assert-True ($requiredControlId -in @($deepAuditCase.controlExpectations.controlId)) "deep-audit case must reuse control: $requiredControlId"
}
Assert-True ($deepAuditText -match 'not-checked' -and $deepAuditText -match 'admin/export') 'deep-audit case must keep untested scope visible'
Assert-True ($deepAuditText -match 'gateway' -and $deepAuditText -match 'payment-1' -and $deepAuditText -match 'idempotency') 'deep-audit case must expose the repeated external effect'

$resultTemplate = Get-Content -LiteralPath (Join-Path $hubRoot 'evals/runs/RESULT_TEMPLATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($field in @('runId', 'caseId', 'subject', 'taskSuccess', 'controlResults', 'coverageResults', 'violations', 'unrelatedChangedFiles', 'unknownDataPreserved', 'checksRun', 'evidence', 'notes')) {
    Assert-True ($null -ne $resultTemplate.PSObject.Properties[$field]) "result template field is required: $field"
}
$controlResultTemplate = @($resultTemplate.controlResults)[0]
foreach ($field in @('controlId', 'status', 'evidence', 'notes')) {
    Assert-True ($null -ne $controlResultTemplate.PSObject.Properties[$field]) "control result field is required: $field"
}
Assert-True ($controlResultTemplate.status -in @('pass', 'violation', 'unknown', 'not-observed')) 'control result status must use the documented vocabulary'
$coverageResultTemplate = @($resultTemplate.coverageResults)[0]
foreach ($field in @('area', 'property', 'status', 'evidence', 'notes')) {
    Assert-True ($null -ne $coverageResultTemplate.PSObject.Properties[$field]) "coverage result field is required: $field"
}
Assert-True ($coverageResultTemplate.status -in @('checked-no-finding', 'finding', 'not-applicable', 'unknown', 'not-checked')) 'coverage result status must use the documented vocabulary'

Write-Host "Eval structure tests passed: $assertionCount assertions." -ForegroundColor Green

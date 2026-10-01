[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('audit', 'connect', 'deep-audit', 'study', 'parallel', 'bootstrap')]
    [string]$Name,

    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

switch ($Name) {
    'audit' {
        $promptPath = Join-Path $hubRoot 'workflows/PROJECT_AUDIT_PROMPT.md'
    }
    'connect' {
        if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            throw 'ProjectRoot is required for prompt connect.'
        }
        $promptPath = Join-Path $hubRoot 'workflows/PROJECT_CONNECT_PROMPT.md'
    }
    'deep-audit' {
        if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            throw 'ProjectRoot is required for prompt deep-audit.'
        }
        $promptPath = Join-Path $hubRoot 'workflows/PROJECT_DEEP_AUDIT_PROMPT.md'
    }
    'study' {
        if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            throw 'ProjectRoot is required for prompt study.'
        }
        $promptPath = Join-Path $hubRoot 'workflows/PROJECT_STUDY_PROMPT.md'
    }
    'parallel' {
        if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            throw 'ProjectRoot is required for prompt parallel.'
        }
        $promptPath = Join-Path $hubRoot 'workflows/PARALLEL_DELIVERY_PROMPT.md'
    }
    'bootstrap' {
        if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
            throw 'ProjectRoot is required for prompt bootstrap.'
        }
        $promptPath = Join-Path $hubRoot 'workflows/PROJECT_BOOTSTRAP.md'
    }
}

$promptDocument = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$promptMatch = [regex]::Match($promptDocument, '(?ms)^```text\s*\r?\n(?<prompt>.*?)\r?\n```\s*$')
if (-not $promptMatch.Success) {
    throw "Could not read the prompt from $promptPath."
}

$prompt = $promptMatch.Groups['prompt'].Value.Trim()
if ($Name -in @('connect', 'deep-audit', 'study', 'parallel', 'bootstrap')) {
    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $cliPath = Join-Path $hubRoot 'ai-rules.ps1'
    $prompt = $prompt.Replace('{{PROJECT_ROOT}}', $resolvedProjectRoot).Replace('{{HUB_CLI_PATH}}', $cliPath)
    if ($Name -eq 'bootstrap') {
        $prompt = $prompt.Replace('{{BOOTSTRAP_WORKFLOW_PATH}}', $promptPath)
    }
    if ($Name -eq 'parallel') {
        $taskContractPath = Join-Path $hubRoot 'templates/TASK_CONTRACT.md'
        $prompt = $prompt.Replace('{{TASK_CONTRACT_PATH}}', $taskContractPath)
    }
}

Write-Output $prompt

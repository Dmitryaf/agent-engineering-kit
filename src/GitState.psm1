function Invoke-AiRulesGitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git @Arguments 2>$null)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "Команда Git завершилась ошибкой: git $($Arguments -join ' ')"
    }
    return @($output)
}

function Get-AiRulesHubGitState {
    param([Parameter(Mandatory = $true)][string]$HubRoot)

    $revisionOutput = @(Invoke-AiRulesGitText -Arguments @('-C', $HubRoot, 'rev-parse', 'HEAD'))
    $statusOutput = @(Invoke-AiRulesGitText -Arguments @('-C', $HubRoot, 'status', '--porcelain'))
    $revision = ([string]$revisionOutput[0]).Trim()
    if ($revision -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'Не удалось определить полный 40-символьный Git SHA текущей revision хаба.'
    }
    $result = [pscustomobject]@{
        Revision = $revision
        Dirty = $statusOutput.Count -gt 0
    }
    $result.PSObject.TypeNames.Insert(0, 'AiRules.GitState')
    return $result
}

function Test-AiRulesGitAncestor {
    param(
        [Parameter(Mandatory = $true)][string]$HubRoot,
        [Parameter(Mandatory = $true)][string]$Ancestor,
        [Parameter(Mandatory = $true)][string]$Descendant
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $HubRoot merge-base --is-ancestor $Ancestor $Descendant 2>$null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -eq 0) {
        return [pscustomobject]@{ Available = $true; IsAncestor = $true; ExitCode = $exitCode }
    }
    if ($exitCode -eq 1) {
        return [pscustomobject]@{ Available = $true; IsAncestor = $false; ExitCode = $exitCode }
    }
    return [pscustomobject]@{ Available = $false; IsAncestor = $false; ExitCode = $exitCode }
}

function Get-AiRulesRevisionRelation {
    param(
        [Parameter(Mandatory = $true)][string]$HubRoot,
        [Parameter(Mandatory = $true)][string]$ProjectRevision,
        [Parameter(Mandatory = $true)][string]$HubRevision
    )

    $relation = 'unavailable'
    $detail = $null
    if ($ProjectRevision -eq $HubRevision) {
        $relation = 'same'
    }
    elseif ($ProjectRevision -notmatch '^[0-9a-fA-F]{40}$' -or $HubRevision -notmatch '^[0-9a-fA-F]{40}$') {
        $detail = 'Одна из revisions не является полным Git SHA.'
    }
    else {
        $projectIsAncestor = Test-AiRulesGitAncestor -HubRoot $HubRoot -Ancestor $ProjectRevision -Descendant $HubRevision
        if (-not $projectIsAncestor.Available) {
            $detail = "Git не смог проверить revision проекта (exit code $($projectIsAncestor.ExitCode))."
        }
        elseif ($projectIsAncestor.IsAncestor) {
            $relation = 'ahead'
        }
        else {
            $hubIsAncestor = Test-AiRulesGitAncestor -HubRoot $HubRoot -Ancestor $HubRevision -Descendant $ProjectRevision
            if (-not $hubIsAncestor.Available) {
                $detail = "Git не смог проверить revision хаба (exit code $($hubIsAncestor.ExitCode))."
            }
            elseif ($hubIsAncestor.IsAncestor) {
                $relation = 'behind'
            }
            else {
                $relation = 'diverged'
            }
        }
    }

    $result = [pscustomobject]@{
        Relation = $relation
        ProjectRevision = $ProjectRevision
        HubRevision = $HubRevision
        Detail = $detail
    }
    $result.PSObject.TypeNames.Insert(0, 'AiRules.RevisionRelation')
    return $result
}

Export-ModuleMember -Function @(
    'Invoke-AiRulesGitText',
    'Get-AiRulesHubGitState',
    'Get-AiRulesRevisionRelation'
)

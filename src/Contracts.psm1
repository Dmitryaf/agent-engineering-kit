function Add-AiRulesTypeName {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$TypeName
    )

    $InputObject.PSObject.TypeNames.Insert(0, $TypeName)
    return $InputObject
}

function New-AiRulesDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('OK', 'WARN', 'ERROR')]
        [string]$Level,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Category = 'general'
    )

    return Add-AiRulesTypeName -TypeName 'AiRules.Diagnostic' -InputObject ([pscustomobject]@{
        Level = $Level
        Category = $Category
        Message = $Message
    })
}

function Get-AiRulesPlanSummary {
    param([Parameter(Mandatory = $true)][object[]]$Entries)

    $summary = [ordered]@{}
    foreach ($action in @('add', 'update', 'unchanged', 'conflict', 'orphan', 'orphan-modified', 'orphan-missing')) {
        $count = @($Entries | Where-Object { $_.Action -eq $action }).Count
        if ($count -gt 0) {
            $summary[$action] = $count
        }
    }
    return $summary
}

function New-AiRulesSyncPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$HubRoot,
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)]$Manifest,
        [AllowNull()][string]$HubRevision,
        [AllowNull()][Nullable[bool]]$HubDirty,
        [AllowNull()][string]$ExpectedRevision,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Topics,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Profiles,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
        $PreviousLock
    )

    $summary = Get-AiRulesPlanSummary -Entries $Entries
    $hasChanges = @($summary.Keys | Where-Object { $_ -ne 'unchanged' }).Count -gt 0
    return Add-AiRulesTypeName -TypeName 'AiRules.SyncPlan' -InputObject ([pscustomobject]@{
        ProjectRoot = $ProjectRoot
        HubRoot = $HubRoot
        Catalog = $Catalog
        Manifest = $Manifest
        HubRevision = $HubRevision
        HubDirty = $HubDirty
        ExpectedRevision = $ExpectedRevision
        Topics = @($Topics)
        Profiles = @($Profiles)
        Entries = @($Entries)
        Summary = $summary
        IsUnchanged = -not $hasChanges
        HasConflicts = $summary.Contains('conflict')
        PreviousLock = $PreviousLock
    })
}

function New-AiRulesProjectState {
    param([Parameter(Mandatory = $true)][hashtable]$Properties)

    return Add-AiRulesTypeName -TypeName 'AiRules.ProjectState' -InputObject ([pscustomobject]$Properties)
}

Export-ModuleMember -Function @(
    'New-AiRulesDiagnostic',
    'Get-AiRulesPlanSummary',
    'New-AiRulesSyncPlan',
    'New-AiRulesProjectState'
)

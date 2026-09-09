$moduleRoot = $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'Catalog.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'Contracts.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'GitState.psm1') -ErrorAction Stop
Import-Module (Join-Path $moduleRoot 'SyncPlan.psm1') -ErrorAction Stop

function Read-AiRulesJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw ("Некорректный JSON в {0}: {1}" -f $Path, $_.Exception.Message)
    }
}

function Get-AiRulesProjectState {
    param(
        [Parameter(Mandatory = $true)][string]$HubRoot,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )

    $hubRootFull = (Resolve-Path -LiteralPath $HubRoot).Path
    $projectRootFull = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $localRulesRoot = Join-Path $projectRootFull '.ai-rules'
    $paths = [pscustomobject]@{
        Manifest = Join-Path $localRulesRoot 'manifest.json'
        Lock = Join-Path $localRulesRoot 'lock.json'
        ManagedRoot = Join-Path $localRulesRoot 'upstream'
        Agents = Join-Path $projectRootFull 'AGENTS.md'
        Ruleset = Join-Path $localRulesRoot 'RULESET.md'
        ProjectRules = Join-Path $localRulesRoot 'PROJECT_RULES.md'
    }
    $found = [pscustomobject]@{
        Manifest = Test-Path -LiteralPath $paths.Manifest -PathType Leaf
        Lock = Test-Path -LiteralPath $paths.Lock -PathType Leaf
        ManagedRoot = Test-Path -LiteralPath $paths.ManagedRoot -PathType Container
        Agents = Test-Path -LiteralPath $paths.Agents -PathType Leaf
        Ruleset = Test-Path -LiteralPath $paths.Ruleset -PathType Leaf
        ProjectRules = Test-Path -LiteralPath $paths.ProjectRules -PathType Leaf
    }

    $catalog = Get-AiRulesCatalog -HubRoot $hubRootFull
    $hubState = Get-AiRulesHubGitState -HubRoot $hubRootFull
    $manifest = $null
    $manifestError = $null
    $manifestContractValid = $false
    $selectionError = $null
    $selectionsValid = $false
    $profiles = @()
    $directTopics = @()
    $effectiveTopics = @()
    $manifestRevision = $null
    $pinned = $false

    if ($found.Manifest) {
        try {
            $manifest = Read-AiRulesJsonFile -Path $paths.Manifest
            $manifestContractValid = (
                $manifest.schemaVersion -eq '0.2' -and
                $null -ne $manifest.PSObject.Properties['source'] -and
                $null -ne $manifest.PSObject.Properties['profiles'] -and
                $null -ne $manifest.PSObject.Properties['topics'] -and
                $null -ne $manifest.source -and
                $null -ne $manifest.source.PSObject.Properties['revision'] -and
                [string]$manifest.source.repository -eq 'ai-rules-hub'
            )
            if ($null -ne $manifest.PSObject.Properties['profiles']) {
                $profiles = @($manifest.profiles | ForEach-Object { [string]$_ })
            }
            if ($null -ne $manifest.PSObject.Properties['topics']) {
                $directTopics = @($manifest.topics | ForEach-Object { [string]$_ })
            }
            $effectiveTopics = @(Get-AiRulesEffectiveTopics -Catalog $catalog -SelectedProfiles $profiles -SelectedTopics $directTopics)
            if ($manifestContractValid) {
                try {
                    Assert-AiRulesSelections -Catalog $catalog -SelectedProfiles $profiles -SelectedTopics $directTopics
                    $selectionsValid = $true
                }
                catch {
                    $selectionError = $_.Exception.Message
                }
                if ($null -ne $manifest.source.revision) {
                    $manifestRevision = [string]$manifest.source.revision
                }
                $pinned = -not [string]::IsNullOrWhiteSpace($manifestRevision) -and $manifestRevision -match '^[0-9a-fA-F]{40}$'
            }
        }
        catch {
            $manifestError = $_.Exception.Message
        }
    }

    $lock = $null
    $lockError = $null
    $lockContractValid = $false
    $lockRevision = $null
    if ($found.Lock) {
        try {
            $lock = Read-AiRulesJsonFile -Path $paths.Lock
            $lockContractValid = (
                $lock.schemaVersion -eq '0.2' -and
                [string]$lock.manifest -eq '.ai-rules/manifest.json' -and
                [string]$lock.managedRoot -eq '.ai-rules/upstream' -and
                $null -ne $lock.PSObject.Properties['source'] -and
                $null -ne $lock.PSObject.Properties['files']
            )
            if ($null -ne $lock.source -and $null -ne $lock.source.revision) {
                $lockRevision = [string]$lock.source.revision
            }
        }
        catch {
            $lockError = $_.Exception.Message
        }
    }

    $revisionRelation = $null
    if ($pinned) {
        $revisionRelation = Get-AiRulesRevisionRelation -HubRoot $hubRootFull -ProjectRevision $manifestRevision -HubRevision $hubState.Revision
    }

    $syncPlan = $null
    $syncPlanError = $null
    $canBuildPlan = $manifestContractValid -and $selectionsValid -and (-not $pinned -or $revisionRelation.Relation -eq 'same')
    if ($canBuildPlan) {
        try {
            $syncPlan = Get-AiRulesSyncPlan -HubRoot $hubRootFull -ProjectRoot $projectRootFull
        }
        catch {
            $syncPlanError = $_.Exception.Message
        }
    }

    return New-AiRulesProjectState -Properties @{
        ProjectRoot = $projectRootFull
        ProjectName = Split-Path -Leaf $projectRootFull.TrimEnd([char[]]@('\', '/'))
        HubRoot = $hubRootFull
        Catalog = $catalog
        HubState = $hubState
        Paths = $paths
        Found = $found
        Manifest = $manifest
        ManifestError = $manifestError
        ManifestContractValid = $manifestContractValid
        SelectionError = $selectionError
        SelectionsValid = $selectionsValid
        ManifestRevision = $manifestRevision
        Pinned = $pinned
        Profiles = @($profiles)
        DirectTopics = @($directTopics)
        EffectiveTopics = @($effectiveTopics)
        Lock = $lock
        LockError = $lockError
        LockContractValid = $lockContractValid
        LockRevision = $lockRevision
        RevisionRelation = $revisionRelation
        SyncPlan = $syncPlan
        SyncPlanError = $syncPlanError
    }
}

Export-ModuleMember -Function 'Get-AiRulesProjectState'

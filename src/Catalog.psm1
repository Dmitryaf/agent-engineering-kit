function Get-AiRulesCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$HubRoot,
        [string]$Revision
    )

    $catalogPath = Join-Path $HubRoot 'sync/catalog.json'
    if (-not [string]::IsNullOrWhiteSpace($Revision) -and $Revision -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'Версия каталога должна быть полным 40-символьным Git SHA.'
    }
    try {
        if ([string]::IsNullOrWhiteSpace($Revision)) {
            $content = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8
        }
        else {
            Import-Module (Join-Path $PSScriptRoot 'GitState.psm1') -ErrorAction Stop
            $content = @(Invoke-AiRulesGitText -Arguments @('-C', $HubRoot, 'show', ($Revision + ':sync/catalog.json'))) -join "`n"
        }
        $catalog = $content | ConvertFrom-Json
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($Revision)) {
            throw ("Каталог sync/catalog.json версии {0} недоступен или некорректен: {1}" -f $Revision, $_.Exception.Message)
        }
        throw ("Некорректный JSON в {0}: {1}" -f $catalogPath, $_.Exception.Message)
    }
    if ($catalog.schemaVersion -ne '0.1') {
        throw "Неподдерживаемая версия catalog schemaVersion: $($catalog.schemaVersion)"
    }
    return $catalog
}

function ConvertTo-AiRulesNameList {
    param([string[]]$Values)

    return @(
        foreach ($value in @($Values)) {
            foreach ($part in ([string]$value -split ',')) {
                $name = $part.Trim()
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $name
                }
            }
        }
    )
}

function Assert-AiRulesSelections {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [string[]]$SelectedProfiles,
        [string[]]$SelectedTopics
    )

    $availableProfiles = @($Catalog.profiles.PSObject.Properties.Name)
    $availableTopics = @($Catalog.topics.PSObject.Properties.Name)
    foreach ($profile in @($SelectedProfiles)) {
        if ([string]::IsNullOrWhiteSpace([string]$profile)) {
            continue
        }
        if ($profile -notin $availableProfiles) {
            throw "Неизвестный профиль '$profile'. Доступны: $($availableProfiles -join ', ')"
        }
    }
    foreach ($topic in @($SelectedTopics)) {
        if ([string]::IsNullOrWhiteSpace([string]$topic)) {
            continue
        }
        if ($topic -notin $availableTopics) {
            throw "Неизвестная тема '$topic'. Доступны: $($availableTopics -join ', ')"
        }
    }
}

function Get-AiRulesEffectiveTopics {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [string[]]$SelectedProfiles,
        [string[]]$SelectedTopics
    )

    $selected = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($topic in @($SelectedTopics)) {
        if ($null -ne $Catalog.topics.PSObject.Properties[[string]$topic]) {
            [void]$selected.Add([string]$topic)
        }
    }
    foreach ($profileName in @($SelectedProfiles)) {
        $profileProperty = $Catalog.profiles.PSObject.Properties[[string]$profileName]
        if ($null -eq $profileProperty) {
            continue
        }
        foreach ($topic in @($profileProperty.Value.topics)) {
            [void]$selected.Add([string]$topic)
        }
    }

    return @(
        foreach ($topicProperty in $Catalog.topics.PSObject.Properties) {
            if ($selected.Contains($topicProperty.Name)) {
                $topicProperty.Name
            }
        }
    )
}

Export-ModuleMember -Function @(
    'Get-AiRulesCatalog',
    'ConvertTo-AiRulesNameList',
    'Assert-AiRulesSelections',
    'Get-AiRulesEffectiveTopics'
)

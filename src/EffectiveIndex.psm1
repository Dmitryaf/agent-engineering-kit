function Get-AiRulesRequiredMetadata {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $value = $Object.PSObject.Properties[$Property]
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value.Value)) {
        throw "$Label должен содержать непустое поле $Property."
    }
    return [string]$value.Value
}

function New-AiRulesIndexEntryLines {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)]$Metadata,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$SelectedBy
    )

    $kind = Get-AiRulesRequiredMetadata -Object $Metadata -Property 'kind' -Label $Id
    $description = Get-AiRulesRequiredMetadata -Object $Metadata -Property 'description' -Label $Id
    $readWhen = Get-AiRulesRequiredMetadata -Object $Metadata -Property 'readWhen' -Label $Id
    "### ``$Id``"
    ''
    "- Вид: ``$kind``"
    "- Путь: ``$Path``"
    "- Назначение: $description"
    "- Читать: $readWhen"
    if (-not [string]::IsNullOrWhiteSpace($SelectedBy)) {
        "- Выбрано через: $SelectedBy"
    }
    ''
}

function New-AiRulesEffectiveIndexContent {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)]$Manifest
    )

    $selectedProfiles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $directTopics = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($profileName in @($Manifest.profiles)) { [void]$selectedProfiles.Add([string]$profileName) }
    foreach ($topicName in @($Manifest.topics)) { [void]$directTopics.Add([string]$topicName) }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Индекс подключённых правил')
    $lines.Add('')
    $lines.Add('<!-- Сгенерировано AI Rules Hub из sync/catalog.json и manifest. Не редактировать вручную. -->')
    $lines.Add('')
    $lines.Add('Используй этот файл как карту чтения. Источниками истины для состава и версии остаются `.ai-rules/manifest.json` и `.ai-rules/lock.json`.')
    $lines.Add('')
    $lines.Add('## Обязательная основа')
    $lines.Add('')
    foreach ($coreFile in @($Catalog.core)) {
        $metadataProperty = $Catalog.coreMetadata.PSObject.Properties[[string]$coreFile]
        if ($null -eq $metadataProperty) { throw "В catalog отсутствует coreMetadata для $coreFile." }
        $path = if ([string]$coreFile -eq 'rules/CORE.md') { 'CORE.md' } else { [string]$coreFile }
        foreach ($line in @(New-AiRulesIndexEntryLines -Id 'core' -Metadata $metadataProperty.Value -Path $path)) { $lines.Add($line) }
    }

    $lines.Add('## Выбранные профили')
    $lines.Add('')
    $profileCount = 0
    foreach ($profileProperty in $Catalog.profiles.PSObject.Properties) {
        if (-not $selectedProfiles.Contains($profileProperty.Name)) { continue }
        foreach ($line in @(New-AiRulesIndexEntryLines -Id $profileProperty.Name -Metadata $profileProperty.Value -Path ([string]$profileProperty.Value.file))) { $lines.Add($line) }
        $profileCount++
    }
    if ($profileCount -eq 0) {
        $lines.Add('- Нет.')
        $lines.Add('')
    }

    $lines.Add('## Эффективные темы и процессы')
    $lines.Add('')
    $topicCount = 0
    foreach ($topicProperty in $Catalog.topics.PSObject.Properties) {
        $selectedBy = [System.Collections.Generic.List[string]]::new()
        if ($directTopics.Contains($topicProperty.Name)) { $selectedBy.Add('`manifest.topics`') }
        foreach ($profileProperty in $Catalog.profiles.PSObject.Properties) {
            if (-not $selectedProfiles.Contains($profileProperty.Name)) { continue }
            if ($topicProperty.Name -in @($profileProperty.Value.topics)) {
                $selectedBy.Add("профиль ``$($profileProperty.Name)``")
            }
        }
        if ($selectedBy.Count -eq 0) { continue }

        foreach ($line in @(New-AiRulesIndexEntryLines -Id $topicProperty.Name -Metadata $topicProperty.Value -Path ([string]$topicProperty.Value.file) -SelectedBy ($selectedBy -join ', '))) { $lines.Add($line) }
        $topicCount++
    }
    if ($topicCount -eq 0) {
        $lines.Add('- Нет.')
        $lines.Add('')
    }

    return ($lines -join [string][char]10).TrimEnd() + [string][char]10
}

Export-ModuleMember -Function 'New-AiRulesEffectiveIndexContent'

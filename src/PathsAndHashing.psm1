function Assert-AiRulesPathHasNoReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$BaseFullPath,
        [Parameter(Mandatory = $true)][string]$CandidateFullPath,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$ChildPath
    )

    if ($CandidateFullPath -eq $BaseFullPath) {
        return
    }

    $relativePath = $CandidateFullPath.Substring($BaseFullPath.Length).TrimStart([char[]]@('\', '/'))
    $currentPath = $BaseFullPath
    foreach ($segment in @($relativePath -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }
        if (-not [System.IO.Directory]::Exists($currentPath)) {
            return
        }

        $entry = @(
            Get-ChildItem -LiteralPath $currentPath -Force -ErrorAction Stop |
                Where-Object { $_.Name -eq $segment } |
                Select-Object -First 1
        )
        if ($entry.Count -eq 0) {
            return
        }
        if (($entry[0].Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label проходит через reparse point и отклонён: $ChildPath"
        }

        $currentPath = $entry[0].FullName
    }
}

function Get-AiRulesSafePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ChildPath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([System.IO.Path]::IsPathRooted($ChildPath)) {
        throw "$Label должен быть относительным путём: $ChildPath"
    }

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([char[]]@('\', '/'))
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $baseFullPath $ChildPath))
    $prefix = $baseFullPath + [System.IO.Path]::DirectorySeparatorChar
    if (
        $candidate -ne $baseFullPath -and
        -not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "$Label выходит за пределы разрешённого корня: $ChildPath"
    }

    Assert-AiRulesPathHasNoReparsePoint -BaseFullPath $baseFullPath -CandidateFullPath $candidate -Label $Label -ChildPath $ChildPath
    return $candidate
}

function Get-AiRulesSha256Text {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    $crlf = [string][char]13 + [string][char]10
    $lf = [string][char]10
    $cr = [string][char]13
    $normalizedContent = $Content.Replace($crlf, $lf).Replace($cr, $lf)
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8WithoutBom.GetBytes($normalizedContent)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($bytes)
        return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-AiRulesSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $textExtensions = @('.md', '.json', '.yml', '.yaml', '.txt')
    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -in $textExtensions) {
        return Get-AiRulesSha256Text -Content ([System.IO.File]::ReadAllText($Path))
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-AiRulesJsonValue {
    param(
        $Value,
        [int]$IndentLevel = 0
    )

    if ($null -eq $Value) {
        return 'null'
    }

    $properties = $null
    if ($Value -is [System.Collections.IDictionary]) {
        $properties = @($Value.Keys | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_; Value = $Value[$_] }
        })
    }
    elseif ($Value.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
        $properties = @($Value.PSObject.Properties | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Value = $_.Value }
        })
    }

    if ($null -ne $properties) {
        if ($properties.Count -eq 0) {
            return '{}'
        }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('{')
        for ($index = 0; $index -lt $properties.Count; $index++) {
            $property = $properties[$index]
            $name = $property.Name | ConvertTo-Json -Compress
            $formattedValue = ConvertTo-AiRulesJsonValue -Value $property.Value -IndentLevel ($IndentLevel + 1)
            $valueLines = @($formattedValue -split '\r?\n')
            $suffix = if ($index -lt $properties.Count - 1) { ',' } else { '' }
            $firstLineSuffix = if ($valueLines.Count -eq 1) { $suffix } else { '' }
            $lines.Add(('  ' * ($IndentLevel + 1)) + $name + ': ' + $valueLines[0] + $firstLineSuffix)
            for ($lineIndex = 1; $lineIndex -lt $valueLines.Count; $lineIndex++) {
                $lineSuffix = if ($lineIndex -eq $valueLines.Count - 1) { $suffix } else { '' }
                $lines.Add($valueLines[$lineIndex] + $lineSuffix)
            }
        }
        $lines.Add(('  ' * $IndentLevel) + '}')
        return ($lines -join [string][char]10)
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value)
        if ($items.Count -eq 0) {
            return '[]'
        }
        $primitiveItems = @($items | Where-Object {
            $_ -isnot [System.Collections.IDictionary] -and
            ($null -eq $_ -or $_.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') -and
            -not ($_ -is [System.Collections.IEnumerable] -and $_ -isnot [string])
        })
        if ($primitiveItems.Count -eq $items.Count) {
            $tokens = @($items | ForEach-Object { ConvertTo-AiRulesJsonValue -Value $_ })
            $compact = '[' + ($tokens -join ', ') + ']'
            if ((('  ' * $IndentLevel) + $compact).Length -le 80) {
                return $compact
            }
        }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('[')
        for ($index = 0; $index -lt $items.Count; $index++) {
            $formattedItem = ConvertTo-AiRulesJsonValue -Value $items[$index] -IndentLevel ($IndentLevel + 1)
            $itemLines = @($formattedItem -split '\r?\n')
            for ($lineIndex = 0; $lineIndex -lt $itemLines.Count; $lineIndex++) {
                $line = if ($lineIndex -eq 0) { ('  ' * ($IndentLevel + 1)) + $itemLines[$lineIndex] } else { $itemLines[$lineIndex] }
                if ($lineIndex -eq $itemLines.Count - 1 -and $index -lt $items.Count - 1) {
                    $line += ','
                }
                $lines.Add($line)
            }
        }
        $lines.Add(('  ' * $IndentLevel) + ']')
        return ($lines -join [string][char]10)
    }

    return ($Value | ConvertTo-Json -Compress)
}

function ConvertTo-AiRulesJson {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [int]$Depth = 10
    )

    return ConvertTo-AiRulesJsonValue -Value $InputObject
}

Export-ModuleMember -Function @(
    'Get-AiRulesSafePath',
    'Get-AiRulesSha256',
    'Get-AiRulesSha256Text',
    'ConvertTo-AiRulesJson'
)

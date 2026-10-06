[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hubRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$powerShellExe = (Get-Process -Id $PID).Path
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
$tempRoot = Join-Path $tempBase ('kit-historical-catalog-' + [Guid]::NewGuid().ToString('N'))
$assertions = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertions++
}

function Invoke-FixtureGit {
    param([string[]]$Arguments)
    $output = @(& git -C $fixtureHub @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $($Arguments -join ' ')" }
    return $output
}

function Invoke-FixtureScript {
    param([string]$Name, [string[]]$Arguments)
    $output = & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureHub "scripts/$Name") @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fixture script failed: $Name $output" }
}

function Get-ProjectSnapshot {
    return (@(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($projectRoot.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}

try {
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    $fixtureHub = Join-Path $tempRoot 'hub'
    $projectRoot = Join-Path $tempRoot 'project'
    [System.IO.Directory]::CreateDirectory($fixtureHub) | Out-Null
    [System.IO.Directory]::CreateDirectory($projectRoot) | Out-Null
    [void](Invoke-FixtureGit @('init', '--quiet'))
    [void](Invoke-FixtureGit @('config', 'core.autocrlf', 'false'))
    [System.IO.File]::WriteAllText((Join-Path $fixtureHub 'README.md'), '# Fixture before the catalog', $utf8)
    [void](Invoke-FixtureGit @('add', '--all'))
    [void](Invoke-FixtureGit @('-c', 'user.name=Kit Tests', '-c', 'user.email=tests@example.invalid', 'commit', '--quiet', '-m', 'test(sync): create revision without catalog'))
    $withoutCatalogRevision = [string](@(Invoke-FixtureGit @('rev-parse', 'HEAD'))[0])

    foreach ($directory in @('rules', 'profiles', 'workflows', 'templates', 'scripts', 'src', 'sync')) {
        Copy-Item -LiteralPath (Join-Path $hubRoot $directory) -Destination $fixtureHub -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $hubRoot 'ai-rules.ps1') -Destination $fixtureHub
    $catalogPath = Join-Path $fixtureHub 'sync/catalog.json'
    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $catalog.profiles.'standard-product'.topics = @('quality')
    $profileDescription = [string]$catalog.profiles.'standard-product'.description
    [System.IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 10), $utf8)
    [void](Invoke-FixtureGit @('add', '--all'))
    [void](Invoke-FixtureGit @('-c', 'user.name=Kit Tests', '-c', 'user.email=tests@example.invalid', 'commit', '--quiet', '-m', 'test(sync): create installed profile composition'))
    $installedRevision = [string](@(Invoke-FixtureGit @('rev-parse', 'HEAD'))[0])

    Invoke-FixtureScript -Name 'init-project-sync.ps1' -Arguments @('-ProjectRoot', $projectRoot, '-Profiles', 'standard-product', '-SeedProjectFiles')
    $manifestPath = Join-Path $projectRoot '.ai-rules/manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.source.revision = $installedRevision
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), $utf8)
    Invoke-FixtureScript -Name 'sync-rules.ps1' -Arguments @('-ProjectRoot', $projectRoot, '-Mode', 'Apply')

    Import-Module (Join-Path $hubRoot 'src/ProjectState.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $hubRoot 'src/Diagnostics.psm1') -Force -ErrorAction Stop
    $initial = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    Assert-True ((Get-AiRulesStatusAssessment -ProjectState $initial).State -eq 'synchronized') 'installed revision must start synchronized'
    $snapshot = Get-ProjectSnapshot

    $catalog.profiles.'standard-product'.topics = @('quality', 'implementation')
    [System.IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 10), $utf8)
    $state = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    Assert-True ((Get-AiRulesStatusAssessment -ProjectState $state).State -eq 'synchronized' -and ($state.EffectiveTopics -join ',') -eq 'quality') 'unapplied dirty catalog at the same SHA must not change clean installed composition'
    Assert-True ((Get-ProjectSnapshot) -eq $snapshot) 'same-SHA dirty-catalog diagnostics must remain read-only'
    $doctorOutput = & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureHub 'ai-rules.ps1') doctor -ProjectRoot $projectRoot 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0 -and $doctorOutput -notmatch '\[ERROR\]') 'doctor must validate the clean pinned snapshot independently of dirty same-SHA sources'
    [System.IO.File]::WriteAllText($catalogPath, '{ invalid dirty catalog', $utf8)
    $state = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    Assert-True ((Get-AiRulesStatusAssessment -ProjectState $state).State -eq 'synchronized' -and ($state.EffectiveTopics -join ',') -eq 'quality') 'invalid dirty current catalog must not hide the readable pinned catalog'
    [System.IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 10), $utf8)
    $dirtyProjectRoot = Join-Path $tempRoot 'dirty-project'
    Copy-Item -LiteralPath $projectRoot -Destination $dirtyProjectRoot -Recurse
    Invoke-FixtureScript -Name 'sync-rules.ps1' -Arguments @('-ProjectRoot', $dirtyProjectRoot, '-Mode', 'Apply', '-AllowDirtySource')
    $dirtyState = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $dirtyProjectRoot
    Assert-True ($dirtyState.Lock.source.dirty -eq $true -and (Get-AiRulesStatusAssessment -ProjectState $dirtyState).State -eq 'synchronized') 'same-SHA dirty installation must retain working-tree composition semantics'
    Assert-True (($dirtyState.EffectiveTopics -join ',') -eq 'implementation,quality') 'dirty installation must use the actual local profile expansion'
    [void](Invoke-FixtureGit @('add', 'sync/catalog.json'))
    [void](Invoke-FixtureGit @('-c', 'user.name=Kit Tests', '-c', 'user.email=tests@example.invalid', 'commit', '--quiet', '-m', 'test(sync): expand current profile composition'))
    $state = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    $assessment = Get-AiRulesStatusAssessment -ProjectState $state
    Assert-True ($assessment.State -eq 'update-available') "profile expansion must preserve the historical snapshot; got $($assessment.State): $($assessment.Diagnostics -join '; ')"
    Assert-True (($state.EffectiveTopics -join ',') -eq 'quality') 'effective topics must come from the installed revision'
    Assert-True ([string]$state.Catalog.profiles.'standard-product'.description -eq $profileDescription) 'historical catalog must preserve UTF-8 metadata'
    Assert-True ((Get-ProjectSnapshot) -eq $snapshot) 'historical diagnostics must not modify project files'
    $doctorOutput = & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureHub 'ai-rules.ps1') doctor -ProjectRoot $projectRoot 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0 -and $doctorOutput -notmatch '\[ERROR\]') 'CLI doctor must accept the historical snapshot after profile expansion'
    $dirtyState = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $dirtyProjectRoot
    $dirtyAssessment = Get-AiRulesStatusAssessment -ProjectState $dirtyState
    Assert-True ($dirtyAssessment.State -eq 'checkout-mismatch' -and $dirtyState.CatalogError -match 'dirty') 'historical dirty composition must remain unknown rather than be replaced by the clean base catalog'

    # Current catalog may retire an ID that remains valid in the pinned revision.
    $catalog.profiles.PSObject.Properties.Remove('standard-product')
    [System.IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 10), $utf8)
    [void](Invoke-FixtureGit @('add', 'sync/catalog.json'))
    [void](Invoke-FixtureGit @('-c', 'user.name=Kit Tests', '-c', 'user.email=tests@example.invalid', 'commit', '--quiet', '-m', 'test(sync): retire current profile'))
    $state = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    Assert-True ($state.SelectionsValid -and (Get-AiRulesStatusAssessment -ProjectState $state).State -eq 'update-available') 'retired current IDs must remain valid for the historical installation'

    # A readable Git revision without its catalog is unknown, not current composition.
    $manifest.source.revision = $withoutCatalogRevision
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), $utf8)
    $lockPath = Join-Path $projectRoot '.ai-rules/lock.json'
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lock.source.revision = $withoutCatalogRevision
    [System.IO.File]::WriteAllText($lockPath, ($lock | ConvertTo-Json -Depth 10), $utf8)
    $snapshot = Get-ProjectSnapshot
    $state = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    $assessment = Get-AiRulesStatusAssessment -ProjectState $state
    Assert-True ($null -eq $state.Catalog -and -not [string]::IsNullOrWhiteSpace($state.CatalogError)) 'missing historical catalog must be reported without current-catalog fallback'
    Assert-True ($assessment.State -eq 'checkout-mismatch' -and ($assessment.Diagnostics -join '; ') -match 'catalog') 'missing historical catalog must have an explicit unknown-composition diagnosis'
    Assert-True (@($assessment.Diagnostics).Count -eq 1) 'unknown composition must not add a topic mismatch'
    Assert-True ((Get-ProjectSnapshot) -eq $snapshot) 'missing-catalog diagnostics must remain read-only'
    $doctorOutput = & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureHub 'ai-rules.ps1') doctor -ProjectRoot $projectRoot 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0 -and $doctorOutput -match '\[WARN\].*catalog' -and $doctorOutput -notmatch '\[ERROR\]') 'CLI doctor must explicitly warn about unavailable historical composition'

    $manifest.source.revision = 'f' * 40
    $lock.source.revision = $manifest.source.revision
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), $utf8)
    [System.IO.File]::WriteAllText($lockPath, ($lock | ConvertTo-Json -Depth 10), $utf8)
    $snapshot = Get-ProjectSnapshot
    $state = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    Assert-True ((Get-AiRulesStatusAssessment -ProjectState $state).State -eq 'checkout-mismatch' -and $null -eq $state.Catalog) 'unavailable Git revision must not fall back to the current catalog'
    Assert-True ((Get-ProjectSnapshot) -eq $snapshot) 'unavailable-revision diagnostics must remain read-only'
    [System.IO.File]::AppendAllText((Join-Path $projectRoot '.ai-rules/upstream/CORE.md'), "`nmanual edit", $utf8)
    $state = Get-AiRulesProjectState -HubRoot $fixtureHub -ProjectRoot $projectRoot
    Assert-True ((Get-AiRulesStatusAssessment -ProjectState $state).State -eq 'inconsistent') 'unknown catalog must not suppress installed-file integrity failures'

    Write-Host "Historical catalog tests passed: $assertions assertions." -ForegroundColor Green
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'kit-historical-catalog-*') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}

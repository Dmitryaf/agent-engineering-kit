$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/PathsAndHashing.psm1'
Import-Module $modulePath -ErrorAction Stop

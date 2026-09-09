[CmdletBinding()]
param()

$runner = Join-Path $PSScriptRoot 'run.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner
exit $LASTEXITCODE

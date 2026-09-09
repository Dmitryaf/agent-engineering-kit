[CmdletBinding()]
param()

$runner = Join-Path $PSScriptRoot 'run.ps1'
$powershellExe = (Get-Process -Id $PID -ErrorAction Stop).Path
& $powershellExe -NoProfile -ExecutionPolicy Bypass -File $runner
exit $LASTEXITCODE

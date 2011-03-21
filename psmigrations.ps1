Remove-Module psmigrations -ErrorAction 'SilentlyContinue'
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.path
Import-Module (Join-Path $scriptPath psmigrations.psm1)
$scriptPath = (Split-Path -Parent $MyInvocation.MyCommand.path)
. (Join-Path ([IO.Path]::GetDirectoryName($scriptPath)) psmigrations.ps1)

$CONN_STR = "SERVER=.\SQLEXPRESS;DATABASE=psmigrations;INTEGRATED SECURITY=SSPI;"
$DB_PROVIDER = "System.Data.SqlClient"
$SCRIPT_PATH = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.path) "migrate"

Write-Host "Get-DbStatus"
Write-Host *****************************
Get-DbStatus -ConnectionString $CONN_STR -Provider $DB_PROVIDER -ScriptPath $SCRIPT_PATH
Write-Host *****************************`n


Write-Host "Invoke-DbMigrate"
Write-Host *****************************
Invoke-DbMigrate -ConnectionString $CONN_STR -Provider $DB_PROVIDER -ScriptPath $SCRIPT_PATH
Write-Host *****************************
﻿$scriptPath = (Split-Path -Parent $MyInvocation.MyCommand.path)
. (Join-Path ([IO.Path]::GetDirectoryName($scriptPath)) psmigrations.ps1)

$CONN_STR = "SERVER=.\SQLEXPRESS;DATABASE=psmigrations;INTEGRATED SECURITY=SSPI;"
$DB_PROVIDER = "System.Data.SqlClient"
$SCRIPT_PATH = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.path) "migrate"

#Install-PSMigrations -ConnectionString $CONN_STR -Provider $DB_PROVIDER


Write-Host "Get-DbStatus"
Write-Host *****************************
Get-DbStatus -ConnectionString $CONN_STR -Provider $DB_PROVIDER -ScriptPath $SCRIPT_PATH
Write-Host *****************************`n

<#
function PrintIt {
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1, ValueFromPipelineByPropertyName=1)]
		[IO.FileInfo]$File
	)
	
	begin {
		$regex = "(?ismx)^\s*BEGIN_SETUP:\s*$  (?<SETUP>.*)  ^\s*END_SETUP:\s*$"
		#Write-Host "File name: $script"
		$script = [System.IO.File]::ReadAllText($File.FullName)
	}
	process {		
		Write-Host $File.FullName
		if ($script -match $regex) {
			$matches['SETUP']
		}
		#else {
		#	# if there isn't a setup, assume the entire script is the setup
		#	$script
		#}
	}
	end {
	}
}
#>

#Get-DbMigrationScript -Path $SCRIPT_PATH `
#	| Invoke-SqlScript -Connection $CONN_STR -StartLabel "BEGIN_SETUP" -EndLabel "END_SETUP"



	<#
Get-ChildItem $SCRIPT_PATH `
	| Where-Object { $_ -is [IO.FileInfo] -and $_.Name -match "^(?<VERSION>\d+)[_\-](?<DESC>.*)\.sql" } `
	| Select-Object @{Name = "Version"; Expression = {[long]$matches['VERSION']}}, `
	                @{Name = "Name";    Expression = {$matches['DESC']}}, `
	                @{Name = "File";    Expression = {$_}} `
	| Sort-Object Version `
	| PrintIt
	#| % { [System.IO.File]::ReadAllText($_.File.FullName) }
#>


Write-Host "Invoke-DbMigrate"
Write-Host *****************************
Invoke-DbMigrate -ConnectionString $CONN_STR -Provider $DB_PROVIDER -ScriptPath $SCRIPT_PATH -Version 0
Write-Host *****************************

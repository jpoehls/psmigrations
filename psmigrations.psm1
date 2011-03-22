# GOALS
# * Nuget package that adds module to console in VS
# * Read connection strings from default project (nuget)'s config file
# * Use ScriptSplitter to support sql GO keywords
# * Some 'check' function that will ensure all migration scripts have been run on the db
#   and that the script hashes match what's on disk. warn if any scripts havent' been run
#   or if some scripts are missing or have been changed.
# * support WhatIf and Confirm using "ShouldProcess()"
# * support one-time scripts (sprocs/funcs/views) like roundhouse does

$DEFAULT_SCRIPT_PATH   = ".\migrate"
$DEFAULT_PROVIDER_NAME = "System.Data.SqlClient"

#-- Private Module Functions
function Get-DbConnection {
<#
.SYNOPSIS
Uses a [DbProviderFactory] to create and return a [DbConnection] object.

.PARAMETER ConnectionString
The connection string to use for the connection.

.PARAMETER Provider
The ADO.NET DbProvider name to use when creating the connection.
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$ConnectionString,
		[Parameter(Position=0, Mandatory=1)]
		[string]$Provider
	)
	$factory = [System.Data.Common.DbProviderFactories]::GetFactory($Provider)
	$connection = $factory.CreateConnection()
	$connection.ConnectionString = $ConnectionString
	$connection
}

function Get-DbMigrationScriptVersion {
<#
.SYNOPSIS
Gets the latest migration script version number
that exists in the given directory path.

.PARAMETER Path
The directory path where to look for the migration scripts.

.LINK
Get-DbMigrationScript
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$Path
	)
	
	# get a list of all the migration scripts
	$scripts = Get-DbMigrationScript -Path $Path
	
	# find and return the latest version number	
	$newestScript = $scripts `
					| Sort-Object Version -Descending `
					| Select-Object -First 1

	if ($newestScript) {
		$newestScript.Version
	} else {
		return 0
	}
}

function Get-DbMigrationScript {
<#
.SYNOPSIS
Gets all of the migration scripts in the given
directory path.

.PARAMETER Path
The directory path where to look for the migration scripts.

.PARAMETER Version
The specific version number to return the script for.
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$Path,
		[Parameter(Position=1, Mandatory=0)]
		[long]$Version = 0
	)
	
	Get-ChildItem $Path `
		| Where-Object { $_ -is [IO.FileInfo] -and $_.Name -match "^(?<VERSION>\d+)[_\-](?<DESC>.*)\.sql" } `
		| Select-Object @{Name = "Version"; Expression = {[long]$matches['VERSION']}}, `
		                @{Name = "Name";    Expression = {$matches['DESC']}}, `
		                @{Name = "File";    Expression = {$_}} `
		| Where-Object { $Version -eq 0 -or $_.Version -eq $Version } `
		| Sort-Object Version
}

function Install-PSMigrations {
<#
.SYNOPSIS
Creates the [psmigrations] table if it doesn't already exist.

.LINK
Invoke-SqlScript
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$ConnectionString,
		[Parameter(Position=1, Mandatory=1)]
		[string]$Provider
	)
	
	$sql = "
IF (NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'psmigrations'))
BEGIN
	CREATE TABLE [dbo].[psmigrations] ([id] INT IDENTITY(1,1) PRIMARY KEY, [version] BIGINT, [script_name] VARCHAR(255))
END
"

	Invoke-SqlScript -ConnectionString $ConnectionString -Provider $Provider -Script $sql
}

function Get-DbVersion {
<#
.SYNOPSIS
Gets the version number of the latest migration script
run for the given database.

.LINK
Get-DbConnection
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$ConnectionString,
		[Parameter(Position=1, Mandatory=1)]
		[string]$Provider
	)
	
	$connection = Get-DbConnection -ConnectionString $ConnectionString -Provider $Provider
	[Data.Common.DbCommand]$command | Out-Null
	
	try {
		$connection.Open()
		$command = $connection.CreateCommand()
		$command.CommandText = "SELECT MAX(version) FROM [dbo].[psmigrations]"
		$dbVersion = $command.ExecuteScalar()
	
		if ($dbVersion -eq [DBNull]::Value) {
			0 # default return value
		}
		else {
			[long]$dbVersion
		}
	} finally {
		if ($command) { $command.Dispose() }
		if ($connection) { $connection.Dispose() }
	}
}

function Invoke-SqlScript {
<#
.SYNOPSIS
Executes a SQL script against the given database connection.
All scripts received are executed inside of a transaction.

If an existing connection is given then it is automatically
closed when the scripts are finished running.

.PARAMETER Connection
Can be any of the following:
* a [Data.Common.DbConnection] to be used
* a [string] connection string to use (Provider should also be specified)

.PARAMETER Provider
The ADO.NET DbProvider name to use when creating the connection.

.PARAMETER Script
Can be any of the following:
* a [string] SQL script to be executed
* a [string] path to SQL script file to be executed
* a [IO.FileInfo] for SQL script file to be executed
* an [array] of whose elements are any of the above

.PARAMETER StartLabel
When specified with EndLabel, only executes the portion of the script
between the StartLabel and the EndLabel.

.PARAMETER EndLabel
See StartLabel.

.PARAMETER Version
Version of the script being executed. This will be inserted
into the [psmigrations] table if specified.

.PARAMETER Name
Name of the script being executed. This will be inserted
into the [psmigrations] table if specified.

.PARAMETER IsRollback
When $true and a Version is specified, then the matching record is
deleted from the [psmigrations] table.

.LINK
Get-DbConnection
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[Alias("ConnectionString")]
		$Connection,
		[Parameter(Position=1, Mandatory=1, ValueFromPipelineByPropertyName=1)]
		[Alias("File")]
		$Script,
		[Parameter(Position=2, Mandatory=0)]
		[string]$Provider = $DEFAULT_PROVIDER_NAME,
		[Parameter(Position=3, Mandatory=0)]
		[string]$StartLabel,
		[Parameter(Position=4, Mandatory=0)]
		[string]$EndLabel,
		[Parameter(Position=5, Mandatory=0, ValueFromPipelineByPropertyName=1)]
		[long]$Version = 0,
		[Parameter(Position=6, Mandatory=0, ValueFromPipelineByPropertyName=1)]
		[string]$Name,
		[Parameter(Position=7, Mandatory=0)]
		[switch]$IsRollback
	)
	
	begin {
		$disposeConnection = $false
	
		# support the connection being a connection string (or the name of a connection string)
		if ($Connection -is [string]) {
			$Connection = (Get-DbConnection -Connection $Connection -Provider $Provider)
			$disposeConnection = $true # dispose the connection since we created it
		}
		
		# ensure the connection is a DbConnection before continuing
		if ($Connection -isnot [Data.Common.DbConnection]) {
			throw $Connection # throw the object that caused the error
		}
		
		$Connection.Open()
		$tx = $Connection.BeginTransaction()
		
		$regex = "(?ismx)^\s*" + [regex]::Escape($StartLabel) + ":\s*$  (?<SCRIPT>.*)  ^\s*" + [regex]::Escape($EndLabel) + ":\s*$"
	}
	process {		
		# support the script being an array of scripts
		foreach ($scriptItem in $Script) {	
		
			# support the script being a FileInfo object
			if ($scriptItem -is [IO.FileInfo]) {
				$scriptItem = [System.IO.File]::ReadAllText($Script.FullName)
			}
			# support the script being a file path
			elseif ($scriptItem -is [string] -and (Test-Path $Script -ErrorAction SilentlyContinue)) {
				$scriptItem = [IO.File]::ReadAllText($Script)
			}
			
			# by this point the script should be the actual SQL script to run
			# if not, then we need to stop here
			if ($scriptItem -isnot [string]) {
				throw $scriptItem # throw the object the caused the error
			}
			
			# parse out the section of the script that is between the StartLabel and the EndLabel
			if ($StartLabel -and $EndLabel) {
				if ($scriptItem -match $regex) {
					$scriptItem = $matches['SCRIPT']
				} else {
					Write-Error "Failed to parse labeled section of the script. Labels not found.`n$scriptItem"
					throw
				}
			}
			
			# split the script in parts by the GO keyword
			$scriptParts = [regex]::Split($scriptItem, "(?im)^\s*GO\s*$")
			
			# if a version or name was given then queue up
			# an insert into the [psmigrations] table
			# or a delete if we are rolling back
			if ($Version -gt 0 -or $Name) {
				if ($IsRollback) {
					$scriptParts += "DELETE FROM [dbo].[psmigrations] WHERE [version] = $Version"
				} else {
					$safeName = $Name.Replace("'", "''")
					$scriptParts += "INSERT INTO [dbo].[psmigrations] ([version], [script_name]) VALUES ($Version, '$safeName')"
				}
			}

			# execute each part of the script separately
			foreach ($scriptPart in $scriptParts) {
			
				# don't bother running empty scripts
				if ($scriptPart.Trim() -eq [string]::Empty) {
					continue
				}
				
				try {
					$cmd = $Connection.CreateCommand()
					$cmd.Transaction = $tx
					$cmd.CommandType = [Data.CommandType]::Text
					
					# assume the script is the actual sql script
					#Write-Host $scriptPart
					#Write-Host **********************
					$cmd.CommandText = $scriptPart
					$cmd.ExecuteNonQuery() | Out-Null
				}
				catch {
					$tx.Rollback()
					$Connection.Close()
					
					# throw both the error and the SQL script we were running
					Write-Error "Error executing SQL:`n$scriptPart"
					throw
				}
				finally { 
					if ($cmd) {
						$cmd.Dispose()
					}
				}
			}
		}
	}
	end {
		$tx.Commit()
		$Connection.Close()
		if ($disposeConnection) { $Connection.Dispose() }
	}
}


#-- Public Module Functions
function Get-DbStatus {
<#
.SYNOPSIS
Gets the current version of the database.
  
.PARAMETER ConnectionString
The connection string of the database to get the status of.
  
.PARAMETER Provider
The name of the DbProvider to use.
  
.PARAMETER ScriptPath
The path to the migration scripts.

.LINK
Install-PSMigrations
Get-DbVersion
Get-DbMigrationScriptVersion
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1, ValueFromPipeline=1)]
		[string]$ConnectionString,
		[Parameter(Position=1, Mandatory=0)]
		[string]$Provider = $DEFAULT_PROVIDER_NAME,
		[Parameter(Position=2, Mandatory=0)]
		[string]$ScriptPath = $DEFAULT_SCRIPT_PATH
	)
	
	Install-PSMigrations -ConnectionString $ConnectionString -Provider $Provider
	
	Write-Verbose "Using connection: $ConnectionString"
	
	$dbVersion = Get-DbVersion -ConnectionString $ConnectionString -Provider $Provider
	$scriptVersion = Get-DbMigrationScriptVersion -Path $ScriptPath
		
	Write-Host "Database version: $dbVersion"
	Write-Host "Scripts version: $scriptVersion"
}

function Invoke-DbMigrate() {
<#
.SYNOPSIS
Migrates the database to the given schema.

.PARAMETER ConnectionString
Connection string of the database to run the scripts against.

.PARAMETER Provider
Name of the ADO.NET DbProvider to use.

.PARAMETER ScriptPath
Directory path where to look for the migration scripts.

.PARAMETER TargetVersion
Script version to migrate the database to.
  
.LINK
Install-PSMigrations
Get-DbMigrationScript
Get-DbConnection
Get-DbVersion
Invoke-SqlScript
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1, ValueFromPipeline=1)]
		[string]$ConnectionString,
		[Parameter(Position=1, Mandatory=0)]
		[string]$Provider = $DEFAULT_PROVIDER_NAME,
		[Parameter(Position=2, Mandatory=0)]
		[string]$ScriptPath = $DEFAULT_SCRIPT_PATH,
		[Parameter(Position=3, Mandatory=0)]
		[Alias("Version")]
		[long]$TargetVersion = $(Get-DbMigrationScriptVersion -Path $ScriptPath)
	)
	
	Install-PSMigrations -ConnectionString $ConnectionString -Provider $Provider
	
	$scripts = Get-DbMigrationScript -Path $ScriptPath
		
	# ensure the target version has a matching script
	if ($Version -gt 0 -and -not($scripts | Where-Object { $_.Version -eq $TargetVersion })) {
		Write-Error "Invalid target version, there is no migration file for the version specified." `
			-RecommendedAction "Ensure the script path and target version are correct."
		return
	}
	
	$dbVersion = [long](Get-DbVersion -ConnectionString $ConnectionString -Provider $Provider)
	
	$connection = Get-DbConnection -ConnectionString $ConnectionString -Provider $Provider
	try {	
		if ($TargetVersion -gt $dbVersion) {
			# migrate up
			Write-Host "Database is at version $dbVersion. Migrating up to $TargetVersion."

			# execute all scripts in order
			$scripts | Where-Object { $_.Version -gt $dbVersion -and $_.Version -le $TargetVersion } `
				     | Invoke-SqlScript -Connection $connection	-StartLabel "BEGIN_SETUP" -EndLabel "END_SETUP"				 
			Write-Host "Database has been migrated to $TargetVersion."
			
		} elseif ($TargetVersion -lt $dbVersion) {
			# migrate down
			$scripts = $scripts | Sort-Object Version -Descending `
								| Where-Object { $_.Version -le $dbVersion -and $_.Version -gt $TargetVersion } `
								| Invoke-SqlScript -Connection $connection -StartLabel "BEGIN_TEARDOWN" -EndLabel "END_TEARDOWN" -IsRollback
								
			Write-Host "Database has been rolled back to $TargetVersion."
		} else {
			Write-Host "Database is already at the target version."
		}
	}
	finally {
		$connection.Dispose()
	}
}


Export-ModuleMember -Function Get-DbStatus, Invoke-DbMigrate
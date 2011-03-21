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
function Install-PSMigrationsTables {
<#
.SYNOPSIS
  Creates the psmigrations tables if needed.
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$ConnectionString,
		[Parameter(Position=1, Mandatory=1)]
		[string]$Provider
	)
	
	$connection = Get-DbConnection -ConnectionString $ConnectionString -Provider $Provider
	[System.Data.Common.DbCommand]$command | Out-Null
	
	try {
		$connection.Open()
		$command = $connection.CreateCommand()
		$command.CommandText = "
IF (NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'psmigrations'))
BEGIN
	CREATE TABLE [dbo].[psmigrations] ([id] INT IDENTITY(1,1) PRIMARY KEY, [version] BIGINT, [script_name] VARCHAR(255))
END
"
		$command.ExecuteNonQuery() | Out-Null
	} finally {
		if ($command) { $command.Dispose() }
		if ($connection) { $connection.Dispose() }
	}
}

function Get-DbMigrationScriptVersion {
<#
.SYNOPSIS
  Returns the latest migration script version number.
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$ScriptPath
	)
	
	$newestScriptName = Get-ChildItem $ScriptPath `
							| Sort-Object Name -Descending `
							| Select-Object -First 1

	$version = 0
	if ($newestScriptName) {
		$version = $newestScriptName.Name.Split('_')[0]
	}
	
	[long]$version
}

function Get-DbMigrationScript {
<#
.SYNOPSIS
  Returns all of the migration scripts.
#>
	param(
		[string]$Path = $DEFAULT_SCRIPT_PATH,
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

function Get-DbConnection {
<#
.SYNOPSIS
  Creates and returns a DbConnection to the database.
#>
	param(
		[string]$ConnectionString = $(throw "ConnectionString is required."),
		[string]$Provider = $(throw "Provider is required.")
	)
	$factory = [System.Data.Common.DbProviderFactories]::GetFactory($Provider)
	$connection = $factory.CreateConnection()
	$connection.ConnectionString = $ConnectionString
	$connection
}

function Get-DbVersion {
<#
.SYNOPSIS
  Gets the current db version.
  Creates the [psmigrations] table if needed.
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		[string]$ConnectionString,
		[Parameter(Position=1, Mandatory=1)]
		[string]$Provider
	)
	
	$connection = Get-DbConnection -ConnectionString $ConnectionString -Provider $Provider
	[System.Data.Common.DbCommand]$command | Out-Null
	
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

function Get-DbMigrationScriptUp {
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1, ValueFromPipeline=1)]
		$Script
	)
	
	begin {
		$regex = "(?ismx)^\s*BEGIN_SETUP:\s*$  (?<SETUP>.*)  ^\s*END_SETUP:\s*$"
	}
	process {
		# support the script being a Hashtable of our migration script info
		if ($Script.File -is [System.IO.FileInfo]) {
			$Script = $Script.File.FullName
		}
		# support the script being a FileInfo object
		if ($Script -is [System.IO.FileInfo]) {
			$Script = [System.IO.File]::ReadAllText($Script.FullName)
		}
		# support the script being a file path
		elseif (Test-Path $Script -ErrorAction SilentlyContinue) {
			$Script = [System.IO.File]::ReadAllText($Script)
		}
		
		if ($Script -match $regex) {
			$matches['SETUP']
		}
		else {
			# if there isn't a setup, assume the entire script is the setup
			$Script
		}
	}
	end {
	}
}

function Get-DbMigrationScriptDown {
<#
.SYNOPSIS
  
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1, ValueFromPipeline=1)]
		$Script
	)
	
	begin {
		$regex = "(?ismx)^\s*BEGIN_TEARDOWN:\s*$  (?<TEARDOWN>.*)  ^\s*END_TEARDOWN:\s*$"
	}
	process {
		# support the script being a Hashtable of our migration script info
		if ($Script.File -is [System.IO.FileInfo]) {
			$Script = $Script.File.FullName
		}
		# support the script being a FileInfo object
		if ($Script -is [System.IO.FileInfo]) {
			$Script = [System.IO.File]::ReadAllText($Script.FullName)
		}
		# support the script being a file path
		elseif (Test-Path $Script -ErrorAction SilentlyContinue) {
			$Script = [System.IO.File]::ReadAllText($Script)
		}
		
		if ($Script -match $regex) {
			$matches['TEARDOWN']
		}
		else {
			$null
		}
	}
	end {
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
	
	Install-PSMigrationsTables -ConnectionString $ConnectionString -Provider $Provider
	
	Write-Verbose "Using connection: $ConnectionString"
	
	$dbVersion = Get-DbVersion -ConnectionString $ConnectionString -Provider $Provider
	$scriptVersion = Get-DbMigrationScriptVersion -ScriptPath $ScriptPath
		
	Write-Host "Database version: $dbVersion"
	Write-Host "Scripts version: $scriptVersion"
}

function Invoke-DbScript {
<#
.SYNOPSIS
  Invokes a database script against the given connection.
  If multiple script are piped in then they are all
  executed inside a transaction.
  
.PARAMETER Connection
  [System.Data.Common.DbConnection] or [String] Connection String to use.
  
.PARAMETER Provider
  Provider name to use.
  
.PARAMETER Script
  SQL script, or path to SQL script file to execute.
#>
	[CmdletBinding()]
	param(
		[Parameter(Position=0, Mandatory=1)]
		$Connection,
		[Parameter(Position=1, Mandatory=1, ValueFromPipeline=1)]
		$Script,
		[Parameter(Position=2, Mandatory=0)]
		[string]$Provider = $DEFAULT_PROVIDER_NAME
	)
	
	begin {
		# support the connection being a connection string (or the name of a connection string)
		if ($Connection -is [string]) {
			$Connection = (Get-DbConnection -Connection $Connection -Provider $Provider)
		}
		
		# assume the connection is a DbConnection
		$Connection.Open()
		$tx = $Connection.BeginTransaction()
	}
	process {
		# support the script being a FileInfo object
		if ($Script -is [System.IO.FileInfo]) {
			$Script = [System.IO.File]::ReadAllText($Script.FullName)
		}
		# support the script being a file path
		elseif (Test-Path $Script -ErrorAction SilentlyContinue) {
			$Script = [System.IO.File]::ReadAllText($Script)
		}
		
		$scriptParts = ([regex]::Split($Script, "(?im)^\s*GO\s*$"))
		foreach ($scriptPart in $scriptParts) {
			if ($scriptPart.Trim() -eq [string]::Empty) {
				continue
			}
			
			try {
				$cmd = $Connection.CreateCommand()
				$cmd.Transaction = $tx
				$cmd.CommandType = [System.Data.CommandType]::Text
				
				# assume the script is the actual sql script
				Write-Host $scriptPart
				Write-Host **********************
				$cmd.CommandText = $scriptPart
				$cmd.ExecuteNonQuery() | Out-Null
			}
			catch {
				$tx.Rollback()
				$Connection.Close()
				throw
			}
			finally { 
				if ($cmd) {
					$cmd.Dispose()
				}
			}
		}
	}
	end {
		$tx.Commit()
		$Connection.Close()
	}
}

function Invoke-DbMigrate() {
<#
.SYNOPSIS
  Migrates the database to the given schema.
.LINK
  Install-PSMigrationsTables
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
		[long]$TargetVersion = $(Get-DbMigrationScriptVersion -ScriptPath $ScriptPath)
	)
	
	Install-PSMigrationsTables -ConnectionString $ConnectionString -Provider $Provider
	
	$scripts = Get-DbMigrationScript -Path $ScriptPath
		
	# Validate the target version has a matching script
	if (-not($scripts | Where-Object { $_.Version -eq $TargetVersion })) {
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
					 | Get-DbMigrationScriptUp `
				     | Invoke-DbScript -Connection $connection					 
			Write-Host "Database has been migrated to $TargetVersion."
			
		} elseif ($TargetVersion -le $dbVersion) {
			# migrate down
			#Write-Error "Rollbacks are not supported yet.`nIf they were we would be rolling back from $dbVersion to $TargetVersion."
			$scripts = $scripts | Sort-Object Version -Descending `
								| Where-Object { $_.Version -le $dbVersion -and $_.Version -gt $TargetVersion } `
								| Get-DbMigrationScriptDown `
								| Invoke-DbScript -Connection $connection
								
			Write-Host "Database has been rolled back to $TargetVersion."
		} else {
			Write-Host "Database is already at the target version."
		}
	}
	finally {
		$connection.Dispose()
	}
}

function Invoke-DbSetup() {
<#
.SYNOPSIS
  Migrates the database to the latest version
  and executes all seed data scripts.
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
	
	Invoke-DbMigrate -ConnectionString $ConnectionString -Provider $Provider -ScriptPath $ScriptPath
	
	# TODO: execute all seed data scripts
	# TODO: insert each script run, and its hash into a [psmigrations] table
}

Export-ModuleMember -Function Get-DbStatus, Invoke-DbMigrate, Invoke-DbSetup, Invoke-DbScript
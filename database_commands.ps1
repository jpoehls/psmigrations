function New-DbConnection {
  [CmdletBinding()]
  param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$ConnectionString,
    
    [Parameter(Position=1, ParameterSetName="ConnectionString")]
    [string]$Provider = "System.Data.SqlClient"
  )
  
  $factory = [System.Data.Common.DbProviderFactories]::GetFactory($Provider)
  $Connection = $factory.CreateConnection()
  $Connection.ConnectionString = $ConnectionString
  
  return $Connection
}

function Test-DbObject {
  [CmdletBinding(DefaultParameterSetName="ConnectionString")]
  param(
    [Parameter(Position=0)]
    [Alias("Schema")]
    [string]$SchemaName,
    
    [Parameter(Position=1, Mandatory=$true)]
    [Alias("Table")]
    [string]$TableName,
    
    [Parameter(Mandatory=$true, ParameterSetName="ConnectionString")]
    [string]$ConnectionString,
    
    [Parameter(ParameterSetName="ConnectionString")]
    [string]$Provider = "System.Data.SqlClient",
    
    [Parameter(Mandatory=$true, ParameterSetName="Connection")]
    [Data.Common.DbConnection]$Connection,
    
    [Data.Common.DbTransaction]$Transaction = $null,
    
    [ValidateSet("InformationSchema", "Sqlite")]
    [string]$Method = "InformationSchema"
  )
  
  $params = @{}
  
  if ($Method -eq "InformationSchema") {
    $params["Table"] = $TableName 
    $sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_name=@Table;"
  }
  elseif ($Method -eq "Sqlite") {
    $sql = "PRAGMA table_info($TableName);"
  }
  else {
    throw "Invalid method specified. [ $Method ]"
  }
  
  if ($Schema) {
    $sql += " AND table_schema=@Schema"
    $params["Schema"] = $SchemaName
  }
  
  if ($PsCmdlet.ParameterSetName -eq "ConnectionString") {
    $result = Invoke-DbCommand -CommandText $sql `
                               -Parameters $params `
                               -ConnectionString $ConnectionString `
                               -Provider $Provider `
                               -Transaction $Transaction `
                               -ExecutionMode Scalar 
  } else {
    $result = Invoke-DbCommand -CommandText $sql `
                               -Parameters $params `
                               -Connection $Connection  `
                               -Transaction $Transaction `
                               -ExecutionMode Scalar
  }

  Write-Output ($result -gt 0)
}

function Invoke-DbCommand {
  [CmdletBinding(SupportsShouldProcess=$true, DefaultParameterSetName="ConnectionString")]
  param(
    [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
    [Alias("Sql")]
    [string]$CommandText,
    [Parameter(Position=1, ValueFromPipelineByPropertyName=$true)]
    [hashtable]$Parameters,
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [Data.CommandType]$CommandType = [Data.CommandType]::Text,
    
    [Parameter(Mandatory=$true, ParameterSetName="ConnectionString")]
    [string]$ConnectionString,
    [Parameter(ParameterSetName="ConnectionString")]
    [string]$Provider = "System.Data.SqlClient",
    
    [Parameter(Mandatory=$true, ParameterSetName="Connection")]
    [Data.Common.DbConnection]$Connection,
    
    [Parameter(Mandatory=$false)]
    [Data.Common.DbTransaction]$Transaction,
    
    [ValidateSet("Query", "NonQuery", "Scalar")]
    [Alias("Mode")]
    [string]$ExecutionMode = "Query"
  )
  
  begin {
    # create the connection if it wasn't passed in
    if ($PsCmdlet.ParameterSetName -eq "ConnectionString") {
      Write-Verbose "Creating connection: $ConnectionString"
      Write-Verbose "Provider: $Provider"
      $Connection = New-DbConnection -ConnectionString $ConnectionString -Provider $Provider
    }
    
    if ($Connection.State -eq [Data.ConnectionState]::Closed) {
      Write-Verbose "Opening connection."
      $Connection.Open()
    }
        
    if ($Transaction) {
      $activeTransaction = $Transaction
    } else {
      Write-Verbose "Beginning transaction."
      $activeTransaction = $Connection.BeginTransaction()
      $ownTransaction = $true
    }
  }
  process {
    Write-Verbose "CommandText: $CommandText"
  
    # create the command
    $command = $Connection.CreateCommand()
    $command.CommandText = $CommandText
    $command.CommandType = $CommandType
    $command.Transaction = $activeTransaction
    
    if ($activeTransaction -eq $null) { throw "TX is null!?" }
    
    # add parameters to the command
    $Parameters.Keys | %{ 
      if ($_ -ne $null) {
        $param = $command.CreateParameter()
        $param.Value = $Parameters[$_]
        $param.ParameterName = $_
        $command.Parameters.Add($param) | Out-Null
        Write-Verbose "Parameter @$($param.ParameterName) = $($param.Value)"
      }
    }
    
    [Data.Common.DbDataReader]$reader = $null
    try {
      if ($PsCmdlet.ShouldProcess($CommandText)) {
        if ($ExecutionMode -eq "NonQuery") {
          $command.ExecuteNonQuery() | Out-Null
        }
        elseif ($ExecutionMode -eq "Scalar") {
          Write-Output $command.ExecuteScalar()
        }
        else {
          $reader = $command.ExecuteReader()
          
          while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
              # add the column name and value to the hash
              # these hash items will be converted to properties
              # on the PSObject we return
              $row.Add($reader.GetName($i), $reader.GetValue($i))
            }
            
            Write-Output (New-Object PSObject -Property $row)
          }
        }
      }
    }
    catch {
      if ($activeTransaction) {
        $activeTransaction.Rollback()
        Write-Verbose "Transaction rolled back."
        
        if ($ownTransaction) {
          $activeTransaction.Dispose()
          Write-Debug "Transaction disposed."
        }
      }
      
      # only close and dispose the connection if we created it
      if ($PsCmdlet.ParameterSetName -eq "ConnectionString") {
        if ($Connection) {
          $Connection.Dispose()
          Write-Verbose "Connection closed."
          Write-Debug "Connection disposed."
        }
      }
      
      Write-Error $error[0].Exception
      #Write-Error "Error executing SQL command:`n$CommandText"
      throw
    }
    finally {
      if ($reader) {
        $reader.Dispose()
        Write-Debug "Reader disposed."
      }
      
      if ($command) {
        $command.Dispose()
        Write-Debug "Command disposed."
      }
    }
  }
  end {
    if ($activeTransaction -and $ownTransaction) {
        $activeTransaction.Commit()
        Write-Verbose "Transaction committed."
        
        $activeTransaction.Dispose()
        Write-Debug "Transaction disposed."
    }
  
    # only close and dispose the connection if we created it
    if ($PsCmdlet.ParameterSetName -eq "ConnectionString") {
      if ($Connection) {
        $Connection.Dispose()
        Write-Verbose "Connection closed."
        Write-Debug "Connection disposed."
      }
    }
  }
}

function Split-SqlScript {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [Alias("Sql")]
        [string]$SqlScript
    )
    
    begin {
    
    }
    process {
        # Perform a very naive split on lines that only contain
        # the GO keyword surrounded by optional whitespace.
        $scriptParts = [regex]::Split($SqlScript, "(?im)^\s*GO\s*$")
        foreach ($part in $scriptParts) {
            if ($part.Trim().Length -gt 0) {
                Write-Output $part
            }
        }
    }
    end {
    
    }
}

# http://allen-mack.blogspot.com/2008/02/powershell-convert-csv-to-sql-insert.html
function Get-SqlInsertStatements {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [string]$TableName,
        [Parameter(Position=1, Mandatory=$true)]
        [PSObject[]]$Objects
    )
    
    $inserts = @()
    
    $inserts += "SET IDENTITY_INSERT [$TableName] ON"
    
    # Loop through the rows in the csv file.
    $Objects | % {
        # The insert variable is used to build a single insert statement.
        $insert = "INSERT INTO $tableName ("
        
        # We only care about the noteproperties, no use dealing with methods and the such.
        $properties = $_ | Get-Member | where { $_.MemberType -eq "NoteProperty" }

        # Create a comma delimited string of all the property names to use in the insert statement. 
        # You should make sure that the column headings in the CSV file match the field names in 
        # your table before you run the script.
        $properties | % {
            $value = $_.Definition.SubString($_.Definition.IndexOf("=") + 1)
            # only insert into the column if we were given a value to insert
            if ($value.Length -gt 0) {
                $insert += $_.Name + ", "
            }
        }
        
        $insert = $insert.TrimEnd(", ") + ") VALUES ("
        
        # Couldn't figure out how to access the value directly.  So here I'm forced to use 
        # substring to get it.  The Definition looks like "System.String PropertyName=PropertyValue".
        # Since the value will be enclosed in single quotes, you will run into trouble if the value  
        # contains a single quote.  To escape the single quote in T-SQL, just put another single quote
        # directly in front of it.
        $properties | % { 
            $value = $_.Definition.SubString($_.Definition.IndexOf("=") + 1)
            # only insert into the column if we were given a value to insert
            if ($value.Length -gt 0) {
                $insert += "'" + $value.Replace("'", "''") + "', " 
            }
        }
        
        $insert = $insert.TrimEnd(", ") + ")"
        
        # Append the insert statement to the end of the output file.
        $inserts += $insert
    }
    
    $inserts += "SET IDENTITY_INSERT [$TableName] OFF"
    
    Write-Output $inserts
}

$CONN_STR = "SERVER=.\SQLEXPRESS;DATABASE=psmigrations;INTEGRATED SECURITY=SSPI;"
$DB_PROVIDER = "System.Data.SqlClient"


Clear-Host

Test-DbObject -ConnectionString $CONN_STR -Provider $DB_PROVIDER `
              -Table "psmigrations" -Schema "dbo" -Verbose

<#
$sql = @("SELECT * FROM benjibender..customer",
         "SELECT email FROM benjibender..customer")

  
$sql | `
Invoke-DbCommand -ConnectionString $CONN_STR -Provider $DB_PROVIDER `
                 -Mode Query -Verbose | Format-Table
#>

<#
Invoke-DbCommand -ConnectionString $CONN_STR -Provider $DB_PROVIDER `
                 -CommandText "SELECT email FROM benjibender..customer" `
                 -Parameters @{id = 1} `
                 -Mode Query -Verbose | Format-Table                  
#>

<#
$conn = New-DbConnection $CONN_STR $DB_PROVIDER
$conn.Open()
$tx = $conn.BeginTransaction()
"SELECT email FROM benjibender..customer" | Invoke-DbCommand -Connection $conn -Transaction $tx `
                 -Parameters @{id = 1} `
                 -Mode Query -Verbose | Format-Table                  
$conn.Close()
#>
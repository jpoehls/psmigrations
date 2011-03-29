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
          Write-Output $command.ExecuteNonQuery()
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
      
      Write-Error "Error executing SQL command:`n$CommandText"
      
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
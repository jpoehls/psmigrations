function New-DbConnection {

}

function Test-DbName {
  [CmdletBinding(DefaultParameterSetName="ConnectionString")]
  param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Name,
    
    [Parameter(Mandatory=$true, ParameterSetName="ConnectionString")]
    [string]$ConnectionString,
    [Parameter(ParameterSetName="ConnectionString")]
    [string]$Provider = "System.Data.SqlClient",
    
    [Parameter(Mandatory=$true, ParameterSetName="Connection")]
    [Data.Common.DbConnection]$Connection,
    
    [Data.Common.DbTransaction]$Transaction = $null,
    
    [ValidateSet("Any", "Table", "Column", "Schema", "Function", "StoredProc", "Index", "Constraint")]
    [string]$ObjectType = "Any",
    
    [ValidateSet("InformationSchema", "Sqlite")]
    [string]$Method = "InformationSchema",
  )
  
  
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
    
    [Data.Common.DbTransaction]$Transaction,
    
    [ValidateSet("Query", "NonQuery", "Scalar")]
    [Alias("Mode")]
    [string]$ExecutionMode = "Query"
  )
  
  begin {
    # create the connection if it wasn't passed in
    if ($PsCmdlet.ParameterSetName -eq "ConnectionString") {
      $factory = [System.Data.Common.DbProviderFactories]::GetFactory($Provider)
  	  $Connection = $factory.CreateConnection()
  	  $Connection.ConnectionString = $ConnectionString
    }
    
    $Connection.Open()
        
    if ($Transaction) {
        Write-Host "Transaction was passed."
        $Connection.Enlist($Transaction)
        $activeTransaction = $Transaction
    } else {
        $activeTransaction = $Connection.BeginTransaction()
        Write-Host "Starting transaction"
    }
  }
  process { 
    # create the command
    $command = $Connection.CreateCommand()
    $command.CommandText = $CommandText
    $command.CommandType = $CommandType
    $command.Transaction = $Transaction
    
    # add parameters to the command
    $Parameters.Keys | %{ 
      if ($_ -ne $null) {
        $param = $command.CreateParameter()
        $param.Value = $Parameters[$_]
        $param.ParameterName = $_
        $command.Parameters.Add($param) | Out-Null
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
      if ($transaction) {
        $transaction.Rollback()
        
        if ($ownTransaction) { $transaction.Dispose() }
      }
      
      $Connection.Close()
      
      # only dispose the connection if we created it
      if ($PsCmdlet.ParameterSetName -eq "ConnectionString") {
        if ($Connection) { $Connection.Dispose() }
      }
      
      Write-Error "Error executing SQL command:`n$CommandText"
      
      throw
    }
    finally {
      if ($reader) { $reader.Dispose() }
      if ($command) { $command.Dispose() }
    }
  }
  end {
    if ($transaction -and $ownTransaction) {
        $transaction.Commit()
        $transaction.Dispose()
    }
    
    $Connection.Close()
  
    # only dispose the connection if we created it
    if ($PsCmdlet.ParameterSetName -eq "ConnectionString") {
      if ($Connection) { $Connection.Dispose() }
    }
  }
}

$CONN_STR = "SERVER=.\SQLEXPRESS;DATABASE=psmigrations;INTEGRATED SECURITY=SSPI;"
$DB_PROVIDER = "System.Data.SqlClient"


Clear-Host

$sql = @("SELECT * FROM benjibender..customer",
         "SELECT email FROM benjibender..customer")

$sql | `
Invoke-DbCommand -ConnectionString $CONN_STR -Provider $DB_PROVIDER `
                 -Mode Query | Format-Table

Invoke-DbCommand -ConnectionString $CONN_STR -Provider $DB_PROVIDER `
                 -CommandText "SELECT email FROM benjibender..customer" `
                 -Parameters @{id = 1} `
                 -Mode Query | Format-Table                  
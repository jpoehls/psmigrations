using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text;

namespace PSMigrations
{
    
    public class Installer
    {
        public void Go()
        {
            string sql = @"
IF (NOT EXISTS (SELECT *
                FROM INFORMATION_SCHEMA.TABLES
                WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'psmigrations'))
BEGIN
	CREATE TABLE [dbo].[psmigrations] (
        [id] INT IDENTITY(1,1) PRIMARY KEY,
        [version] BIGINT,
        [script_name] VARCHAR(255)
    )
END";
        }
    }

    public class InvokeSqlScript : PSCmdlet
    {
        
    }

    public class GetScalarValue : PSCmdlet
    {
        
    }

    // runs a query and returns the results as an array of PSObjects
    // with properties for each column
    public class InvokeSqlQuery:PSCmdlet{}

    // split by the GO keyword and return array of script parts
    public class SplitSqlScript : PSCmdlet
    {}

    // selects the part of the script between the given start/end labels
    // if the end label isn't found but the start is, then selects
    // the script start at the start label to the end
    public class SelectLabeledPartOfScript : PSCmdlet{}

    [Cmdlet(VerbsCommon.Get, "DbStatus")]
    public class GetDbStatus : PSCmdlet
    {
        /*
        [Parameter(Position = 0,
            Mandatory = false,
            ValueFromPipelineByPropertyName = true,
            HelpMessage = "Help Text")]
        [ValidateNotNullOrEmpty]
        public string Name
        {
            
        }
 */
        [Parameter]
        public string ConnectionString { get; set; }

        [Parameter]
        public string ProviderName { get; set; }

        [Parameter]
        public string ScriptPath { get; set; }

        protected override void ProcessRecord()
        {
            
            // select max version of psmigrations table
            // select max script version
            // return both
        }
    }
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text;

namespace PSMigrations
{
    [Cmdlet("Invoke", "SqlQuery", SupportsTransactions = true)]
    public class InvokeSqlQuery : PSCmdlet
    {
    }
}

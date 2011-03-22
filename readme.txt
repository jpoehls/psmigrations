System.Management.Automation.dll is located in C:\Program Files (x86)\Reference Assemblies\Microsoft\WindowsPowerShell\v1.0

GOALS

 * Nuget package that adds module to console in VS

 * Read connection strings from default project (nuget)'s config file
 
 * Use ScriptSplitter to support sql GO keywords
 
 * Some 'check' function that will ensure all migration scripts have been run on the db
   and that the script hashes match what's on disk. warn if any scripts havent' been run
   or if some scripts are missing or have been changed.
 
 * support WhatIf and Confirm using "ShouldProcess()"
 
 * support one-time scripts (sprocs/funcs/views) like roundhouse does

 * DLL should contain friendly API for use in web apps

 * DLL should contain PowerShell cmdlets

 * should have PS1 script that loads up the dll
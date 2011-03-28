using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data.Common;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml.Linq;
using NUnit.Framework;

namespace PSMigrations.Tests
{
    [TestFixture]
    public class Discovery
    {
        public IList<ConnectionStringSettings> GetConnectionStringsFromConfigFile(string configPath)
        {
            var fileMap = new ExeConfigurationFileMap
                              {
                                  ExeConfigFilename = configPath
                              };
            var config = ConfigurationManager.OpenMappedExeConfiguration(fileMap, ConfigurationUserLevel.None);

            var list = new List<ConnectionStringSettings>(config.ConnectionStrings.ConnectionStrings.Count);
            list.AddRange(config.ConnectionStrings.ConnectionStrings.Cast<ConnectionStringSettings>());

            return list;
        }

        public IList<ConnectionStringSettings> GetConnectionStringsFromProjects(string[] projectPaths)
        {
            var sqlcmd = new SqlCommand();
            var cmd = (DbCommand) sqlcmd;
            var p = cmd.CreateParameter();
            p.Value = "";
            p.ParameterName = "";
            cmd.Parameters.Add(p);
            //System.Data.IDataReader;
            var reader = cmd.ExecuteReader();
            var factory = DbProviderFactories.GetFactory("");
            var conn = factory.CreateConnection();
            
            while (reader.Read())
            {

            }

            var connectionStrings = new List<ConnectionStringSettings>();

            foreach (var path in projectPaths)
            {
                string appConfigPath = Path.Combine(path, "App.config");
                if (File.Exists(appConfigPath))
                {
                    connectionStrings.AddRange(GetConnectionStringsFromConfigFile(appConfigPath));
                }

                string webConfigPath = Path.Combine(path, "Web.config");
                if (File.Exists(webConfigPath))
                {
                    connectionStrings.AddRange(GetConnectionStringsFromConfigFile(webConfigPath));
                }
            }

            // TODO: remove duplicates
            return connectionStrings;
        }

        [Test]
        public void Alpha()
        {
            string[] configFiles = {
                                       @"c:\code\psmigrations\src\PSMigrations.Tests.DummyA\App.config",
                                       @"c:\code\psmigrations\src\PSMigrations.Tests.DummyB\App.config"
                                   };

            foreach (var configFile in configFiles)
            {
                var file = new ExeConfigurationFileMap();
                file.ExeConfigFilename = configFile;

                Console.WriteLine(configFile);

                var config = ConfigurationManager.OpenMappedExeConfiguration(file, ConfigurationUserLevel.None);
                Assert.IsTrue(config.HasFile, "Config file is missing.");
                
                foreach (ConnectionStringSettings connStr in config.ConnectionStrings.ConnectionStrings)
                {
                    Console.WriteLine("{0} | {1} | {2}", connStr.Name, connStr.ConnectionString, connStr.ProviderName);
                }

                Console.WriteLine(new string('*', 50));
            }
        }
    }
}

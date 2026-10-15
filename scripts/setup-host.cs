// Read-only setup prototype. Application scripts/defaults are compiled into the EXE.
// Reuses ConsoleHost from command-host.cs; does not load user profiles or set policy.
using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace WindowsHybridAgenticStack {
    public static class SetupHost {
        private static void Help() {
            Console.WriteLine("Windows Hybrid Agentic Stack setup prototype");
            Console.WriteLine("Usage: whas-setup-preview.exe [--help | --plan | --check] [OPTIONS]");
            Console.WriteLine("  --plan                 Preview selected components and destination");
            Console.WriteLine("  --check                Check selected prerequisites without installing");
            Console.WriteLine("  --cloud --local --voice Select components (default: bundled configuration)");
            Console.WriteLine("  --config PATH          Read JSON configuration overrides");
            Console.WriteLine("  --install-path PATH    Preview an installation destination");
            Console.WriteLine("This prototype does not install components.");
        }

        private static string Next(string[] args, ref int index) {
            if (++index >= args.Length || String.IsNullOrWhiteSpace(args[index]) || args[index].StartsWith("--", StringComparison.Ordinal))
                throw new ArgumentException("Missing option value.");
            return args[index];
        }

        [STAThread]
        public static int Main(string[] args) {
            try { return Run(args); }
            catch (Exception error) { Console.Error.WriteLine("Setup error: " + error.Message); return 1; }
        }

        private static int Run(string[] args) {
            string mode = null, config = null, path = null;
            bool cloud = false, local = false, voice = false;
            foreach (string value in args) if (value == null) throw new ArgumentException("Invalid argument.");
            for (int i = 0; i < args.Length; i++) {
                string option = args[i].ToLowerInvariant();
                if (option == "--help" || option == "-h" || option == "--plan" || option == "--check") {
                    if (mode != null) throw new ArgumentException("Choose one of --help, --plan or --check.");
                    mode = option == "-h" ? "--help" : option;
                } else if (option == "--cloud") cloud = true;
                else if (option == "--local") local = true;
                else if (option == "--voice") voice = true;
                else if (option == "--config") {
                    if (config != null) throw new ArgumentException("Duplicate --config option.");
                    config = Next(args, ref i);
                } else if (option == "--install-path") {
                    if (path != null) throw new ArgumentException("Duplicate --install-path option.");
                    path = Next(args, ref i);
                } else throw new ArgumentException("Unknown option: " + args[i]);
            }
            if (mode == "--help" || args.Length == 0) { Help(); return 0; }
            if (mode == null) throw new ArgumentException("Specify --plan or --check.");
            ConsoleHost host = new ConsoleHost();
            using (Runspace runspace = RunspaceFactory.CreateRunspace(host)) {
                runspace.Open();
                runspace.SessionStateProxy.Path.SetLocation(Environment.CurrentDirectory);
                if (runspace.SessionStateProxy.LanguageMode != PSLanguageMode.FullLanguage)
                    throw new InvalidOperationException("Setup requires an application context permitted by your administrator.");
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    ps.AddCommand("Get-ExecutionPolicy").AddParameter("List");
                    var policies = ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException("Unable to read execution policy; setup stopped.");
                    foreach (PSObject policy in policies) {
                        string scope = Convert.ToString(policy.Properties["Scope"].Value);
                        string value = Convert.ToString(policy.Properties["ExecutionPolicy"].Value);
                        if ((scope == "MachinePolicy" || scope == "UserPolicy") && value != "Undefined" && value != "Bypass" && value != "Unrestricted")
                            throw new InvalidOperationException("Organization policy restricts hosted setup code; contact your administrator.");
                    }
                    ps.Commands.Clear();
                    ps.AddScript(SetupPayload.Configuration, false);
                    ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                    ps.Commands.Clear();
                    ps.Streams.Error.Clear();
                    ps.AddScript(SetupPayload.Preview, true)
                        .AddParameter("DefaultsJson", SetupPayload.Defaults)
                        .AddParameter("ConfigPath", config).AddParameter("InstallPath", path)
                        .AddParameter("Cloud", cloud).AddParameter("Local", local).AddParameter("Voice", voice)
                        .AddParameter("ShowPlan", mode == "--plan");
                    var selection = ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                    if (selection.Count != 1) throw new InvalidOperationException("Unable to resolve component selection.");
                    if (mode == "--plan") return 0;
                    ps.Commands.Clear();
                    ps.Streams.Error.Clear();
                    ps.AddScript(SetupPayload.Prerequisites, true)
                        .AddParameter("Cloud", (bool)selection[0].Properties["Cloud"].Value)
                        .AddParameter("Local", (bool)selection[0].Properties["Local"].Value)
                        .AddParameter("Voice", (bool)selection[0].Properties["Voice"].Value)
                        .AddCommand("Out-Default");
                    ps.Invoke();
                    if (host.ExitRequested) return host.ExitCode;
                    return ps.HadErrors ? 1 : 0;
                }
            }
        }
    }
}

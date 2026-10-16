// Application scripts/defaults are compiled into the EXE.
// Reuses ConsoleHost from command-host.cs; does not load user profiles or set policy.
using System;
using System.Collections;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace WindowsHybridAgenticStack {
    public static class SetupHost {
        private static void Help() {
            Console.WriteLine("Windows Hybrid Agentic Stack setup");
            Console.WriteLine("Usage: whas-setup.exe [--help | --plan | --check | --install | --uninstall] [OPTIONS]");
            Console.WriteLine("  No arguments / --gui   Open the graphical setup and uninstaller");
            Console.WriteLine("  --core                 Install shared CLI and graphical applications only");
            Console.WriteLine("  --plan                 Preview selected components and destination");
            Console.WriteLine("  --check                Check selected prerequisites without installing");
            Console.WriteLine("  --cloud --local --voice Select components (default: bundled configuration)");
            Console.WriteLine("  --tts-engine IDS       Comma-separated TTS engines; first is default (--voice)");
            Console.WriteLine("  --local-models IDS     Comma-separated Ollama models to install (--local)");
            Console.WriteLine("  --default-local-model ID Choose the default from selected local models");
            Console.WriteLine("  --default-location ID  Save cloud or local as the default request location");
            Console.WriteLine("  --config PATH          Read JSON configuration overrides");
            Console.WriteLine("  --install-path PATH    Choose an installation destination");
            Console.WriteLine("  --install              Install selected cloud, local and voice components");
            Console.WriteLine("  --uninstall            Preview removal of a tracked installation");
            Console.WriteLine("  --apply                Apply uninstall, with confirmation");
            Console.WriteLine("  --retain-managed-models Keep installer-created models (otherwise removed if unchanged)");
            Console.WriteLine("  --remove-managed-models Legacy explicit removal flag; removal is now the default");
            Console.WriteLine("  --yes                  Accept installation/uninstall confirmation");
            Console.WriteLine("  --no-path              Leave the saved user PATH unchanged");
        }

        private static string Next(string[] args, ref int index) {
            if (++index >= args.Length || String.IsNullOrWhiteSpace(args[index]) || args[index].StartsWith("--", StringComparison.Ordinal))
                throw new ArgumentException("Missing option value.");
            return args[index];
        }

        [STAThread]
        public static int Main(string[] args) {
            if(Environment.GetEnvironmentVariable("WHAS_PROGRESS_EVENTS")=="1") Console.OutputEncoding=new System.Text.UTF8Encoding(false);
            if (args.Length == 0 || (args.Length == 1 && args[0] == "--gui") || (args.Length == 2 && args[0] == "--gui-render")) {
                System.Windows.Forms.Application.EnableVisualStyles();
                System.Windows.Forms.Application.SetCompatibleTextRenderingDefault(false);
                string executable = System.Reflection.Assembly.GetExecutingAssembly().Location;
                using (var window = new WhasWindow(true, executable, SetupPayload.StrategyCatalog)) {
                    if (args.Length == 2) window.Render(args[1]);
                    else System.Windows.Forms.Application.Run(window);
                }
                return 0;
            }
            try { return Run(args); }
            catch (Exception error) { Console.Error.WriteLine("Setup error: " + error.Message); return 1; }
        }

        internal static void EnsureAllowed(Runspace runspace) {
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
            }
        }

        private static int Run(string[] args) {
            string mode = null, config = null, path = null, ttsEngine = null, localModels = null, defaultLocalModel = null, defaultLocation = null;
            bool cloud = false, local = false, voice = false, core = false;
            bool yes = false, apply = false, noPath = false, removeModels = false, retainModels = false;
            foreach (string value in args) if (value == null) throw new ArgumentException("Invalid argument.");
            for (int i = 0; i < args.Length; i++) {
                string option = args[i].ToLowerInvariant();
                if (option == "--help" || option == "-h" || option == "--plan" || option == "--check" || option == "--install" || option == "--uninstall") {
                    if (mode != null) throw new ArgumentException("Choose one setup action.");
                    mode = option == "-h" ? "--help" : option;
                } else if (option == "--cloud") cloud = true;
                else if (option == "--core") core = true;
                else if (option == "--local") local = true;
                else if (option == "--voice") voice = true;
                else if (option == "--local-models") { if (localModels != null) throw new ArgumentException("Duplicate local models."); localModels = Next(args, ref i); }
                else if (option == "--default-location") { if(defaultLocation != null) throw new ArgumentException("Duplicate default location."); defaultLocation=Next(args,ref i); }
                else if (option == "--default-local-model") { if (defaultLocalModel != null) throw new ArgumentException("Duplicate default model."); defaultLocalModel = Next(args, ref i); }
                else if (option == "--tts-engine") {
                    if (ttsEngine != null) throw new ArgumentException("Duplicate --tts-engine option.");
                    ttsEngine = Next(args, ref i);
                }
                else if (option == "--yes") yes = true;
                else if (option == "--apply") apply = true;
                else if (option == "--no-path") noPath = true;
                else if (option == "--remove-managed-models") removeModels = true;
                else if (option == "--retain-managed-models") retainModels = true;
                else if (option == "--config") {
                    if (config != null) throw new ArgumentException("Duplicate --config option.");
                    config = Next(args, ref i);
                } else if (option == "--install-path") {
                    if (path != null) throw new ArgumentException("Duplicate --install-path option.");
                    path = Next(args, ref i);
                } else throw new ArgumentException("Unknown option: " + args[i]);
            }
            if (mode == "--help" || args.Length == 0) { Help(); return 0; }
            if (mode == null) throw new ArgumentException("Specify a setup action; use --help for usage.");
            if (apply && mode != "--uninstall") throw new ArgumentException("--apply requires --uninstall.");
            if (removeModels && mode != "--uninstall") throw new ArgumentException("--remove-managed-models requires --uninstall.");
            if (retainModels && mode != "--uninstall") throw new ArgumentException("--retain-managed-models requires --uninstall.");
            if (retainModels && removeModels) throw new ArgumentException("Choose either --retain-managed-models or --remove-managed-models, not both.");
            if (yes && mode != "--install" && !(mode == "--uninstall" && apply)) throw new ArgumentException("--yes requires installation or applied uninstall.");
            if (noPath && mode != "--install" && mode != "--uninstall") throw new ArgumentException("--no-path requires install or uninstall.");
            if (ttsEngine != null && !voice) throw new ArgumentException("--tts-engine requires --voice.");
            if ((localModels != null || defaultLocalModel != null) && (!local || mode == "--uninstall")) throw new ArgumentException("Local model selection requires --local setup.");
            if (mode == "--uninstall") {
                if (core || cloud || local || voice || config != null || ttsEngine != null || defaultLocation != null) throw new ArgumentException("Uninstall does not accept component or configuration flags.");
                Hashtable arguments = new Hashtable { { "Apply", apply }, { "PersistCommandPath", !noPath }, { "RetainManagedModels", retainModels }, { "RemoveManagedModels", removeModels } };
                if (path != null) arguments.Add("InstallPath", path);
                if (yes) arguments.Add("Confirm", false);
                return SetupRuntime.Run("uninstall.ps1", arguments, null);
            }
            ConsoleHost host = new ConsoleHost();
            using (Runspace runspace = RunspaceFactory.CreateRunspace(host)) {
                runspace.Open();
                runspace.SessionStateProxy.Path.SetLocation(Environment.CurrentDirectory);
                EnsureAllowed(runspace);
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    ps.AddScript(SetupPayload.Configuration, false);
                    ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                    ps.Commands.Clear();
                    ps.Streams.Error.Clear();
                    ps.AddScript(SetupPayload.StrategyHelper, false);
                    ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                    ps.Commands.Clear();
                    ps.Streams.Error.Clear();
                    ps.AddScript(SetupPayload.Preview, true)
                        .AddParameter("DefaultsJson", SetupPayload.Defaults)
                        .AddParameter("StrategyCatalogJson", SetupPayload.StrategyCatalog).AddParameter("TtsEngine", ttsEngine)
                        .AddParameter("LocalModels", localModels).AddParameter("DefaultLocalModel", defaultLocalModel)
                        .AddParameter("DefaultLocation",defaultLocation)
                        .AddParameter("Interactive", mode == "--install" && !yes)
                        .AddParameter("ConfigPath", config).AddParameter("InstallPath", path)
                        .AddParameter("Cloud", cloud).AddParameter("Local", local).AddParameter("Voice", voice)
                        .AddParameter("Core", core)
                        .AddParameter("ShowPlan", mode == "--plan");
                    var selection = ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                    if (selection.Count != 1) throw new InvalidOperationException("Unable to resolve component selection.");
                    if (mode == "--plan") return 0;
                    if (mode == "--install") {
                        Hashtable arguments = new Hashtable { { "Cloud", (bool)selection[0].Properties["Cloud"].Value }, { "Local", (bool)selection[0].Properties["Local"].Value }, { "Voice", (bool)selection[0].Properties["Voice"].Value }, { "InstallPath", LanguagePrimitives.ConvertTo<string>(selection[0].Properties["InstallPath"].Value) }, { "Yes", yes }, { "PersistCommandPath", !noPath } };
                        arguments.Add("Core", core);
                        if ((bool)selection[0].Properties["Voice"].Value)
                            arguments.Add("TtsEngine", LanguagePrimitives.ConvertTo<string>(selection[0].Properties["EngineSelection"].Value));
                        if (localModels != null) arguments.Add("LocalModels", localModels);
                        if (defaultLocalModel != null) arguments.Add("DefaultLocalModel", defaultLocalModel);
                        if (defaultLocation != null) arguments.Add("DefaultLocation",defaultLocation);
                        return SetupRuntime.Run("install.ps1", arguments, LanguagePrimitives.ConvertTo<string>(selection[0].Properties["ConfigJson"].Value));
                    }
                    string[] manifests = LanguagePrimitives.ConvertTo<string[]>(selection[0].Properties["StrategyManifestJsons"].Value);
                    if (manifests == null || manifests.Length == 0) manifests = new string[] { null };
                    for (int check = 0; check < manifests.Length; check++) {
                        ps.Commands.Clear(); ps.Streams.Error.Clear();
                        host.ExitRequested = false; host.ExitCode = 0;
                        ps.AddScript(SetupPayload.Prerequisites, true)
                        .AddParameter("Cloud", check == 0 && (bool)selection[0].Properties["Cloud"].Value)
                        .AddParameter("Local", check == 0 && (bool)selection[0].Properties["Local"].Value)
                        .AddParameter("Voice", (bool)selection[0].Properties["Voice"].Value)
                        .AddParameter("Core", core)
                        .AddParameter("StrategyManifestJson", manifests[check])
                        .AddCommand("Out-Default");
                        ps.Invoke();
                        if (host.ExitRequested && host.ExitCode != 0) return host.ExitCode;
                        if (ps.HadErrors) return 1;
                    }
                    return 0;
                }
            }
        }
    }
}

// Built locally with the compiler included with Windows PowerShell 5.1.
// Runs application command code through Microsoft's PowerShell hosting API.
// Does not load profiles, change execution policies, or alter authorization managers.
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Runspaces;
using System.Security;
using System.Runtime.InteropServices;

namespace WindowsHybridAgenticStack {
    public sealed class ConsoleUI : PSHostUserInterface {
        public override PSHostRawUserInterface RawUI { get { return null; } }
        public override string ReadLine() { return Console.ReadLine(); }
        public override SecureString ReadLineAsSecureString() { throw new NotSupportedException("Secure input is not used by stack commands."); }
        public override void Write(string value) { Console.Write(value); }
        public override void Write(ConsoleColor foreground, ConsoleColor background, string value) {
            if (Console.IsOutputRedirected) { Console.Write(value); return; }
            ConsoleColor previousForeground = Console.ForegroundColor;
            ConsoleColor previousBackground = Console.BackgroundColor;
            try {
                Console.ForegroundColor = foreground;
                Console.BackgroundColor = background;
                Console.Write(value);
            }
            finally {
                Console.ForegroundColor = previousForeground;
                Console.BackgroundColor = previousBackground;
            }
        }
        public override void WriteLine(string value) { Console.WriteLine(value); }
        public override void WriteErrorLine(string value) { Console.Error.WriteLine(value); }
        public override void WriteDebugLine(string value) { Console.Error.WriteLine(value); }
        public override void WriteVerboseLine(string value) { Console.Error.WriteLine(value); }
        public override void WriteWarningLine(string value) { Console.Error.WriteLine("WARNING: " + value); }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> fields) {
            Dictionary<string, PSObject> answers = new Dictionary<string, PSObject>();
            if (!String.IsNullOrEmpty(caption)) Console.WriteLine(caption);
            if (!String.IsNullOrEmpty(message)) Console.WriteLine(message);
            foreach (FieldDescription field in fields) {
                Console.Write(field.Name + ": ");
                string answer = Console.ReadLine();
                if (answer == null) throw new ArgumentException("Missing input for " + field.Name);
                answers.Add(field.Name, PSObject.AsPSObject(answer));
            }
            return answers;
        }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) {
            throw new NotSupportedException("Configure provider authentication with OpenCode.");
        }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes types, PSCredentialUIOptions options) {
            return PromptForCredential(caption, message, userName, targetName);
        }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
            Console.WriteLine(caption + " " + message);
            for (int i = 0; i < choices.Count; i++) Console.WriteLine(i + ": " + choices[i].Label);
            string answer = Console.ReadLine();
            int selected;
            return Int32.TryParse(answer, out selected) && selected >= 0 && selected < choices.Count ? selected : defaultChoice;
        }
    }

    public sealed class ConsoleHost : PSHost {
        private readonly Guid id = Guid.NewGuid();
        private readonly ConsoleUI ui = new ConsoleUI();
        public bool ExitRequested;
        public int ExitCode;
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "WindowsHybridAgenticStack"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override PSHostUserInterface UI { get { return ui; } }
        public override CultureInfo CurrentCulture { get { return CultureInfo.CurrentCulture; } }
        public override CultureInfo CurrentUICulture { get { return CultureInfo.CurrentUICulture; } }
        public override void SetShouldExit(int exitCode) { ExitRequested = true; ExitCode = exitCode; }
        public override void EnterNestedPrompt() { throw new NotSupportedException("Nested prompts are not supported."); }
        public override void ExitNestedPrompt() { }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }

    public static class CommandHost {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo {
            public int Size;
            public string Reserved, Desktop, Title;
            public uint X, Y, XSize, YSize, XChars, YChars, Fill, Flags;
            public short ShowWindow, ReservedSize;
            public IntPtr ReservedData, Input, Output, Error;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation {
            public IntPtr Process, Thread;
            public int ProcessId, ThreadId;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(string application, System.Text.StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint flags,
            IntPtr environment, string directory, ref StartupInfo startup, out ProcessInformation process);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        public static int StartBackgroundProcess(string executable, string arguments, string directory) {
            StartupInfo startup = new StartupInfo();
            startup.Size = Marshal.SizeOf(typeof(StartupInfo));
            ProcessInformation process;
            // No inherited console/pipe handles. The service opens its own logs.
            System.Text.StringBuilder commandLine = new System.Text.StringBuilder("\"" + executable + "\" " + arguments);
            if (!CreateProcess(executable, commandLine, IntPtr.Zero, IntPtr.Zero, false, 0x08000000,
                IntPtr.Zero, directory, ref startup, out process))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            CloseHandle(process.Thread);
            CloseHandle(process.Process);
            return process.ProcessId;
        }

        private static readonly string[] Agents = { "agent", "agentdo", "localagent", "localagentdo" };
        private static readonly Dictionary<string, string[]> TtsParameters = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase) {
            { "tts-start", new string[0] }, { "tts-stop", new string[0] }, { "tts-status", new string[0] },
            { "tts-voice-list", new string[0] }, { "tts-say", new string[] { "Text", "Voice" } },
            { "tts-voice-add", new string[] { "Path", "Name" } },
            { "tts-voice-remove", new string[] { "Name" } }, { "tts-voice-test", new string[] { "Name" } }
        };

        private static void Load(PowerShell ps, string path, string root) {
            if (!File.Exists(path)) throw new FileNotFoundException("Stack runtime file is missing; reinstall the selected component.", path);
            ps.Commands.Clear();
            ps.Streams.Error.Clear();
            ps.AddScript(File.ReadAllText(path), false);
            if (root != null) ps.AddParameter("InstallPath", root);
            ps.Invoke();
            if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
        }

        [STAThread]
        public static int Main(string[] args) {
            try { return Run(args); }
            catch (Exception error) { Console.Error.WriteLine("Stack command error: " + error.Message); return 1; }
        }

        private static int Run(string[] args) {
            string executable = Process.GetCurrentProcess().MainModule.FileName;
            string command = Path.GetFileNameWithoutExtension(executable).ToLowerInvariant();
            bool isAgent = Array.IndexOf(Agents, command) >= 0;
            if (!isAgent && !TtsParameters.ContainsKey(command)) throw new ArgumentException("Unknown stack command: " + command);
            string registration = Path.Combine(Path.GetDirectoryName(executable), "install-root.txt");
            if (!File.Exists(registration)) throw new FileNotFoundException("Local stack registration is missing.", registration);
            string root = File.ReadAllText(registration).TrimEnd('\r', '\n');
            if (!Path.IsPathRooted(root) || !Directory.Exists(root)) throw new DirectoryNotFoundException("Stack installation is missing: " + root);
            ConsoleHost host = new ConsoleHost();
            using (Runspace runspace = RunspaceFactory.CreateRunspace(host)) {
                runspace.Open();
                // Preserve the caller's working directory and policy. No profiles are loaded.
                runspace.SessionStateProxy.Path.SetLocation(Environment.CurrentDirectory);
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    // Respect enforced policy instead of interpreting unsigned application
                    // code when an administrator explicitly requires signed/no scripts.
                    ps.AddCommand("Get-ExecutionPolicy").AddParameter("List");
                    foreach (PSObject policy in ps.Invoke()) {
                        string scope = Convert.ToString(policy.Properties["Scope"].Value);
                        string value = Convert.ToString(policy.Properties["ExecutionPolicy"].Value);
                        if ((scope == "MachinePolicy" || scope == "UserPolicy") && value != "Undefined" && value != "Bypass" && value != "Unrestricted")
                            throw new InvalidOperationException("Organization policy restricts hosted command code; contact your administrator.");
                    }
                    if (isAgent) {
                        Load(ps, Path.Combine(root, "scripts", "configuration.ps1"), null);
                        Load(ps, Path.Combine(root, "scripts", "agent-commands.ps1"), root);
                    }
                    string tts = Path.Combine(root, "tts", "tts.ps1");
                    string strategies = Path.Combine(root, "tts", "strategy-management.ps1");
                    if (File.Exists(strategies)) Load(ps, strategies, null);
                    if (!isAgent || File.Exists(tts)) Load(ps, tts, root);
                    ps.Commands.Clear();
                    ps.Streams.Error.Clear();
                    if (isAgent) {
                        ps.AddCommand("Invoke-AgentStackTask").AddParameter("Kind", command).AddParameter("Arguments", args);
                    } else {
                        ps.AddCommand(command);
                        string[] allowed = TtsParameters[command];
                        for (int i = 0; i < args.Length; i++) {
                            string parameter = null;
                            if (args[i].StartsWith("-", StringComparison.Ordinal)) {
                                foreach (string candidate in allowed) if (String.Equals(args[i], "-" + candidate, StringComparison.OrdinalIgnoreCase)) parameter = candidate;
                                if (parameter == null) throw new ArgumentException("Unknown option: " + args[i]);
                                if (++i >= args.Length) throw new ArgumentException("Missing value after -" + parameter);
                                ps.AddParameter(parameter, args[i]);
                            } else ps.AddArgument(args[i]);
                        }
                    }
                    using (PSDataCollection<PSObject> output = new PSDataCollection<PSObject>()) {
                        output.DataAdded += delegate(object sender, DataAddedEventArgs e) { Console.WriteLine(output[e.Index]); };
                        ps.Streams.Error.DataAdded += delegate(object sender, DataAddedEventArgs e) { Console.Error.WriteLine(ps.Streams.Error[e.Index]); };
                        ConsoleCancelEventHandler cancel = delegate(object sender, ConsoleCancelEventArgs e) { e.Cancel = true; ps.Stop(); };
                        Console.CancelKeyPress += cancel;
                        try { ps.EndInvoke(ps.BeginInvoke<PSObject, PSObject>(null, output)); }
                        finally { Console.CancelKeyPress -= cancel; }
                    }
                    if (host.ExitRequested) return host.ExitCode;
                    if (ps.HadErrors) return 1;
                    object nativeExit = runspace.SessionStateProxy.GetVariable("LASTEXITCODE");
                    return nativeExit is int ? (int)nativeExit : 0;
                }
            }
        }
    }
}

using System;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;

namespace WindowsHybridAgenticStack {
    public sealed class SetupScriptResult {
        public int ExitCode;
        public Collection<PSObject> Output;
    }
    public static class SetupRuntime {
        private static string root;
        public static bool IsHosting { get { return root != null; } }

        private static string AssetName(string path) {
            string full = Path.GetFullPath(path);
            if (root == null || !full.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Script is outside the bundled setup application.");
            string name = full.Substring(root.Length + 1).Replace('\\', '/');
            if (!SetupPayload.Files.ContainsKey(name)) throw new InvalidOperationException("Script is not a bundled setup asset: " + name);
            return name;
        }
        public static ScriptBlock LoadScript(string path) {
            string name = AssetName(path);
            if (!name.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Not an application script.");
            Token[] tokens;
            ParseError[] errors;
            ScriptBlockAst ast = Parser.ParseInput(SetupPayload.ReadText(name), Path.GetFullPath(path), out tokens, out errors);
            if (errors.Length != 0) throw new InvalidOperationException("Invalid bundled script: " + errors[0].Message);
            return ast.GetScriptBlock();
        }
        public static SetupScriptResult InvokeScript(string path, IDictionary arguments) { return Execute(path, arguments, false); }

        public static SetupScriptResult InvokeVerifiedScript(string path, string hash, IDictionary arguments) {
            string text;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                using (var sha = SHA256.Create()) {
                    string actual = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
                    if (actual != hash) throw new InvalidOperationException("Strategy hook changed.");
                }
                stream.Position = 0;
                using (var reader = new StreamReader(stream)) text = reader.ReadToEnd();
            }
            Token[] tokens; ParseError[] errors;
            var ast = Parser.ParseInput(text, Path.GetFullPath(path), out tokens, out errors);
            if (errors.Length != 0) throw new InvalidOperationException("Invalid installed strategy hook.");
            return Execute(path, arguments, false, ast.GetScriptBlock());
        }

        private static SetupScriptResult Execute(string path, IDictionary arguments, bool display, ScriptBlock verified = null) {
            ConsoleHost host = new ConsoleHost();
            using (Runspace runspace = RunspaceFactory.CreateRunspace(host)) {
                runspace.Open();
                runspace.SessionStateProxy.Path.SetLocation(Environment.CurrentDirectory);
                SetupHost.EnsureAllowed(runspace);
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    ps.AddScript(SetupPayload.ReadText("scripts/script-invocation.ps1"), false);
                    ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                    ps.Commands.Clear(); ps.Streams.Error.Clear();
                    runspace.SessionStateProxy.SetVariable("StackSetupEntrypoint", verified ?? LoadScript(path));
                    runspace.SessionStateProxy.SetVariable("StackSetupArguments", arguments);
                    ps.AddScript("& $StackSetupEntrypoint @StackSetupArguments", false);
                    if (display) ps.AddCommand("Out-Default");
                    Collection<PSObject> output = ps.Invoke();
                    foreach (ErrorRecord error in ps.Streams.Error) Console.Error.WriteLine(error);
                    return new SetupScriptResult { Output = output, ExitCode = host.ExitRequested ? host.ExitCode : (ps.HadErrors ? 1 : 0) };
                }
            }
        }
        public static int Run(string script, IDictionary arguments, string configuration) {
            if (root != null) throw new InvalidOperationException("Setup is already running.");
            root = Path.Combine(Path.GetTempPath(), "whas-setup-payload-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try {
                foreach (var file in SetupPayload.Files) {
                    string destination = Path.Combine(root, file.Key.Replace('/', Path.DirectorySeparatorChar));
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    File.WriteAllBytes(destination, Convert.FromBase64String(file.Value));
                }
                if (configuration != null) File.WriteAllText(Path.Combine(root, "config", "config.json"), configuration, new System.Text.UTF8Encoding(false));
                return Execute(Path.Combine(root, script), arguments, true).ExitCode;
            }
            finally {
                // Delete only known extracted assets and empty directories. Never recurse
                // into unknown data, and never interpret a link created during execution.
                string cleanupRoot = root;
                root = null;
                try {
                    foreach (var file in SetupPayload.Files) DeleteExtracted(cleanupRoot, file.Key);
                    if (configuration != null) DeleteExtracted(cleanupRoot, "config/config.json");
                    var parents = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    parents.Add("");
                    foreach (var file in SetupPayload.Files) {
                        string directory = Path.GetDirectoryName(file.Key.Replace('/', Path.DirectorySeparatorChar));
                        while (!String.IsNullOrEmpty(directory)) { parents.Add(directory); directory = Path.GetDirectoryName(directory); }
                    }
                    var ordered = new List<string>(parents);
                    ordered.Sort((a, b) => b.Length.CompareTo(a.Length));
                    foreach (string directory in ordered) {
                        string path = CheckedExtractedPath(cleanupRoot, directory);
                        if (Directory.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0 && Directory.GetFileSystemEntries(path).Length == 0)
                            Directory.Delete(path);
                    }
                } catch (Exception error) { Console.Error.WriteLine("Setup temporary files retained: " + error.Message); }
            }
        }
        private static void DeleteExtracted(string cleanupRoot, string relative) {
            string path = CheckedExtractedPath(cleanupRoot, relative);
            if (File.Exists(path)) File.Delete(path);
        }
        private static string CheckedExtractedPath(string cleanupRoot, string relative) {
            string path = Path.GetFullPath(Path.Combine(cleanupRoot, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!String.Equals(path, cleanupRoot, StringComparison.OrdinalIgnoreCase) && !path.StartsWith(cleanupRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Invalid cleanup path.");
            string ancestor = path;
            while (ancestor.Length >= cleanupRoot.Length) {
                if ((File.Exists(ancestor) || Directory.Exists(ancestor)) && (File.GetAttributes(ancestor) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidOperationException("Temporary path became a link; retained for review.");
                ancestor = Path.GetDirectoryName(ancestor);
                if (ancestor == null) break;
            }
            return path;
        }
    }
}

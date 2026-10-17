// Windows Forms is included with the Windows .NET Framework. No UI runtime
// download, web server, embedded browser or account is required by this UI.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace WindowsHybridAgenticStack {
    // Windows Common Item Dialog in folder mode; no extra UI dependency.
    internal static class FolderPicker {
        [ComImport,Guid("42F85136-DB7E-439C-85F1-E4075D135FC8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileDialog {
            [PreserveSig] int Show(IntPtr owner);
            void SetFileTypes(uint count,IntPtr types); void SetFileTypeIndex(uint index); void GetFileTypeIndex(out uint index);
            void Advise(IntPtr events,out uint cookie); void Unadvise(uint cookie);
            void SetOptions(uint options); void GetOptions(out uint options);
            void SetDefaultFolder(IShellItem folder); void SetFolder(IShellItem folder); void GetFolder(out IShellItem folder); void GetCurrentSelection(out IShellItem item);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)]string name); void GetFileName([MarshalAs(UnmanagedType.LPWStr)]out string name);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)]string title); void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)]string text); void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)]string text);
            void GetResult(out IShellItem item);
        }
        [ComImport,Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem {
            void BindToHandler(IntPtr context,ref Guid handler,ref Guid iid,out IntPtr result); void GetParent(out IShellItem parent);
            void GetDisplayName(uint kind,out IntPtr name); void GetAttributes(uint mask,out uint attributes); void Compare(IShellItem other,uint hint,out int order);
        }
        [DllImport("shell32.dll",CharSet=CharSet.Unicode,PreserveSig=false)]
        private static extern void SHCreateItemFromParsingName(string path,IntPtr context,ref Guid iid,out IShellItem item);
        private static IFileDialog CreateDialog(string initial,string title) {
            var dialog=(IFileDialog)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")));
            try {
                uint options;dialog.GetOptions(out options);dialog.SetOptions(options|0x20|0x40|0x800|0x8|0x02000000);
                dialog.SetTitle(title);dialog.SetOkButtonLabel("Select folder");
                if(Directory.Exists(initial)) {IShellItem folder=null;try {var iid=new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");SHCreateItemFromParsingName(Path.GetFullPath(initial),IntPtr.Zero,ref iid,out folder);dialog.SetFolder(folder);}finally{if(folder!=null) Marshal.FinalReleaseComObject(folder);}}
                return dialog;
            } catch {Marshal.FinalReleaseComObject(dialog);throw;}
        }
        internal static string Select(IWin32Window owner,string initial,string title) {
            var dialog=CreateDialog(initial,title);IShellItem selected=null;IntPtr name=IntPtr.Zero;
            try {int result=dialog.Show(owner==null?IntPtr.Zero:owner.Handle);if(result==unchecked((int)0x800704C7)) return null;Marshal.ThrowExceptionForHR(result);dialog.GetResult(out selected);selected.GetDisplayName(0x80058000,out name);return Marshal.PtrToStringUni(name);}
            finally {if(name!=IntPtr.Zero) Marshal.FreeCoTaskMem(name);if(selected!=null) Marshal.FinalReleaseComObject(selected);Marshal.FinalReleaseComObject(dialog);}
        }
    }
    internal sealed class GuiPreferences {
        public string Theme="system", ActiveWorkspace="";
        public readonly List<string> Workspaces=new List<string>();
        private readonly string path;
        private string snapshot;
        public string Warning="";
        public GuiPreferences(string file) {
            path=file??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"WindowsHybridAgenticStack","gui-preferences.json");
            if(!File.Exists(path)) return;
            try {
                snapshot=File.ReadAllText(path);
                var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(snapshot);
                if(data==null || !data.ContainsKey("schemaVersion") || Convert.ToInt32(data["schemaVersion"])!=1) throw new ArgumentException("Unsupported GUI preferences.");
                object value;
                if(data.TryGetValue("theme",out value) && new[]{"system","light","dark"}.Contains(Convert.ToString(value))) Theme=Convert.ToString(value);
                if(data.TryGetValue("workspaces",out value) && value is IList) foreach(object item in (IList)value) {string folder=Normalize(Convert.ToString(item));if(!Workspaces.Contains(folder,StringComparer.OrdinalIgnoreCase)) Workspaces.Add(folder);}
                if(data.TryGetValue("activeWorkspace",out value)) {string active=Convert.ToString(value);if(Workspaces.Contains(active,StringComparer.OrdinalIgnoreCase)) ActiveWorkspace=active;}
            }catch(Exception error) {Theme="system";Workspaces.Clear();ActiveWorkspace="";Warning="GUI preferences could not be read: "+error.Message;}
        }
        public void SeedWorkspace(string folder) {if(snapshot==null && Workspaces.Count==0) {Workspaces.Add(Normalize(folder));ActiveWorkspace=Workspaces[0];}}
        public static string Normalize(string folder) {
            if(!Path.IsPathRooted(folder)) throw new ArgumentException("Choose an absolute workspace path.");
            string full=Path.GetFullPath(folder);return full.Length>Path.GetPathRoot(full).Length?full.TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar):full;
        }
        public void Save() {
            string key;using(var hash=System.Security.Cryptography.SHA256.Create()) key=BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToUpperInvariant()))).Replace("-","");
            using(var mutex=new Mutex(false,"Local\\WHAS-GuiPreferences-"+key)) {
                bool entered=false;try {
                    try {entered=mutex.WaitOne(5000);}catch(AbandonedMutexException){entered=true;}
                    if(!entered) throw new IOException("Another window is saving GUI preferences. Try again.");
                    string current=File.Exists(path)?File.ReadAllText(path):null;
                    if(current!=snapshot) throw new IOException("GUI preferences changed in another window. Reopen this window before saving.");
                    var data=new Dictionary<string,object>{{"schemaVersion",1},{"theme",Theme},{"workspaces",Workspaces.ToArray()},{"activeWorkspace",ActiveWorkspace}};
                    string text=new JavaScriptSerializer().Serialize(data);Directory.CreateDirectory(Path.GetDirectoryName(path));string temp=path+".tmp."+Guid.NewGuid().ToString("N");
                    try {File.WriteAllText(temp,text,new UTF8Encoding(false));if(File.Exists(path)) File.Replace(temp,path,null);else File.Move(temp,path);snapshot=text;}finally{if(File.Exists(temp)) File.Delete(temp);}
                }finally{if(entered) mutex.ReleaseMutex();}
            }
        }
    }
    public static class GuiMaintenance {
        public static bool IsTemporarySetup(string executable) {
            string directory=Path.GetDirectoryName(Path.GetFullPath(executable));
            return String.Equals(Path.GetDirectoryName(directory).TrimEnd('\\'),Path.GetTempPath().TrimEnd('\\'),StringComparison.OrdinalIgnoreCase) && Regex.IsMatch(Path.GetFileName(directory),"^whas-setup-ui-[a-f0-9]{32}$") && (Path.GetFileName(executable)=="whas-setup.exe" || Path.GetFileName(executable)=="whas-gui.exe");
        }
        public static string CopySetup(string executable) {
            string directory=Path.Combine(Path.GetTempPath(),"whas-setup-ui-"+Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            string target=Path.Combine(directory,Path.GetFileName(executable)=="whas-gui.exe"?"whas-gui.exe":"whas-setup.exe");
            File.Copy(executable,target); File.SetAttributes(target,FileAttributes.Normal); return target;
        }
        public static void CleanupAfterExit(string executable) {
            string directory=Path.GetDirectoryName(Path.GetFullPath(executable));
            if(!IsTemporarySetup(executable)) return;
            string literal=executable.Replace("'","''"); string folder=directory.Replace("'","''");
            string code="Wait-Process -Id "+Process.GetCurrentProcess().Id+" -ErrorAction SilentlyContinue; for($i=0;$i -lt 30;$i++){try{[IO.File]::Delete('"+literal+"');[IO.Directory]::Delete('"+folder+"');break}catch{Start-Sleep -Milliseconds 200}}";
            string shell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","powershell.exe");
            Process.Start(new ProcessStartInfo(shell,"-NoLogo -NoProfile -NonInteractive -Command "+GuiProcess.Quote(code)){UseShellExecute=false,CreateNoWindow=true});
        }
        public static void CheckUnlockedGui(string root) {
            string prefix=Path.GetFullPath(root).TrimEnd('\\')+"\\";
            foreach(var process in Process.GetProcesses()) {
                try {
                    if((process.ProcessName=="whas-gui" || process.ProcessName=="whas-setup") && process.MainModule.FileName.StartsWith(prefix,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Close other WHAS windows in this installation before uninstalling.");
                } catch(System.ComponentModel.Win32Exception) { } finally { process.Dispose(); }
            }
        }
    }
    public sealed class GuiProcess : IDisposable {
        internal static string FindApplication(string name) {
            string path=Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.Machine)+";"+Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.User)+";"+Environment.GetEnvironmentVariable("Path");
            foreach(string directory in path.Split(';')) {
                if(String.IsNullOrWhiteSpace(directory)) continue;
                try {string candidate=Path.Combine(Environment.ExpandEnvironmentVariables(directory.Trim().Trim('"')),name);if(File.Exists(candidate)) return candidate;}catch(ArgumentException){}
            }
            return null;
        }
        private Process process;
        private IntPtr job;
        public bool Running { get { try { return process != null && !process.HasExited; } catch(InvalidOperationException) { return false; } } }
        public bool CanCancel { get { return job != IntPtr.Zero; } }
        public bool WaitForStop(int milliseconds) { return process==null || process.WaitForExit(milliseconds); }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll")] private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll")] private static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        public static string Quote(string value) {
            if (value.IndexOf('\0') >= 0) throw new ArgumentException("Invalid command argument.");
            // CommandLineToArgvW quoting; no command shell is involved.
            var text=new StringBuilder("\""); int slashes=0;
            foreach(char c in value) {
                if(c=='\\') { slashes++; continue; }
                if(c=='\"') text.Append('\\',slashes*2+1).Append(c);
                else text.Append('\\',slashes).Append(c);
                slashes=0;
            }
            return text.Append('\\',slashes*2).Append('\"').ToString();
        }
        public void Start(string executable, IEnumerable<string> arguments, Action<string,bool> line, Action<int> done, IDictionary<string,string> environment=null, string workingDirectory=null) {
            if (Running) throw new InvalidOperationException("Wait for the current operation.");
            ProcessStartInfo start = new ProcessStartInfo(executable, String.Join(" ", arguments.Select(Quote)));
            start.UseShellExecute=false; start.CreateNoWindow=true;
            start.RedirectStandardOutput=true; start.RedirectStandardError=true; start.RedirectStandardInput=true;
            start.StandardOutputEncoding=Encoding.UTF8; start.StandardErrorEncoding=Encoding.UTF8;
            if(workingDirectory!=null) start.WorkingDirectory=workingDirectory;
            start.EnvironmentVariables["WHAS_PROGRESS_EVENTS"]="1";
            start.EnvironmentVariables["Path"]=Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.Machine)+";"+Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.User)+";"+Environment.GetEnvironmentVariable("Path");
            if(environment!=null) foreach(var item in environment) start.EnvironmentVariables[item.Key]=item.Value;
            process=new Process(); process.StartInfo=start;
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) line(e.Data,false); };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) line(e.Data,true); };
            process.Start();
            job=CreateJobObject(IntPtr.Zero,null);
            if (job != IntPtr.Zero && !AssignProcessToJobObject(job,process.Handle)) { CloseHandle(job); job=IntPtr.Zero; }
            process.StandardInput.Close(); process.BeginOutputReadLine(); process.BeginErrorReadLine();
            Process owned=process;
            Thread waiter=new Thread(delegate() {
                int code=130;
                try { owned.WaitForExit(); code=owned.ExitCode; } catch(InvalidOperationException) { }
                done(code);
            }); waiter.IsBackground=true; waiter.Start();
        }
        public void Cancel() {
            if (!Running) return;
            if (!CanCancel) throw new InvalidOperationException("Windows did not grant request-tree cancellation. Wait for completion.");
            if (!TerminateJobObject(job,130)) throw new InvalidOperationException("Cancellation was not accepted by Windows.");
        }
        public void CancelRoot() { if(Running) process.Kill(); }
        public void Dispose() { if (Running) return; if (process != null) { process.Dispose(); process=null; } if (job != IntPtr.Zero) { CloseHandle(job); job=IntPtr.Zero; } }
    }

    public sealed class ProviderWindow : Form {
        private readonly GuiProcess server=new GuiProcess();
        private readonly string password=Guid.NewGuid().ToString("N");
        private readonly Label state=new Label {Dock=DockStyle.Top,Height=74};
        public ProviderWindow(string root) {
            Text="Provider accounts — OpenCode"; Size=new Size(670,350); StartPosition=FormStartPosition.CenterParent; Font=new Font("Segoe UI",10);
            var content=new FlowLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(20),FlowDirection=FlowDirection.TopDown,WrapContents=false}; Controls.Add(content);
            state.Width=600; state.Text="OpenCode's account interface opens in your browser.\nFor its temporary local login, use username: opencode and the password below."; content.Controls.Add(state);
            var field=new TextBox {Text=password,UseSystemPasswordChar=true,ReadOnly=true,Width=450}; content.Controls.Add(field);
            var copy=new Button {Text="Copy temporary local password",AutoSize=true}; copy.Click+=delegate { Clipboard.SetText(password); }; content.Controls.Add(copy);
            var details=new Label {Text="Provider sign-in is handled by OpenCode. Existing provider credentials remain in its own storage and are shared with CLI use. Closing this window stops only this temporary local server.",Width=600,Height=74}; content.Controls.Add(details);
            var done=new Button {Text="Done",Width=120}; done.Click+=delegate { Close(); }; content.Controls.Add(done);
            Shown+=delegate {
                try {
                    string path=Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.User)+";"+Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.Machine)+";"+Environment.GetEnvironmentVariable("Path");
                    string binary=path.Split(';').Select(p=>Path.Combine(Environment.ExpandEnvironmentVariables(p.Trim('"')),"opencode.exe")).FirstOrDefault(File.Exists);
                    if(binary==null) throw new InvalidOperationException("Install OpenCode first using the prerequisite guide.");
                    var listener=new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback,0); listener.Start(); int port=((System.Net.IPEndPoint)listener.LocalEndpoint).Port; listener.Stop();
                    // This child alone receives the access secret; it is never an
                    // argument, log entry, URL or persistent environment setting.
                    var environment=new Dictionary<string,string>{{"OPENCODE_SERVER_PASSWORD",password},{"OPENCODE_SERVER_USERNAME","opencode"}};
                    if(File.Exists(Path.Combine(root,"opencode.json"))) environment["OPENCODE_CONFIG"]=Path.Combine(root,"opencode.json");
                    server.Start(binary,new[]{"serve","--hostname","127.0.0.1","--port",port.ToString()},delegate(string line,bool error) {},delegate(int code) {},environment);
                    if(!server.CanCancel) { server.CancelRoot(); throw new InvalidOperationException("Windows did not allow an owned provider-server lifecycle."); }
                    Thread readiness=new Thread(delegate() {
                        string address="http://127.0.0.1:"+port;
                        bool ready=false;
                        for(int i=0;i<60 && server.Running;i++) {
                            try {
                                var request=(System.Net.HttpWebRequest)System.Net.WebRequest.Create(address+"/global/health"); request.Timeout=500; request.Proxy=null;
                                request.Headers["Authorization"]="Basic "+Convert.ToBase64String(Encoding.UTF8.GetBytes("opencode:"+password));
                                using(var response=request.GetResponse()) { ready=true; }
                                var anonymous=(System.Net.HttpWebRequest)System.Net.WebRequest.Create(address+"/global/health"); anonymous.Timeout=500; anonymous.Proxy=null;
                                try { using(var response=anonymous.GetResponse()) { ready=false; } }
                                catch(System.Net.WebException denied) { var response=denied.Response as System.Net.HttpWebResponse; ready=response!=null && response.StatusCode==System.Net.HttpStatusCode.Unauthorized; if(response!=null) response.Dispose(); }
                                break;
                            } catch { Thread.Sleep(250); }
                        }
                        try { if(!IsDisposed && IsHandleCreated) BeginInvoke((Action)delegate {
                            if(ready) { state.Text="Ready. OpenCode opens in your browser.\nUsername: opencode — use Copy password for the temporary local login."; Process.Start(new ProcessStartInfo(address){UseShellExecute=true}); }
                            else state.Text="The provider interface did not become ready. Close this window and check OpenCode installation.";
                        }); } catch(InvalidOperationException) { }
                    }); readiness.IsBackground=true; readiness.Start();
                } catch(Exception error) { state.Text=error.Message; }
            };
            FormClosing+=delegate(object sender,FormClosingEventArgs e) {
                try { if(server.Running) { server.Cancel(); if(!server.WaitForStop(5000)) { e.Cancel=true; state.Text="Waiting for the owned provider server to stop."; } } }
                catch(Exception error) { e.Cancel=true; state.Text=error.Message; }
            };
            FormClosed+=delegate { server.Dispose(); try { if(Clipboard.ContainsText() && Clipboard.GetText()==password) Clipboard.Clear(); } catch(ExternalException) {} };
        }
    }

    internal sealed class OllamaChatRequest {
        private HttpWebRequest request;
        private int cancelled;
        internal bool Cancelled {get{return Interlocked.CompareExchange(ref cancelled,0,0)!=0;}}
        internal void Cancel() {Interlocked.Exchange(ref cancelled,1);var active=request;if(active!=null) active.Abort();}
        internal void Start(Uri endpoint,string model,object[] messages,Action<string> changed,Action<string,string> completed) {
            if(endpoint.Scheme!="http" || !endpoint.IsLoopback) throw new ArgumentException("Local chat requires a loopback Ollama endpoint.");
            request=(HttpWebRequest)WebRequest.Create(endpoint);request.Method="POST";request.ContentType="application/json";request.Proxy=null;request.AllowAutoRedirect=false;request.Timeout=300000;request.ReadWriteTimeout=300000;request.ServicePoint.Expect100Continue=false;
            var worker=new Thread(delegate() {
                var json=new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue};var answer=new StringBuilder();string error=null;
                try {
                    byte[] payload=Encoding.UTF8.GetBytes(json.Serialize(new {model=model,messages=messages,stream=true}));request.ContentLength=payload.Length;
                    using(var body=request.GetRequestStream()) body.Write(payload,0,payload.Length);
                    bool done=false,published=false;var refresh=Stopwatch.StartNew();
                    using(var response=(HttpWebResponse)request.GetResponse()) using(var reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8)) {
                        string line;while((line=reader.ReadLine())!=null) {
                            if(Cancelled) break;if(String.IsNullOrWhiteSpace(line)) continue;
                            var frame=json.Deserialize<Dictionary<string,object>>(line);object value;
                            if(frame==null) throw new InvalidDataException("Ollama returned invalid response data.");
                            if(frame.TryGetValue("error",out value)) throw new InvalidOperationException(Convert.ToString(value));
                            if(frame.TryGetValue("message",out value) && value is Dictionary<string,object>) {object content;if(((Dictionary<string,object>)value).TryGetValue("content",out content)) answer.Append(Convert.ToString(content));}
                            if(answer.Length>0 && (!published || refresh.ElapsedMilliseconds>=75)) {changed(answer.ToString());published=true;refresh.Restart();}
                            if(frame.TryGetValue("done",out value) && value is bool && (bool)value) {done=true;break;}
                        }
                    }
                    if(!Cancelled && (!done || String.IsNullOrWhiteSpace(answer.ToString()))) throw new InvalidDataException(done?"Ollama returned no answer.":"The Ollama response ended before completion.");
                } catch(WebException failure) {
                    error="Could not connect to Ollama. Check that Ollama is running.";
                    if(failure.Response!=null) try {using(var response=failure.Response) using(var reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8)) {var detail=json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd());object value;if(detail!=null && detail.TryGetValue("error",out value)) error=Convert.ToString(value);}} catch {error=failure.Message;}
                } catch(Exception failure) {error=failure.Message;}
                completed(answer.ToString(),Cancelled?"Request cancelled.":error);
            });worker.IsBackground=true;worker.Start();
        }
    }

    public sealed class WhasWindow : Form {
        internal sealed class ConversationReply {
            internal string Key,Value;
            internal bool Pending,Complete;
        }
        internal readonly List<ConversationReply> ConversationReplies=new List<ConversationReply>();
        internal int ConversationRevision;
        private ConversationReply BeginConversationReply(string message) {
            var reply=new ConversationReply {Key=message,Pending=true};ConversationReplies.Add(reply);ConversationRevision++;
            conversation.AppendText("You: "+message+Environment.NewLine);return reply;
        }
        private void CompleteConversationReply(ConversationReply reply,string answer) {
            if(reply.Complete) return;
            reply.Value=answer;reply.Pending=false;reply.Complete=true;ConversationRevision++;
            conversation.AppendText("Assistant: "+answer+Environment.NewLine+Environment.NewLine);
        }
        internal void AddConversationReply(string message,string answer) {
            CompleteConversationReply(BeginConversationReply(message),answer);
        }
        // The WPF presenter uses these existing action/state bindings. This
        // controller is never shown by the normal graphical entry point.
        internal IWin32Window DialogOwner {get;set;}
        internal event Action PresentationChanged;
        internal event Action AppearanceChanged;
        internal GuiPreferences Preferences {get{return preferences;}}
        internal bool IsSetup {get{return setup;}}
        internal void ClearActivityLog() {output.Clear();}
        internal void CompleteRemoval(string installationRoot) {
            root=Path.GetFullPath(installationRoot);setup=true;
            ResetConversationContext();ConversationReplies.Clear();ConversationRevision++;
            BuildPages();
            status.Text="WHAS removed. Personal/modified files remain. Existing terminals must refresh PATH or reopen.";
        }
        internal string SavedSpeechEngine {get{return savedEngine;}}
        internal string SelectedSpeechEngine {get{return voiceEngine==null?"":Convert.ToString(voiceEngine.SelectedItem);}}
        internal bool SelectedSpeechInstalled {get{return voiceInventoryLoaded && voiceInventory.ContainsKey(SelectedSpeechEngine) && (bool)voiceInventory[SelectedSpeechEngine]["installed"];}}
        internal bool SelectedSpeechCloning {get{return voiceInventory.ContainsKey(SelectedSpeechEngine) && (bool)voiceInventory[SelectedSpeechEngine]["voiceCloning"];}}
        internal bool SelectedSpeechTranscript {get{return voiceInventory.ContainsKey(SelectedSpeechEngine) && (bool)voiceInventory[SelectedSpeechEngine]["transcriptRequired"];}}
        internal bool SelectedSpeechDeviceChoice {get{return voiceDeviceChoices.ContainsKey(SelectedSpeechEngine) && voiceDeviceChoices[SelectedSpeechEngine];}}
        internal string MaintenanceFeature {get;private set;}
        internal bool MaintenanceChecked {get{return checkPassed && checkedSelection==String.Join("\n",Selection());}}
        private string reviewedSelection;
        private string setupReviewedSelection;
        internal readonly List<KeyValuePair<string,string>> SetupReview=new List<KeyValuePair<string,string>>();
        internal bool SetupReady {get {try{return checkPassed && checkedSelection==String.Join("\n",Selection());}catch(ArgumentException){return false;}}}
        internal bool SetupReviewed {get {return SetupReady && setupReviewedSelection==checkedSelection;}}
        private string removalRecordPath;
        private DateTime removalRecordWrite;
        private bool removalRecordExists;
        internal bool HasRemovalTarget {get {
            try {
                string record=Path.Combine(destination.Text,".whas-installation.json");
                if(!File.Exists(record)){removalRecordPath=null;removalRecordExists=false;return false;}
                DateTime written=File.GetLastWriteTimeUtc(record);
                if(record==removalRecordPath && written==removalRecordWrite)return removalRecordExists;
                var state=new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue}.Deserialize<Dictionary<string,object>>(File.ReadAllText(record));
                removalRecordExists=state.ContainsKey("Status") && Convert.ToString(state["Status"])!="Uninstalled";removalRecordPath=record;removalRecordWrite=written;return removalRecordExists;
            }catch(Exception){return false;}
        }}
        private void ReviewSetup() {
            var selection=Selection();setupReviewedSelection=null;SetupReview.Clear();
            var summary=new List<KeyValuePair<string,string>>();
            summary.Add(new KeyValuePair<string,string>("Installation folder",Path.GetFullPath(destination.Text)));
            summary.Add(new KeyValuePair<string,string>("Features",String.Join(", ",new[]{cloud.Checked?"Cloud AI":null,local.Checked?"Local AI":null,voice.Checked?"Speech":null}.Where(x=>x!=null).DefaultIfEmpty("Shared application only"))));
            summary.Add(new KeyValuePair<string,string>("Run on by default",Convert.ToString(defaultLocation.SelectedItem)=="local"?"This PC":"Cloud"));
            if(local.Checked)summary.Add(new KeyValuePair<string,string>("Local models",String.Join(", ",models.CheckedItems.Cast<string>())+"\nDefault: "+Convert.ToString(defaultModel.SelectedItem)));
            if(voice.Checked)foreach(int i in engines.CheckedIndices){string id=engineIds[i],device=Convert.ToString(setupDevices[id].SelectedItem);var manifest=json.Deserialize<object[]>(catalog).Cast<Dictionary<string,object>>().First(x=>Convert.ToString(x["id"])==id);summary.Add(new KeyValuePair<string,string>(Convert.ToString(engines.Items[i]),(device=="auto"?"Prefer GPU (CPU fallback)":device=="cpu"?"CPU":"GPU")+(Convert.ToString(defaultEngine.SelectedItem)==id?" · Default engine":"")+"\nVersion "+Convert.ToString(manifest["version"])+" · "+Convert.ToString(manifest["license"])));}
            Run(executable,new[]{"--plan"}.Concat(selection),delegate(int code,string text){if(code==0 && String.Join("\n",Selection())==String.Join("\n",selection)){setupReviewedSelection=String.Join("\n",selection);SetupReview.AddRange(summary);status.Text="Selection reviewed. Select Apply selected features to install.";}});
        }
        internal bool MaintenanceReviewed {get{return MaintenanceChecked && reviewedSelection==checkedSelection;}}
        internal void BeginMaintenance(string feature) {
            if(IsBusy) throw new InvalidOperationException("Wait for the current operation.");
            if(!new[]{"core","cloud","local","voice"}.Contains(feature)) throw new ArgumentException("Unknown feature.");
            LoadDefaultLocation();
            MaintenanceFeature=feature;cloud.Checked=feature=="cloud";local.Checked=feature=="local";voice.Checked=feature=="voice";
            checkedSelection=reviewedSelection=null;checkPassed=false;checkGrid.Rows.Clear();
            if(feature=="local") {
                string model=Convert.ToString(((ComboBox)settings["local.model"]).SelectedItem);
                if(model.StartsWith("whas-",StringComparison.Ordinal)) {
                    string match=null;var state=new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue}.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,".whas-installation.json")));object entries;
                    if(state.TryGetValue("Models",out entries) && entries is IList) foreach(var entry in ((IList)entries).Cast<Dictionary<string,object>>()) {object kind,name;if(entry.TryGetValue("Kind",out kind) && Convert.ToString(kind)=="Source" && entry.TryGetValue("Name",out name)) {string source=Convert.ToString(name),prefix="whas-"+Regex.Replace(source.ToLowerInvariant(),"[^a-z0-9-]","-").Trim('-')+"-ctx";if(model.StartsWith(prefix,StringComparison.Ordinal) && Regex.IsMatch(model.Substring(prefix.Length),"^[0-9]+(:latest)?$")) match=source;}}
                    model=match;
                }
                for(int i=0;i<models.Items.Count;i++) models.SetItemChecked(i,false);
                if(!String.IsNullOrEmpty(model)) {if(!models.Items.Contains(model)) models.Items.Add(model);models.SetItemChecked(models.Items.IndexOf(model),true);}UpdateModels();
            }
            if(feature=="voice" && voiceInventoryLoaded) {for(int i=0;i<engineIds.Count;i++) engines.SetItemChecked(i,voiceInventory.ContainsKey(engineIds[i]) && (bool)voiceInventory[engineIds[i]]["installed"]);UpdateEngines();if(defaultEngine.Items.Contains(savedEngine)) defaultEngine.SelectedItem=savedEngine;if(engines.CheckedItems.Count==0 && engines.Items.Count>0){engines.SetItemChecked(0,true);UpdateEngines();}}
        }
        internal void CheckMaintenance() {CheckPrerequisites();}
        internal static string PrerequisitePackage(string component) {
            if(component=="Python 3.11") return "Python.Python.3.11";
            if(component=="Visual C++ x64") return "Microsoft.VCRedist.2015+.x64";
            if(component=="OpenCode") return "SST.opencode";
            if(component=="Ollama") return "Ollama.Ollama";
            return null;
        }
        internal static string[] PrerequisiteInstallArguments(string component) {
            string package=PrerequisitePackage(component);
            if(package==null) throw new ArgumentException("Use this component's official download page.");
            return new[]{"install","--id",package,"--exact","--source","winget","--accept-source-agreements","--accept-package-agreements","--disable-interactivity"};
        }
        internal static string FindWinGet() {
            string paths=Environment.GetEnvironmentVariable("Path")+";"+Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.User)+";"+Environment.GetEnvironmentVariable("Path",EnvironmentVariableTarget.Machine)+";"+Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Microsoft","WindowsApps");
            foreach(string entry in paths.Split(';')) {
                try {string candidate=Path.Combine(entry.Trim().Trim('"'),"winget.exe");if(Path.IsPathRooted(candidate) && File.Exists(candidate)) return candidate;} catch(ArgumentException) { }
            }
            return null;
        }
        internal void InstallPrerequisite(string component) {
            string[] arguments=PrerequisiteInstallArguments(component);
            string winget=FindWinGet();
            if(winget==null) throw new InvalidOperationException("WinGet is unavailable. Use Open download page, then select Check Again.");
            if(IsBusy) throw new InvalidOperationException("Wait for the current operation.");
            checkPassed=false;checkedSelection=setupReviewedSelection=reviewedSelection=null;SetupReview.Clear();
            Run(winget,arguments,delegate(int code,string text) {
                if(code==0) {string installationOutput=output.Text;CheckPrerequisites();output.AppendText(installationOutput+Environment.NewLine+"Checking prerequisites after installation…"+Environment.NewLine);}
                else status.Text="WinGet could not complete installation. Review the activity log, or use Open download page, then select Check Again.";
            });
            status.Text="Installing "+component+" with WinGet…";
        }
        internal void CloseMaintenance() {if(IsBusy) throw new InvalidOperationException("Wait for the current operation.");MaintenanceFeature=null;checkPassed=false;checkedSelection=reviewedSelection=null;}
        internal void ReviewMaintenance() {var selection=Selection();if(!MaintenanceChecked) throw new InvalidOperationException("Check readiness for this selection first.");reviewedSelection=null;Run(executable,new[]{"--plan"}.Concat(selection),delegate(int code,string text){if(code==0) reviewedSelection=String.Join("\n",selection);});}
        internal void ApplyMaintenance() {
            if(!MaintenanceReviewed) throw new InvalidOperationException("Check readiness and review these changes first.");
            if(MessageBox.Show(DialogOwner??this,"Apply the reviewed changes? Existing accounts, personal voices and other features are preserved.","Apply maintenance",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes) return;
            Run(executable,new[]{"--install","--yes"}.Concat(Selection()),delegate(int code,string text){if(code==0){MaintenanceFeature=null;RefreshFeatureStatus();ReloadSettings();if(PresentationChanged!=null) PresentationChanged();}});
        }
        internal void RemoveRoute(string feature) {
            if(feature!="cloud" && feature!="local") throw new ArgumentException("Choose Cloud or Local AI.");
            BeginMaintenance("core");var options=Selection();
            Run(executable,new[]{"--check"}.Concat(options),delegate(int checkedCode,string checks){if(checkedCode!=0)return;Run(executable,new[]{"--plan"}.Concat(options),delegate(int plannedCode,string plan){if(plannedCode!=0)return;
                if(MessageBox.Show(DialogOwner??this,"Shared app repair plan:"+Environment.NewLine+plan.Trim()+Environment.NewLine+Environment.NewLine+"Remove the "+feature+" route from WHAS after this update? Provider accounts, external applications and model files are kept. Add this feature again to restore requests.","Remove feature",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes) {MaintenanceFeature=null;status.Text="Feature removal cancelled. No changes applied.";return;}
                Run(executable,new[]{"--install","--yes"}.Concat(options),delegate(int code,string text){if(code==0) Maintenance("remove-route",new[]{"--feature",feature},delegate(int result,string output){if(result==0){MaintenanceFeature=null;RefreshFeatureStatus();ReloadSettings();if(PresentationChanged!=null) PresentationChanged();}});});
            });});
        }
        private void Maintenance(string action,IEnumerable<string> options,Action<int,string> done,bool assistantRequest=false) {Run(executable,new[]{"--maintain",action,"--install-path",root}.Concat(options),done,false,null,assistantRequest);}
        internal string WorkspaceConfiguration() {
            string inherited=Environment.GetEnvironmentVariable("OPENCODE_CONFIG_CONTENT");
            Dictionary<string,object> config;
            try {config=String.IsNullOrWhiteSpace(inherited)?new Dictionary<string,object>():json.Deserialize<Dictionary<string,object>>(inherited);}
            catch(ArgumentException) {throw new ArgumentException("The inherited OpenCode inline configuration is invalid JSON.");}
            if(config==null) throw new ArgumentException("The inherited OpenCode inline configuration must be an object.");
            var agents=ConfigurationObject(config,"agent");
            foreach(string name in new[]{"ps-read","ps-write"}) {
                var agent=ConfigurationObject(agents,name);object value;
                Dictionary<string,object> permissions;
                if(agent.TryGetValue("permission",out value) && value is string) permissions=new Dictionary<string,object>{{"*",value}};
                else permissions=ConfigurationObject(agent,"permission");
                var directories=new Dictionary<string,object>{{"*","ask"}};
                if(permissions.TryGetValue("external_directory",out value)) {
                    if(value is string) directories["*"]=value;
                    else if(value is Dictionary<string,object>) foreach(var rule in (Dictionary<string,object>)value) directories[rule.Key]=rule.Value;
                    else throw new ArgumentException("The inherited OpenCode directory permissions are invalid.");
                }
                foreach(string folder in preferences.Workspaces) {
                    string path=GuiPreferences.Normalize(folder);
                    // Windows OpenCode versions have used both native and
                    // slash-normalised paths. Keep each grant at a separator
                    // boundary so a similarly named sibling is not included.
                    foreach(string rootPath in new[]{path,path.Replace('\\','/')}.Distinct(StringComparer.Ordinal)) {
                        string separator=rootPath.Contains("\\")?"\\":"/";
                        foreach(string pattern in new[]{rootPath,rootPath.TrimEnd('\\','/')+separator+"**"}) {directories.Remove(pattern);directories.Add(pattern,"allow");}
                    }
                }
                permissions["external_directory"]=directories;agent["permission"]=permissions;
            }
            return json.Serialize(config);
        }
        private static Dictionary<string,object> ConfigurationObject(Dictionary<string,object> parent,string name) {
            object value;if(!parent.TryGetValue(name,out value)) {value=new Dictionary<string,object>();parent[name]=value;}
            var result=value as Dictionary<string,object>;if(result==null) throw new ArgumentException("The inherited OpenCode "+name+" configuration must be an object.");return result;
        }
        private string RequestConfiguration(bool localRequest) {
            var config=json.Deserialize<Dictionary<string,object>>(WorkspaceConfiguration());
            if(localRequest) {
                var providers=ConfigurationObject(config,"provider");var ollama=ConfigurationObject(providers,"ollama");var models=ConfigurationObject(ollama,"models");
                // Ollama's installed-model list can contain models added after
                // WHAS setup. Expose them for this request without rewriting
                // provider settings or replacing existing model definitions.
                foreach(string name in ((ComboBox)settings["local.model"]).Items) if(!String.IsNullOrWhiteSpace(name) && !models.ContainsKey(name)) models[name]=new Dictionary<string,object>{{"name",name}};
            }
            return json.Serialize(config);
        }
        internal bool PresentationRebuilding;
        internal TabControl PresentationPages { get { return tabs; } }
        internal bool IsBusy { get { return operationPending; } }
        internal bool IsAssistantRequestRunning { get { return operationPending && operationIsAssistantRequest; } }
        internal string SavedProcessing {get{return savedLocation??Convert.ToString(defaultLocation.SelectedItem);}}
        internal string PresentationStatus { get { return status.Text; } }
        internal TextBox PresentationOutput { get { return output; } }
        internal Button PresentationCancel { get { return cancel; } }
        internal bool PresentationDetails { get { return details.Visible; } }
        internal void PreparePresentation(bool render) { rendering=render; PrepareRender(this); }
        internal void LoadPresentationSettings() { if(!setup) {try {ReloadSettings();}catch(Exception error) {status.Text=error.Message;}} }
        internal void PreparePage(string name) {
            if(rendering || IsBusy) return;
            if(name=="Models & engines" && local.Checked && !setupModelsDiscovered) {RefreshSetupModels();return;}
            if(name=="Voice") {try {RefreshVoice();}catch(Exception error){status.Text="Failed: "+error.Message;voiceSupport.Text="Could not load speech inventory. Check the active installation, then refresh.";}}
        }
        private bool setupModelsDiscovered,setupModelSelectionEdited,applyingSetupModels;
        private readonly HashSet<string> installedSetupModels=new HashSet<string>(StringComparer.Ordinal);
        internal string SetupModelNotice="Choose at least one model for Local AI. Selected missing models are downloaded when you apply features.";
        internal string SetupModelStatus(string name) {return installedSetupModels.Contains(name)?"Installed · Reuse":"Download if missing";}
        internal static string[] ParseOllamaModels(string text) {
            return text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).Select(x=>Regex.Split(x.Trim(),"\\s+")[0]).Where(x=>x!="NAME" && Regex.IsMatch(x,"^[A-Za-z0-9][A-Za-z0-9._/:-]*$")).Distinct().ToArray();
        }
        private void ApplySetupModels(string[] names) {
            applyingSetupModels=true;
            try {
                installedSetupModels.Clear();foreach(string name in names) {installedSetupModels.Add(name);if(!models.Items.Contains(name))models.Items.Add(name,false);}
                if(!setupModelSelectionEdited && MaintenanceFeature==null) {
                    for(int i=0;i<models.Items.Count;i++)models.SetItemChecked(i,false);
                    string chosen=names.Length>0?names[0]:"qwen2.5:1.5b";
                    models.SetItemChecked(models.Items.IndexOf(chosen),true);UpdateModels();defaultModel.SelectedItem=chosen;
                }
                SetupModelNotice=names.Length==0?"No installed models found. qwen2.5:1.5b is the small starter option (about 1 GB). Selected missing models will be downloaded when you apply features.":"Installed models are marked Reuse. Select at least one model for Local AI; only missing models are downloaded when you apply features.";
                setupModelsDiscovered=true;
            } finally {applyingSetupModels=false;}
        }
        internal void RefreshSetupModels() {
            if(IsBusy) throw new InvalidOperationException("Wait for the current operation.");
            if(!local.Checked) {SetupModelNotice="Local AI is off. No local models will be downloaded.";return;}
            string ollama=GuiProcess.FindApplication("ollama.exe");
            if(ollama==null) {SetupModelNotice="Ollama is not installed. qwen2.5:1.5b is the small starter option (about 1 GB). Install Ollama under Prerequisites; selected missing models are downloaded when you apply features.";return;}
            SetupModelNotice="Checking installed Ollama models…";
            Run(ollama,new[]{"list"},delegate(int code,string text) {
                if(code==0)ApplySetupModels(ParseOllamaModels(text));
                else SetupModelNotice="Could not check installed models. Your selection is retained. Start Ollama, then select Refresh available models. Missing selected models will be downloaded when you apply features.";
            },true);
        }
        internal void InvokePresentationAction(Button button) { if(button.Enabled) InvokeOnClick(button,EventArgs.Empty); }
        internal void InvokePresentationLink(LinkLabel link) {
            string uri=link.Tag as string; Uri parsed;
            if(!Uri.TryCreate(uri,UriKind.Absolute,out parsed) || (parsed.Scheme!="https" && parsed.Scheme!="http")) throw new InvalidOperationException("Invalid application link.");
            Process.Start(new ProcessStartInfo(uri){UseShellExecute=true});
        }
        internal Control PresentationField(string name) {
            switch(name) {
                case "destination": return destination; case "cloud": return cloud; case "local": return local; case "voice": return voice;

                case "defaultLocation": return defaultLocation; case "models": return models; case "engines": return engines;
                case "defaultModel": return defaultModel; case "defaultEngine": return defaultEngine; case "checkGrid": return checkGrid;
                case "action": return action; case "route": return route; case "speak": return speak;
                case "prompt": return prompt; case "conversation": return conversation;
                case "voiceEngine":return voiceEngine;case "voiceName":return voiceName;case "voiceSupport":return voiceSupport;
                case "voiceReferenceName":return voiceReferenceName;case "voiceReferencePath":return voiceReferencePath;case "voiceImportNotice":return voiceImportNotice;case "voiceSelectionNotice":return voiceSelectionNotice;case "voiceMakeDefault":return voiceMakeDefault;
            }
            throw new ArgumentException("Unknown presentation field.");
        }
        private bool setup;
        private readonly string catalog;
        private int featureTab;
        private readonly string executable;
        private string root;
        private readonly TabControl tabs=new TabControl();
        private readonly ListBox navigation=new ListBox();
        private readonly Panel details=new Panel();
        private readonly Button detailsToggle=new Button();
        private readonly TextBox output=new TextBox();
        private readonly Label status=new Label();
        private readonly ProgressBar progress=new ProgressBar();
        private readonly Button cancel=new Button();
        private readonly JavaScriptSerializer json=new JavaScriptSerializer();
        private GuiProcess operation;
        private bool operationPending;
        private bool operationIsAssistantRequest;
        private readonly List<Control> actions=new List<Control>();
        private TextBox destination=new TextBox();
        private CheckBox cloud=new CheckBox(), local=new CheckBox(), voice=new CheckBox();
        private CheckedListBox engines=new CheckedListBox(), models=new CheckedListBox();
        private ComboBox defaultEngine=new ComboBox(), defaultModel=new ComboBox();
        private ComboBox defaultLocation;
        private readonly Dictionary<string,ComboBox> setupDevices=new Dictionary<string,ComboBox>();
        internal ComboBox SetupDevice(string engine) {return setupDevices[engine];}
        private readonly List<string> engineIds=new List<string>();
        private readonly Dictionary<string,string[]> setupEngineDevices=new Dictionary<string,string[]>();
        private CheckBox retainModels=new CheckBox();
        private DataGridView checkGrid;
        private bool checkPassed;
        private bool rendering;
        private string checkedSelection;
        private TextBox prompt, session, conversation;
        private TextBox workspace;
        private ComboBox action, route, runtime;
        private CheckBox speak;
        private readonly Dictionary<string,Control> settings=new Dictionary<string,Control>();
        private int settingsChanging;
        private bool sharedSettingsLoaded;
        private readonly Dictionary<string,string> savedSettingValues=new Dictionary<string,string>();
        private Label modelNotice;
        private ComboBox voiceEngine, voiceName;
        private Button voiceAdd, voiceRemove;
        private Button voiceChoose,voiceDefault;
        private CheckBox voiceMakeDefault;
        private TextBox voiceReferenceName,voiceReferencePath;
        private Label voiceImportNotice,voiceSelectionNotice;
        private string voiceImportError="";
        private Label voiceSupport=new Label();
        private bool voiceInventoryLoaded;
        private readonly List<Button> installedVoiceActions=new List<Button>();
        private Button voiceInstall;
        private readonly Dictionary<string,Dictionary<string,object>> voiceInventory=new Dictionary<string,Dictionary<string,object>>();
        private readonly Dictionary<string,bool> voiceDeviceChoices=new Dictionary<string,bool>();
        private string savedEngine="", savedRuntime="", savedVoice="default";
        private string savedLocation;
        private bool savedLocalEnabled=true;
        private OllamaChatRequest localChatRequest;
        private Uri localChatEndpoint=new Uri("http://127.0.0.1:11434/api/chat");
        private readonly List<Dictionary<string,string>> localConversation=new List<Dictionary<string,string>>();
        private string localConversationModel;
        private int localContextRevision;
        private readonly Dictionary<string,string> savedVoices=new Dictionary<string,string>();
        private readonly GuiPreferences preferences;
        private ComboBox workspaceChoices;
        private Label workspaceNotice;
        private bool refreshingWorkspaces;

        public WhasWindow(bool isSetup,string path,string setupCatalog,string initialRoot=null):this(isSetup,path,setupCatalog,initialRoot,null) {}
        public WhasWindow(bool isSetup,string path,string setupCatalog,string initialRoot,string preferencesPath) {
            preferences=new GuiPreferences(preferencesPath);
            setup=isSetup; executable=path; catalog=setupCatalog; root=initialRoot==null?ResolveRoot(path):Path.GetFullPath(initialRoot);
            Text="WHAS";
            Font=new Font("Segoe UI",10); AutoScaleMode=AutoScaleMode.Dpi;
            Size=new Size(1120,860); MinimumSize=new Size(960,720); StartPosition=FormStartPosition.CenterScreen;
            BackColor=Color.FromArgb(243,245,248);
            var heading=new Label {Text="WHAS   /   Windows Hybrid Agentic Stack", Dock=DockStyle.Top,Height=76,Padding=new Padding(24,22,0,0),Font=new Font("Segoe UI",17,FontStyle.Bold),ForeColor=Color.FromArgb(25,36,55)};
            tabs.Dock=DockStyle.Fill; tabs.Appearance=TabAppearance.FlatButtons; tabs.SizeMode=TabSizeMode.Fixed; tabs.ItemSize=new Size(1,1);
            navigation.Dock=DockStyle.Left; navigation.Width=200; navigation.BorderStyle=BorderStyle.None;
            navigation.BackColor=BackColor; navigation.DrawMode=DrawMode.OwnerDrawFixed; navigation.ItemHeight=44;
            navigation.AccessibleName="Application navigation";
            navigation.DrawItem+=delegate(object sender,DrawItemEventArgs e) {
                if(e.Index<0) return;
                bool selected=(e.State&DrawItemState.Selected)!=0;
                using(var brush=new SolidBrush(selected?Color.FromArgb(222,233,250):BackColor)) e.Graphics.FillRectangle(brush,e.Bounds);
                if(selected) using(var brush=new SolidBrush(Color.FromArgb(0,95,184))) e.Graphics.FillRectangle(brush,e.Bounds.Left,e.Bounds.Top+10,3,e.Bounds.Height-20);
                TextRenderer.DrawText(e.Graphics,Convert.ToString(navigation.Items[e.Index]),Font,new Rectangle(e.Bounds.Left+20,e.Bounds.Top,e.Bounds.Width-24,e.Bounds.Height),Color.FromArgb(25,36,55),TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
                e.DrawFocusRectangle();
            };
            navigation.SelectedIndexChanged+=delegate { if(navigation.SelectedIndex>=0 && navigation.SelectedIndex<tabs.TabPages.Count) tabs.SelectedIndex=navigation.SelectedIndex; };
            tabs.SelectedIndexChanged+=delegate { if(tabs.SelectedIndex>=0 && tabs.SelectedIndex<navigation.Items.Count) navigation.SelectedIndex=tabs.SelectedIndex; };
            output.Multiline=true; output.ReadOnly=true; output.ScrollBars=ScrollBars.Both; output.WordWrap=false;
            output.Dock=DockStyle.Fill; output.Font=new Font("Consolas",9); output.BackColor=Color.White; output.BorderStyle=BorderStyle.None;
            details.Dock=DockStyle.Bottom; details.Height=128; details.Padding=new Padding(24,8,24,8); details.Visible=false; details.Controls.Add(output);
            var footer=new TableLayoutPanel {Dock=DockStyle.Bottom,Height=76,Padding=new Padding(24,10,24,12),ColumnCount=3,RowCount=2};
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,140)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,160));
            footer.RowStyles.Add(new RowStyle(SizeType.Absolute,8)); footer.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            progress.Dock=DockStyle.Fill; progress.Style=ProgressBarStyle.Continuous; progress.Visible=false; footer.Controls.Add(progress,0,0); footer.SetColumnSpan(progress,3);
            status.Dock=DockStyle.Fill; status.TextAlign=ContentAlignment.MiddleLeft; status.AutoEllipsis=true; status.Text="Ready";
            detailsToggle.Text="Show details"; detailsToggle.Dock=DockStyle.Fill; StyleButton(detailsToggle,false);
            detailsToggle.Click+=delegate { details.Visible=!details.Visible; detailsToggle.Text=details.Visible?"Hide details":"Show details"; };
            cancel.Text="Cancel operation"; cancel.Dock=DockStyle.Fill; cancel.Enabled=false; StyleButton(cancel,false);
            cancel.Click+=delegate {try {if(localChatRequest!=null) {localChatRequest.Cancel();status.Text="Cancelling reply…";}else if(operation!=null) {operation.Cancel();status.Text="Cancellation requested; changes already made may need cleanup.";}}catch(Exception e){Error(e);}};
            Disposed+=delegate {if(localChatRequest!=null) localChatRequest.Cancel();};
            footer.Controls.Add(status,0,1); footer.Controls.Add(detailsToggle,1,1); footer.Controls.Add(cancel,2,1);
            Controls.Add(tabs); Controls.Add(navigation); Controls.Add(details); Controls.Add(footer); Controls.Add(heading);
            BuildPages();
            Shown+=delegate { if(!rendering && !setup) { try { ReloadSettings(); } catch(Exception e) { status.Text=e.Message; } } };
            FormClosing+=delegate(object sender,FormClosingEventArgs e) {
                if (IsBusy) { e.Cancel=true; MessageBox.Show(DialogOwner??this,IsAssistantRequestRunning?"A request is running. Cancel it and wait for completion before closing.":"An operation is running. Wait for completion before closing.","Operation in progress"); }
            };
            FormClosed+=delegate { if (operation != null) operation.Dispose(); };
        }
        public static bool IsConfigured(string root) {
            string record=Path.Combine(root,".whas-installation.json");
            if(!File.Exists(record)) return false;
            // Private Python environments legitimately track tens of thousands
            // of files; their ownership records exceed the serializer's 2 MB default.
            try { var state=new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue}.Deserialize<Dictionary<string,object>>(File.ReadAllText(record)); return state!=null && state.ContainsKey("Status") && Convert.ToString(state["Status"])=="Installed" && File.Exists(Path.Combine(root,"config","defaults.json")); }
            catch(ArgumentException) { return false; } catch(IOException) { return false; }
        }
        private void BuildPages() {
            sharedSettingsLoaded=false;savedSettingValues.Clear();setupReviewedSelection=null;SetupReview.Clear();
            PresentationRebuilding=true;
            tabs.SuspendLayout();
            try {
                foreach(TabPage page in tabs.TabPages.Cast<TabPage>().ToArray()) { tabs.TabPages.Remove(page); page.Dispose(); }
                navigation.Items.Clear(); actions.Clear(); settings.Clear(); voiceInventory.Clear();voiceDeviceChoices.Clear(); engineIds.Clear();installedVoiceActions.Clear();voiceInventoryLoaded=false;
                workspace=null; voiceAdd=null; voiceRemove=null; voiceSupport=new Label(); checkPassed=false; checkedSelection=null;savedLocation=null;MaintenanceFeature=null;reviewedSelection=null;
                destination=new TextBox(); cloud=new CheckBox(); local=new CheckBox(); voice=new CheckBox();
                models=new CheckedListBox(); engines=new CheckedListBox(); defaultModel=new ComboBox(); defaultEngine=new ComboBox(); retainModels=new CheckBox();
                if(!setup) BuildUsage();
                featureTab=tabs.TabPages.Count;
                BuildSetup(catalog??"[]");
                foreach(TabPage page in tabs.TabPages) navigation.Items.Add(page.Text);
                tabs.SelectedIndex=0;
                navigation.SelectedIndex=0;
                status.Text=setup?(HasRemovalTarget?"Review the existing installation to repair it or use Remove WHAS.":"Choose features to get started."):"Ready";
            } finally { tabs.ResumeLayout(); PresentationRebuilding=false; }
            if(PresentationChanged!=null) PresentationChanged();
        }
        internal static string ResolveRoot(string path) {
            string adjacent=Path.GetDirectoryName(path);
            if (File.Exists(Path.Combine(adjacent,".whas-installation.json"))) return adjacent;
            string marker=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".windows-hybrid-agentic-stack","bin","install-root.txt");
            if (File.Exists(marker)) return File.ReadAllText(marker).Trim();
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"AI","WindowsHybridAgenticStack");
        }
        private FlowLayoutPanel Page(string name) {
            TabPage page=new TabPage(name); page.Padding=new Padding(24,16,24,16); page.BackColor=Color.White;
            FlowLayoutPanel flow=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true};
            flow.BackColor=Color.White;
            page.Controls.Add(flow); tabs.TabPages.Add(page);
            flow.Controls.Add(new Label {Text=name,UseMnemonic=false,AutoSize=true,Font=new Font("Segoe UI",22,FontStyle.Bold),ForeColor=Color.FromArgb(25,36,55),Margin=new Padding(0,0,0,16)});
            flow.ClientSizeChanged+=delegate { FitPage(flow); }; return flow;
        }
        private void FitPage(FlowLayoutPanel page) {
            if(page.ClientSize.Width<100) return;
            int width=Math.Max(100,page.ClientSize.Width-SystemInformation.VerticalScrollBarWidth-8);
            foreach(Control control in page.Controls) {
                if(control is Label && !control.AutoSize) { control.Width=width; control.Height=TextRenderer.MeasureText(control.Text,control.Font,new Size(width,0),TextFormatFlags.WordBreak).Height+8; }
                else if(control is DataGridView || control is TableLayoutPanel) control.Width=width;
                else if(!control.AutoSize) { if(control.Tag==null) control.Tag=control.Width; control.Width=Math.Min((int)control.Tag,width); }
            }
        }
        private void TextLine(FlowLayoutPanel page,string text,int height) { page.Controls.Add(new Label {Text=text,UseMnemonic=false,Width=720,Height=height,Margin=new Padding(0,4,0,8),ForeColor=Color.FromArgb(60,70,85)}); }
        private void Section(FlowLayoutPanel page,string text) {page.Controls.Add(new Label {Text=text,AutoSize=true,Tag="section-heading",Font=new Font("Segoe UI",12,FontStyle.Bold),Margin=new Padding(0,16,0,8)});}
        private FlowLayoutPanel OptionCard(TableLayoutPanel row,string title,int column) {
            var card=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new Padding(16),Margin=new Padding(column==0?0:8,0,column==0?8:0,0),BackColor=Color.FromArgb(246,248,251)};
            card.Controls.Add(new Label {Text=title,AutoSize=true,Font=new Font("Segoe UI",12,FontStyle.Bold),Margin=new Padding(0,0,0,12)});
            card.ClientSizeChanged+=delegate {FitPage(card);}; row.Controls.Add(card,column,0); return card;
        }
        private static void StyleButton(Button button,bool primary) {
            button.FlatStyle=FlatStyle.Flat; button.FlatAppearance.BorderSize=1;
            button.FlatAppearance.BorderColor=primary?Color.FromArgb(0,95,184):Color.FromArgb(185,194,207);
            button.BackColor=primary?Color.FromArgb(0,95,184):Color.White;
            button.ForeColor=primary?Color.White:Color.FromArgb(25,36,55);
            button.Padding=new Padding(12,4,12,4); button.Cursor=Cursors.Hand; button.UseVisualStyleBackColor=false;
        }
        private Button Button(FlowLayoutPanel page,string text,Action click) {
            Button button=new Button {Text=text,AutoSize=true,MinimumSize=new Size(180,38),Margin=new Padding(0,8,10,6)};
            StyleButton(button,text.StartsWith("Next:") || text=="Apply selected features" || text=="Check again");
            button.Click+=delegate { try { click(); } catch(Exception e) { Error(e); } }; page.Controls.Add(button); actions.Add(button); return button;
        }
        private ComboBox Choice(FlowLayoutPanel page,string label,IEnumerable<string> choices) {
            TextLine(page,label,24); var box=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList,Width=400};
            box.Items.AddRange(choices.Cast<object>().ToArray()); if(box.Items.Count>0) box.SelectedIndex=0; page.Controls.Add(box); return box;
        }
        private void Error(Exception error) { status.Text="Failed: "+error.Message; MessageBox.Show(DialogOwner??this,error.Message,"WHAS",MessageBoxButtons.OK,MessageBoxIcon.Error); }
        private void Ui(Action work) { try { if (!IsDisposed && IsHandleCreated) BeginInvoke(work); } catch(InvalidOperationException) {} }
        private void Run(string file,IEnumerable<string> arguments,Action<int,string> completed,bool optionalDiscovery=false,IDictionary<string,string> environment=null,bool assistantRequest=false) {
            if (IsBusy) throw new InvalidOperationException("Wait for the current operation.");
            var requested=arguments.ToArray();bool requestUsesWorkspace=requested.Length>0 && Regex.IsMatch(requested[0],"^(ask|perform|chat)[lc]?$");
            bool taskRequest=requested.Length>0 && Regex.IsMatch(requested[0],"^perform[lc]?$");
            if(taskRequest && (workspace==null || !Directory.Exists(workspace.Text))) throw new DirectoryNotFoundException("Select an existing starting folder under Configuration > Workspaces.");
            string selectedRuntime=runtime==null?"":Convert.ToString(runtime.SelectedItem);
            if(taskRequest && (selectedRuntime=="opencode" || (selectedRuntime=="default" && savedRuntime=="opencode"))) {
                environment=environment==null?new Dictionary<string,string>():new Dictionary<string,string>(environment);
                bool localRequest=requested[0].EndsWith("l",StringComparison.Ordinal) || requested.Contains("--local") || (!requested[0].EndsWith("c",StringComparison.Ordinal) && !requested.Contains("--cloud") && SavedProcessing=="local");
                environment["OPENCODE_CONFIG_CONTENT"]=RequestConfiguration(localRequest);
            }
            if (operation != null) operation.Dispose();
            foreach(Control button in actions) button.Enabled=false;
            string request=String.Join(" ",requested.Take(3));
            progress.Visible=true; progress.Style=ProgressBarStyle.Marquee; status.Text=request=="configure --show"?"Loading shared configuration…":request=="agent list"?"Checking available runtimes…":request=="tts inventory"?"Loading speech engines and voices…":request.StartsWith("model catalog")?"Loading "+(request.EndsWith("--cloud")?"cloud":"local")+" model choices…":request.StartsWith("tts say")?"Preparing speech…":"Starting operation…"; output.Clear();
            if(optionalDiscovery) status.Text=request=="models"?"Loading cloud model choices…":"Loading local model choices…";
            if(requested.Length>1 && requested[0]=="--maintain" && requested[1]=="speak") status.Text="Preparing speech…";
            var result=new StringBuilder(); operation=new GuiProcess();operationIsAssistantRequest=requestUsesWorkspace || assistantRequest;operationPending=true;
            try {
                operation.Start(file,requested,delegate(string line,bool error) {
                    Ui(delegate {
                        if (line.StartsWith("WHAS_EVENT ",StringComparison.Ordinal)) {
                            try {
                                var frame=json.Deserialize<Dictionary<string,object>>(line.Substring(11));
                                if(Convert.ToString(frame["type"])=="check" && checkGrid!=null) {
                                    int row=checkGrid.Rows.Add(frame["component"],(bool)frame["required"]?"Yes":"No",frame["status"],frame["details"]);
                                    string value=Convert.ToString(frame["status"]); checkGrid.Rows[row].Cells[2].Style.ForeColor=value=="PASS"?Color.DarkGreen:value=="FAIL"?Color.Firebrick:value=="WARN"?Color.DarkGoldenrod:Color.SteelBlue;
                                } else if(frame.ContainsKey("phase")) status.Text=Convert.ToString(frame["phase"])+" — "+frame["elapsedSeconds"]+"s";
                            } catch { }
                        } else { output.AppendText(line+Environment.NewLine); if(!error) result.AppendLine(line); }
                    });
                },delegate(int code) { Ui(delegate {
                    operationPending=false;
                    progress.Style=ProgressBarStyle.Continuous; progress.Visible=false; cancel.Enabled=false;
                    foreach(Control button in actions) button.Enabled=true;
                    status.Text=code==0 ? "Completed" : optionalDiscovery?"Model choices could not load. Check Configuration or the activity log.":"Stopped or failed (exit "+code+"). Review details; changes may remain.";
                    if(code!=0 && !optionalDiscovery) { details.Visible=true; detailsToggle.Text="Hide details";output.AppendText("Operation failed (exit "+code+"). "+(output.Text.Length==0?"The command returned no diagnostic output.":"See command output above.")+Environment.NewLine); }
                    try {if(completed != null) completed(code,result.ToString());}catch(Exception error){status.Text="Failed: "+error.Message;output.AppendText(error.Message+Environment.NewLine);}
                    UpdateVoiceActions();
                }); },environment,workspace!=null && Directory.Exists(workspace.Text)?Path.GetFullPath(workspace.Text):null);
                cancel.Enabled=operation.CanCancel && operationIsAssistantRequest;
            } catch {operationPending=false;foreach(Control button in actions) button.Enabled=true; progress.Style=ProgressBarStyle.Continuous; progress.Visible=false; cancel.Enabled=false; throw; }
        }
        private string Cli() {
            string bin=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".windows-hybrid-agentic-stack","bin");
            string marker=Path.Combine(bin,"install-root.txt");
            if (!File.Exists(marker) || !String.Equals(File.ReadAllText(marker).Trim(),root,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("This installation is not the active command registration. Open setup to inspect the selected installation.");
            return Path.Combine(bin,"whas.exe");
        }
        private void Command(IEnumerable<string> args,Action<int,string> done) { Run(Cli(),args,done); }
        private void BuildSetup(string catalog) {
            var select=Page("Features");
            TextLine(select,"Add features to WHAS. This selection adds or repairs components; unticking does not delete existing features. Remove engines and runtimes in their management tabs, or remove all on the Remove WHAS tab.",82);
            foreach(var pair in new[]{Tuple.Create(cloud,"Cloud agents"),Tuple.Create(local,"Local agents (Ollama)"),Tuple.Create(voice,"Speech output")}) {
                pair.Item1.Text=pair.Item2; pair.Item1.Width=500; pair.Item1.Checked=setup; select.Controls.Add(pair.Item1);
            }
            Button(select,"Select all features",delegate { cloud.Checked=local.Checked=voice.Checked=true; });
            Button(select,"Select none (shared app only)",delegate { cloud.Checked=local.Checked=voice.Checked=false; });
            TextLine(select,"Installation directory",24); destination.Text=root; destination.Width=760; select.Controls.Add(destination);
            Button(select,"Choose folder…",delegate {string folder=FolderPicker.Select(DialogOwner??this,destination.Text,"Choose installation folder");if(folder!=null) destination.Text=folder;});
            defaultLocation=Choice(select,"Default processing",new[]{"cloud","local"});
            TextLine(select,"OpenCode is required for the standard cloud/local workflow. Install missing prerequisites before applying features. Provider sign-in is managed by OpenCode.",78);
            Link(select,"Installation and account setup guide","https://github.com/thestonefox/windows-hybrid-agentic-stack/blob/main/docs/installation.md");
            LoadDefaultLocation();
            RefreshFeatureStatus();destination.TextChanged+=delegate {LoadDefaultLocation();RefreshFeatureStatus();};
            Button(select,"Next: models and engines",delegate { tabs.SelectedIndex=featureTab+1; });
            var components=Page("Models & engines");
            TextLine(components,"Choose what to download, then set a default for each feature. Existing models are reused.",40);
            var choices=new TableLayoutPanel {Width=760,Height=400,ColumnCount=2,RowCount=1,Margin=new Padding(0,8,0,8)};
            choices.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50)); choices.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
            components.Controls.Add(choices);
            var modelOptions=OptionCard(choices,"Local models",0); var engineOptions=OptionCard(choices,"Speech engines",1);
            TextLine(modelOptions,"Select Ollama downloads. Memory and download sizes vary by model.",48);
            models.Width=550; models.Height=78; models.CheckOnClick=true;
            setupModelsDiscovered=setupModelSelectionEdited=applyingSetupModels=false;installedSetupModels.Clear();
            SetupModelNotice="qwen2.5:1.5b is the small starter option (about 1 GB). Choose at least one model for Local AI; missing selected models are downloaded when you apply features.";
            models.Items.Add("qwen2.5:1.5b",true); models.Items.Add("qwen3:8b",false); modelOptions.Controls.Add(models);
            TextLine(modelOptions,"Additional model name (optional)",24);
            var custom=new TextBox {Width=550,AccessibleName="Additional Ollama model name"}; modelOptions.Controls.Add(custom);
            Button(modelOptions,"Add model name",delegate { string value=custom.Text.Trim(); if(!Regex.IsMatch(value,"^[A-Za-z0-9][A-Za-z0-9._/:-]*$")) throw new ArgumentException("Enter a valid Ollama model name."); setupModelSelectionEdited=true;if(!models.Items.Contains(value)) models.Items.Add(value,true);else models.SetItemChecked(models.Items.IndexOf(value),true); UpdateModels(); });
            TextLine(modelOptions,"Default local model",24);
            defaultModel.AccessibleName="Default local model"; defaultModel.Width=400; defaultModel.DropDownStyle=ComboBoxStyle.DropDownList; modelOptions.Controls.Add(defaultModel);
            models.ItemCheck+=delegate {if(!applyingSetupModels)setupModelSelectionEdited=true; BeginInvoke((Action)UpdateModels); }; UpdateModels();
            TextLine(engineOptions,"The default starts on demand. You can switch between installed engines. Review licences before downloading.",70);
            engines.Width=700; engines.Height=84; engines.CheckOnClick=true;
            var licences=new List<string>();
            setupEngineDevices.Clear();setupDevices.Clear();
            foreach(Dictionary<string,object> engine in json.Deserialize<object[]>(catalog)) {
                string id=Convert.ToString(engine["id"]); engineIds.Add(id);
                setupEngineDevices[id]=((IEnumerable)engine["devices"]).Cast<object>().Select(Convert.ToString).ToArray();
                var deviceChoice=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList};deviceChoice.Items.AddRange(setupEngineDevices[id].Length==1?setupEngineDevices[id]:new[]{"cpu","auto"});deviceChoice.SelectedItem=setupEngineDevices[id].Length==1?setupEngineDevices[id][0]:"auto";setupDevices[id]=deviceChoice;
                engines.Items.Add(Convert.ToString(engine["name"]),id=="chatterbox-turbo");
                licences.Add(Convert.ToString(engine["license"]));
            }
            engineOptions.Controls.Add(engines);
            var licence=new Label {Width=320,Height=70,Text="Select an engine to review its licence.",Margin=new Padding(0,8,0,8)};
            engineOptions.Controls.Add(licence);
            engines.SelectedIndexChanged+=delegate {if(engines.SelectedIndex>=0) {licence.Text="Licence: "+licences[engines.SelectedIndex]; FitPage(engineOptions);}};
            if(engines.Items.Count>0) engines.SelectedIndex=0;
            TextLine(engineOptions,"Default speech engine",24);
            defaultEngine.AccessibleName="Default speech engine"; defaultEngine.Width=400; defaultEngine.DropDownStyle=ComboBoxStyle.DropDownList; engineOptions.Controls.Add(defaultEngine);
            engines.ItemCheck+=delegate {BeginInvoke((Action)UpdateEngines);};UpdateEngines();
            Button(components,"Next: prerequisite checks",delegate { tabs.SelectedIndex=featureTab+2; });
            var checks=Page("Prerequisites");
            TextLine(checks,"Checks are read-only. Install missing external prerequisites yourself using the links below, then select Check again. A passing check is required before installation.",62);
            checkGrid=new DataGridView {Width=720,Height=240,ReadOnly=true,AllowUserToAddRows=false,AllowUserToDeleteRows=false,RowHeadersVisible=false,AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill,BackgroundColor=Color.White,BorderStyle=BorderStyle.None,CellBorderStyle=DataGridViewCellBorderStyle.SingleHorizontal,EnableHeadersVisualStyles=false};
            checkGrid.ColumnHeadersDefaultCellStyle.BackColor=Color.FromArgb(240,243,248); checkGrid.ColumnHeadersHeight=36; checkGrid.RowTemplate.Height=32;
            foreach(string title in new[]{"Component","Required","Status","Details"}) checkGrid.Columns.Add(title,title); checkGrid.Columns[3].FillWeight=300; checks.Controls.Add(checkGrid);
            Button(checks,"Check again",CheckPrerequisites);
            var checkedPage=checks.Parent;
            tabs.SelectedIndexChanged+=delegate { if(!rendering && tabs.SelectedTab==checkedPage && checkedSelection==null && !IsBusy) { try { CheckPrerequisites(); } catch(Exception error) { Error(error); } } };
            TextLine(checks,"Install missing prerequisites using the official links:",24);
            var downloads=new FlowLayoutPanel {Width=720,Height=80,FlowDirection=FlowDirection.LeftToRight,WrapContents=true}; checks.Controls.Add(downloads);
            Link(downloads,"Python 3.11","https://www.python.org/downloads/release/python-3119/");
            Link(downloads,"Visual C++ x64 runtime","https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist");
            Link(downloads,"NVIDIA drivers (optional CUDA)","https://www.nvidia.com/Download/index.aspx");
            Link(downloads,"OpenCode installation","https://opencode.ai/docs/"); Link(downloads,"Ollama installation","https://ollama.com/download/windows");
            Button(checks,"Next: review and apply",delegate {tabs.SelectedIndex=featureTab+3;});
            var install=Page("Apply features");
            TextLine(install,"Review prints the exact backend plan without changes. Installation downloads the selected dependencies/models and registers both command-line and graphical interfaces.",64);
            Button(install,"Review selection",ReviewSetup);
            Button(install,"Apply selected features",delegate {
                var selection=Selection(); if(!checkPassed || checkedSelection!=String.Join("\n",selection)) throw new InvalidOperationException("Run prerequisite checks for the current selection first.");
                if(!SetupReviewed) throw new InvalidOperationException("Review the current selection before applying features.");
                if(MessageBox.Show(DialogOwner??this,"Install the reviewed selection and its downloads?","Confirm installation",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes) return;
                Run(executable,new[]{"--install","--yes"}.Concat(selection),delegate(int code,string text) { if(code==0) { root=Path.GetFullPath(destination.Text); setup=false; BuildPages(); ReloadSettings(); } });
            });
            var uninstall=Page("Remove WHAS");
            TextLine(uninstall,"Preview first: unchanged owned files and installer-created models are removed; personal voices, agent data, modified files and external prerequisites are preserved.",82);
            retainModels.Text="Retain installer-created Ollama models"; retainModels.Width=600; uninstall.Controls.Add(retainModels);
            Button(uninstall,"Preview removal",delegate { details.Visible=true; detailsToggle.Text="Hide details"; Run(executable,Removal(false),null); });
            Button(uninstall,"Uninstall…",delegate {
                GuiMaintenance.CheckUnlockedGui(destination.Text);
                if(MessageBox.Show(DialogOwner??this,"Remove this tracked installation? Personal/modified files are preserved. Review the preview before proceeding.","Confirm uninstall",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes) return;
                string removalRoot=Path.GetFullPath(destination.Text);
                Run(executable,Removal(true),delegate(int code,string text) { if(code==0) CompleteRemoval(removalRoot); });
            });
        }
        private void CheckPrerequisites() {
            var selection=Selection(); checkPassed=false; checkGrid.Rows.Clear(); checkedSelection=String.Join("\n",selection);
            Run(executable,new[]{"--check"}.Concat(selection),delegate(int code,string text) {
                checkPassed=code==0 && checkGrid.Rows.Count>0;
                status.Text=checkPassed?(setup?"Prerequisites passed. Select Go to Apply Features.":"Readiness passed. Review the changes below, then apply."):"Prerequisite checks need attention. Review the results and details.";
            });
        }
        private void Link(FlowLayoutPanel page,string title,string uri) {
            var link=new LinkLabel {Text=title,Tag=uri,AutoSize=true,Margin=new Padding(0,5,20,5)}; link.LinkClicked+=delegate { Process.Start(new ProcessStartInfo(uri){UseShellExecute=true}); }; page.Controls.Add(link);
        }
        private void UpdateModels() { string selected=Convert.ToString(defaultModel.SelectedItem); defaultModel.Items.Clear(); foreach(object item in models.CheckedItems) defaultModel.Items.Add(item); if(defaultModel.Items.Contains(selected)) defaultModel.SelectedItem=selected; else if(defaultModel.Items.Count>0) defaultModel.SelectedIndex=0; }
        private void UpdateEngines() { string selected=Convert.ToString(defaultEngine.SelectedItem); defaultEngine.Items.Clear(); foreach(int i in engines.CheckedIndices) defaultEngine.Items.Add(engineIds[i]); if(defaultEngine.Items.Contains(selected)) defaultEngine.SelectedItem=selected; else if(defaultEngine.Items.Count>0) defaultEngine.SelectedIndex=0; }
        private void LoadDefaultLocation() {
            string location="cloud";
            try {
                foreach(string name in new[]{"defaults.json","config.json"}) {
                    string path=Path.Combine(destination.Text,"config",name);if(!File.Exists(path)) continue;
                    var config=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(path));object section,value;
                    if(config!=null && config.TryGetValue("interaction",out section) && section is Dictionary<string,object> && ((Dictionary<string,object>)section).TryGetValue("location",out value)) location=Convert.ToString(value);
                }
                defaultLocation.SelectedIndex=defaultLocation.Items.IndexOf(location);
            } catch(IOException) {defaultLocation.SelectedIndex=-1;}
              catch(UnauthorizedAccessException) {defaultLocation.SelectedIndex=-1;}
              catch(ArgumentException) {defaultLocation.SelectedIndex=-1;}
              catch(InvalidOperationException) {defaultLocation.SelectedIndex=-1;}
        }
        internal void RefreshFeatureStatus() {
            cloud.AccessibleDescription=local.AccessibleDescription=voice.AccessibleDescription="Not configured in this folder";
            string record=Path.Combine(destination.Text,".whas-installation.json");if(!File.Exists(record)) return;
            try {
                var data=new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue}.Deserialize<Dictionary<string,object>>(File.ReadAllText(record));object value;
                if(data!=null && data.ContainsKey("Status") && Convert.ToString(data["Status"])=="Uninstalled") {cloud.AccessibleDescription=local.AccessibleDescription=voice.AccessibleDescription="Not installed";return;}
                if(data==null || !data.TryGetValue("Status",out value) || Convert.ToString(value)!="Installed") {cloud.AccessibleDescription=local.AccessibleDescription=voice.AccessibleDescription="Installation incomplete; review prerequisites";return;}
                string config=Path.Combine(destination.Text,"opencode.json");
                if(File.Exists(config)) {
                    var agents=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(config));object section;
                    if(agents.TryGetValue("agent",out section) && section is Dictionary<string,object> && ((Dictionary<string,object>)section).ContainsKey("ps-read")) cloud.AccessibleDescription="Cloud route configured; account access not checked";
                    if(agents.TryGetValue("provider",out section) && section is Dictionary<string,object> && ((Dictionary<string,object>)section).ContainsKey("ollama")) local.AccessibleDescription="Local route configured; model availability checked separately";
                }
                if(data.TryGetValue("TtsStrategies",out value) && value is IList) {
                    int count=((IList)value).Cast<object>().OfType<Dictionary<string,object>>().Count(x=>x.ContainsKey("Status") && Convert.ToString(x["Status"])=="Installed");
                    if(count>0) voice.AccessibleDescription="Installed: "+count+" speech engine"+(count==1?"":"s");
                }
                string overrides=Path.Combine(destination.Text,"config","config.json");
                if(File.Exists(overrides)) {var settings=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(overrides));object routes;if(settings.TryGetValue("agents",out routes) && routes is Dictionary<string,object>) foreach(var pair in new[]{Tuple.Create("cloud",cloud),Tuple.Create("local",local)}) {object route,enabled;if(((Dictionary<string,object>)routes).TryGetValue(pair.Item1,out route) && route is Dictionary<string,object> && ((Dictionary<string,object>)route).TryGetValue("enabled",out enabled) && enabled is bool && !(bool)enabled) pair.Item2.AccessibleDescription="Not added";}}
            }catch(Exception){cloud.AccessibleDescription=local.AccessibleDescription=voice.AccessibleDescription="Installed status unavailable; check the installation record";}
        }
        private string[] Selection() {
            var args=new List<string>{"--core","--install-path",Path.GetFullPath(destination.Text)};
            if(defaultLocation.SelectedItem==null) throw new ArgumentException("Choose Cloud or This PC for default processing.");
            args.AddRange(new[]{"--default-location",Convert.ToString(defaultLocation.SelectedItem)});
            string existing=Path.Combine(destination.Text,"config","config.json"); if(File.Exists(existing)) args.AddRange(new[]{"--config",existing});
            if(cloud.Checked) args.Add("--cloud");
            if(local.Checked) { if(models.CheckedItems.Count==0) throw new ArgumentException("Select at least one model for Local AI.");if(defaultModel.SelectedItem==null || !models.CheckedItems.Contains(defaultModel.SelectedItem)) throw new ArgumentException("Choose a default local model from your selected models."); args.AddRange(new[]{"--local","--local-models",String.Join(",",models.CheckedItems.Cast<string>()),"--default-local-model",Convert.ToString(defaultModel.SelectedItem)}); }
            if(voice.Checked) { if(defaultEngine.SelectedItem==null) throw new ArgumentException("Choose a default speech engine."); var ids=engines.CheckedIndices.Cast<int>().Select(i=>engineIds[i]).ToList(); string chosen=Convert.ToString(defaultEngine.SelectedItem); ids.Remove(chosen); ids.Insert(0,chosen); args.AddRange(new[]{"--voice","--tts-engine",String.Join(",",ids),"--tts-devices",String.Join(",",ids.Select(id=>id+"="+Convert.ToString(setupDevices[id].SelectedItem)))}); }
            return args.ToArray();
        }
        private string[] Removal(bool apply) { var args=new List<string>{"--uninstall","--install-path",Path.GetFullPath(destination.Text)}; if(retainModels.Checked) args.Add("--retain-managed-models"); if(apply) args.AddRange(new[]{"--apply","--yes"}); return args.ToArray(); }
        private void ResetConversationContext() {
            if(session!=null) session.Clear();localConversation.Clear();localConversationModel=null;localContextRevision++;
        }
        private void SendLocalMessage(bool chatting,string message,bool readAnswer) {
            if(IsBusy) throw new InvalidOperationException("Wait for the current operation.");
            if(!savedLocalEnabled) throw new InvalidOperationException("Local AI has been removed. Add it under Configuration > Maintenance > Features first.");
            string model=Convert.ToString(((ComboBox)settings["local.model"]).SelectedItem);
            if(model.StartsWith("ollama/",StringComparison.Ordinal)) model=model.Substring(7);
            if(String.IsNullOrWhiteSpace(model)) throw new InvalidOperationException("Choose a local model under Configuration > Models first.");
            if(chatting && localConversationModel!=model) {localConversation.Clear();localConversationModel=model;localContextRevision++;}
            int context=localContextRevision;
            var messages=chatting?new List<Dictionary<string,string>>(localConversation):new List<Dictionary<string,string>>();
            messages.Add(new Dictionary<string,string>{{"role","user"},{"content",message}});
            var reply=BeginConversationReply(message);var transport=new OllamaChatRequest();localChatRequest=transport;
            operationPending=true;operationIsAssistantRequest=true;foreach(Control control in actions) control.Enabled=false;
            progress.Visible=true;progress.Style=ProgressBarStyle.Marquee;cancel.Enabled=true;status.Text="Waiting for reply from Ollama…";output.Clear();
            Action<string,string> finish=delegate(string answer,string error) {
                localChatRequest=null;operationPending=false;cancel.Enabled=false;progress.Visible=false;progress.Style=ProgressBarStyle.Continuous;foreach(Control control in actions) control.Enabled=true;
                if(error==null) {
                    if(chatting && context==localContextRevision && localConversationModel==model) {localConversation.Add(new Dictionary<string,string>{{"role","user"},{"content",message}});localConversation.Add(new Dictionary<string,string>{{"role","assistant"},{"content",answer}});}
                    CompleteConversationReply(reply,answer);status.Text="Completed";output.Clear();
                    if(readAnswer) try {Maintenance("speak",new[]{"--speech-text",answer},null,true);} catch(Exception failure) {status.Text="Failed: Speech could not start.";output.AppendText(failure.Message+Environment.NewLine);}
                } else {
                    string explanation=transport.Cancelled?"Request cancelled.":"Could not get a reply. "+error;
                    CompleteConversationReply(reply,(String.IsNullOrEmpty(answer)?"":answer+Environment.NewLine+Environment.NewLine)+explanation);
                    status.Text=transport.Cancelled?"Request cancelled.":"Failed: Ollama request failed.";if(!transport.Cancelled) output.AppendText("Ollama: "+error+Environment.NewLine);
                }
                UpdateVoiceActions();
            };
            try {
                transport.Start(localChatEndpoint,model,messages.Cast<object>().ToArray(),delegate(string text) {Ui(delegate {if(!reply.Complete) {reply.Value=text;reply.Pending=false;ConversationRevision++;status.Text="Receiving reply from Ollama…";}});},delegate(string answer,string error) {Ui(delegate {finish(answer,error);});});prompt.Clear();
            }catch(Exception error){finish("",error.Message);}
        }
        private void BuildUsage() {
            var use=Page("Assistant");
            TextLine(use,"Continue a conversation, run a task or ask a one-off question. Manage defaults and advanced options in Configuration.",48);
            string documents=Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            preferences.SeedWorkspace(Directory.Exists(documents)?documents:Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
            workspace=new TextBox {Width=800,Text=preferences.ActiveWorkspace};
            session=new TextBox {Width=500};
            action=Choice(use,"Operation",new[]{"chat","perform","ask"});
            TextLine(use,"Your message",24);prompt=new TextBox {Multiline=true,Width=800,Height=110,ScrollBars=ScrollBars.Vertical,AccessibleName="Your message"}; use.Controls.Add(prompt);
            Button(use,"Send",delegate {
                if(String.IsNullOrWhiteSpace(prompt.Text)) throw new ArgumentException("Enter a question or message.");
                bool chatting=Convert.ToString(action.SelectedItem)=="chat"; string message=prompt.Text;bool readAnswer=speak.Checked;
                bool task=Convert.ToString(action.SelectedItem)=="perform";bool localRequest=Convert.ToString(route.SelectedItem)=="local" || (Convert.ToString(route.SelectedItem)=="default" && SavedProcessing=="local");
                if(!task && localRequest) {SendLocalMessage(chatting,message,readAnswer);return;}
                string request=task?"Available workspace folders (including their subfolders):"+Environment.NewLine+json.Serialize(preferences.Workspaces.ToArray())+Environment.NewLine+Environment.NewLine+"User request:"+Environment.NewLine+message:message;
                var args=new List<string>{Convert.ToString(action.SelectedItem)};
                if(route.SelectedIndex>0) args.Add("--"+route.SelectedItem);
                if(runtime.SelectedIndex>0) args.AddRange(new[]{"--runtime",Convert.ToString(runtime.SelectedItem)});
                // Generate first, then speak the completed answer separately.
                // This keeps speech diagnostics out of answers and chat JSON.
                args.Add("--no-voice");
                if(action.SelectedItem.ToString()=="chat") { if(session.Text.Trim().Length>0) args.AddRange(new[]{"--session",session.Text.Trim()}); args.AddRange(new[]{"--message",request}); }
                else args.Add(request);
                string cli=Cli();var reply=BeginConversationReply(message);
                try {
                    Run(cli,args,delegate(int code,string text) {
                        if(code!=0) {CompleteConversationReply(reply,code==130?"Request cancelled.":"Could not get a reply. See the activity log for details.");return;}
                        string answer=text.Trim();
                        if(chatting) {
                            try {var response=json.Deserialize<Dictionary<string,object>>(text);session.Text=Convert.ToString(response["sessionId"]);answer=Convert.ToString(response["answer"]);}
                            catch {status.Text="Received an invalid conversation response.";CompleteConversationReply(reply,"Could not read the reply. Try again.");return;}
                        }
                        CompleteConversationReply(reply,String.IsNullOrWhiteSpace(answer)?"No reply was returned.":answer);output.Clear();
                        if(readAnswer && !String.IsNullOrWhiteSpace(answer)) Maintenance("speak",new[]{"--speech-text",answer},null,true);
                    });
                    prompt.Clear();
                } catch(Exception error) {CompleteConversationReply(reply,"Could not start the request. See the activity log for details.");output.AppendText(error.Message+Environment.NewLine);throw;}
            });
            route=Choice(use,"Run on",new[]{"default","local","cloud"});
            route.SelectedIndexChanged+=delegate {ResetConversationContext();};
            speak=new CheckBox {Text="Speak the answer",Width=350}; use.Controls.Add(speak);
            TextLine(use,"Responses",24);conversation=new TextBox {Multiline=true,ReadOnly=true,Width=800,Height=200,ScrollBars=ScrollBars.Vertical,AccessibleName="Responses"}; use.Controls.Add(conversation);
            BuildSettings(); BuildVoice();
            var memory=Page("Sessions & memory");
            TextLine(memory,"Cloud conversation ID (OpenCode; blank starts a new conversation)",24);memory.Controls.Add(session);
            Button(memory,"New conversation",delegate { ResetConversationContext(); prompt.Clear(); output.Clear(); conversation.Clear();ConversationReplies.Clear();ConversationRevision++; });
            TextLine(memory,"Local conversation history stays in this window and is sent directly to Ollama. One-off questions do not use or change that history. New conversation clears the current context. Cloud conversations can resume a registered OpenCode session ID. Run a task uses file tools separately.",100);
            TextLine(memory,"Personal agent data is preserved during uninstall. Manage native runtime memory through its documented interface. WHAS does not silently enable a gateway, schedule, memory upload or cross-runtime history sharing.",90);
            Button(memory,"List WHAS conversation associations",delegate { Command(new[]{"session","list"},null); });
            var sessionRuntime=Choice(memory,"Runtime for association removal",new[]{"opencode"});
            var forget=new TextBox {Width=500}; TextLine(memory,"Session ID to forget (native history and memory remain)",24); memory.Controls.Add(forget);
            Button(memory,"Forget association…",delegate { if(MessageBox.Show(DialogOwner??this,"Forget only this WHAS association? This does not delete native history or persistent memory.","Forget association",MessageBoxButtons.YesNo)!=DialogResult.Yes) return; Command(new[]{"session","forget",Convert.ToString(sessionRuntime.SelectedItem),forget.Text.Trim(),"--yes"},null); });
            Button(memory,"Open installation folder",delegate { Process.Start(new ProcessStartInfo(root){UseShellExecute=true}); });
        }
        private void OpenSetup() {
            tabs.SelectedIndex=featureTab;
        }
        private void RefreshRuntimes(Action done=null) {
            Command(new[]{"agent","list"},delegate(int code,string text) {
                if(code!=0) {if(done!=null) done();return;}
                ChangeSettings(delegate {
                string selected=Convert.ToString(runtime.SelectedItem); runtime.Items.Clear(); runtime.Items.Add("default");
                var saved=(ComboBox)settings["runtime"]; string savedChoice=Convert.ToString(saved.SelectedItem); saved.Items.Clear(); saved.Items.Add("none");
                foreach(string line in text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries)) { var entry=json.Deserialize<Dictionary<string,object>>(line); if((bool)entry["Available"] && Convert.ToString(entry["Id"])=="opencode") { string id=Convert.ToString(entry["Id"]); runtime.Items.Add(id); saved.Items.Add(id); } }
                runtime.SelectedItem=runtime.Items.Contains(selected)?selected:"default"; saved.SelectedItem=saved.Items.Contains(savedRuntime)?savedRuntime:saved.Items.Contains(savedChoice)?savedChoice:"none";
                });
                if(done!=null) done();
            });
        }
        private void BuildSettings() {
            var page=Page("Configuration"); TextLine(page,"Appearance and everyday request defaults.",32);
            Section(page,"Appearance");
            var theme=Choice(page,"Appearance",new[]{"system","light","dark"});theme.SelectedItem=preferences.Theme;
            bool changingTheme=false;theme.SelectedIndexChanged+=delegate {if(changingTheme) return;string previous=preferences.Theme;try{preferences.Theme=Convert.ToString(theme.SelectedItem);preferences.Save();if(AppearanceChanged!=null) AppearanceChanged();}catch(Exception error){preferences.Theme=previous;changingTheme=true;theme.SelectedItem=previous;changingTheme=false;Error(error);}};
            Section(page,"Request defaults");
            settings["location"]=Choice(page,"Run on by default",new[]{"cloud","local"});
            settings["speech.enabled"]=Choice(page,"Speak answers by default",new[]{"false","true"});
            TextLine(page,"Settings save automatically when changed and also apply to the CLI. Appearance is saved for this Windows user.",48);
            Button(page,"Reload shared settings",delegate { ReloadSettings(); });
            if(preferences.Warning.Length>0) TextLine(page,preferences.Warning,48);
            var folders=Page("Workspaces");TextLine(folders,"Every saved folder and its subfolders is available to requests. Choose where commands start; all the other folders stay available.",48);
            workspaceChoices=Choice(folders,"Starting folder",preferences.Workspaces);workspaceChoices.SelectedItem=preferences.ActiveWorkspace;actions.Add(workspaceChoices);
            workspaceChoices.SelectedIndexChanged+=delegate {if(!refreshingWorkspaces && workspaceChoices.SelectedItem!=null) {try{SetWorkspace(Convert.ToString(workspaceChoices.SelectedItem));}catch(Exception error){RefreshWorkspaceChoices();Error(error);}}};
            workspaceNotice=new Label {Width=760,Height=40};folders.Controls.Add(workspaceNotice);RefreshWorkspaceChoices();
            Button(folders,"Add workspace…",delegate {string folder=FolderPicker.Select(DialogOwner??this,workspace.Text,"Add workspace folder");if(folder!=null) AddWorkspace(folder);});
            Button(folders,"Remove workspace from list",delegate {RemoveWorkspace();});
            TextLine(folders,"Removing an entry never deletes its folder or files. Changing the starting folder or workspace list starts a new conversation. Questions remain read-only; tasks retain their normal tool permissions.",65);
            var modelsPage=Page("Models");TextLine(modelsPage,"Choose how requests run and which models they use. Changes save automatically; reload after editing settings in PowerShell.",48);
            Section(modelsPage,"Agent runtime");
            runtime=Choice(modelsPage,"Runtime for this window",new[]{"default"});
            runtime.SelectedIndexChanged+=delegate {ResetConversationContext();};
            Button(modelsPage,"Refresh available runtimes",delegate {RefreshRuntimes();});
            settings["runtime"]=Choice(modelsPage,"Default runtime",new[]{"none"});
            Section(modelsPage,"Cloud model");
            settings["cloud.model"]=Choice(modelsPage,"Cloud model",new[]{""});
            TextLine(modelsPage,"Use OpenCode default keeps OpenCode's own model choice. A listed model does not guarantee account access. Manage provider sign-in using the button below.",48);
            Button(modelsPage,"Manage OpenCode accounts…",delegate { using(var manager=new ProviderWindow(root)) manager.ShowDialog(DialogOwner??this); });
            Section(modelsPage,"Local model");
            settings["local.model"]=Choice(modelsPage,"Local model",new string[0]);
            modelNotice=new Label {Width=760,Height=58,Text="Choices come from OpenCode and installed Ollama models. Saved choices remain available if discovery fails."};modelsPage.Controls.Add(modelNotice);
            TextLine(modelsPage,"Add local model downloads under Maintenance > Features.",36);
            Button(modelsPage,"Reload model settings",delegate { ReloadSettings(); });
            var speech=Page("Voice");TextLine(speech,"Manage speech startup, hardware, engines and voices.",32);
            Section(speech,"Speech startup");
            settings["speech.autoStart"]=Choice(speech,"Start speech on demand",new[]{"true","false"});
            settings["speech.idleTimeoutMinutes"]=Choice(speech,"Stop speech engine after idle (minutes)",new[]{"0","1","5","10","15","30","60","120"});
            TextLine(speech,"0 keeps the engine running. Changes apply the next time the speech engine starts.",48);
            Section(speech,"Hardware");
            settings["speech.device"]=Choice(speech,"Speech device (takes effect on engine installation)",new[]{"auto","cpu","cuda"});
            var labels=new Dictionary<string,string>{{"location","default processing"},{"runtime","default runtime"},{"cloud.model","cloud model"},{"local.model","local model"},{"speech.enabled","speech by default"},{"speech.device","speech device"},{"speech.autoStart","start speech on demand"}};
            foreach(var pair in labels) {string key=pair.Key;var choice=(ComboBox)settings[key];actions.Add(choice);choice.SelectedIndexChanged+=delegate {SaveChangedSetting(key,choice);};}
            var timeout=(ComboBox)settings["speech.idleTimeoutMinutes"];actions.Add(timeout);timeout.SelectedIndexChanged+=delegate {SaveChangedSetting("speech.idleTimeoutMinutes",timeout);};
        }
        private void ChangeSettings(Action update) {settingsChanging++;try{update();}finally{settingsChanging--;}}
        private void SaveChangedSetting(string key,ComboBox choice) {
            if(settingsChanging>0 || !sharedSettingsLoaded || choice.SelectedItem==null) return;
            string previous;savedSettingValues.TryGetValue(key,out previous);string value=Convert.ToString(choice.SelectedItem);if(value==previous) return;
            if(IsBusy) {ChangeSettings(delegate {choice.SelectedItem=previous;});return;}
            try {Action<int,string> saved=delegate(int code,string text){
                if(code!=0) {ChangeSettings(delegate {choice.SelectedItem=previous;});return;}
                savedSettingValues[key]=value;
                if(key=="location") {savedLocation=value;defaultLocation.SelectedItem=value;ResetConversationContext();}
                if(key=="runtime") {savedRuntime=value=="none"?null:value;ResetConversationContext();}
                if(key.EndsWith(".model")) ResetConversationContext();
                if(key=="speech.enabled") speak.Checked=value=="true";
                status.Text="Setting saved. New requests use the updated default.";
            };if(key=="speech.idleTimeoutMinutes") Maintenance("speech-timeout",new[]{"--idle-timeout-minutes",value},saved);else Command(new[]{"configure","--set",key,value},saved);}catch(Exception error){ChangeSettings(delegate {choice.SelectedItem=previous;});Error(error);}
        }
        private void ChangeWorkspaces(Action change) {
            if(IsBusy) throw new InvalidOperationException("Wait for the current operation before changing workspace.");
            string active=preferences.ActiveWorkspace;var folders=preferences.Workspaces.ToArray();
            try {change();preferences.Save();}catch{preferences.Workspaces.Clear();preferences.Workspaces.AddRange(folders);preferences.ActiveWorkspace=active;throw;}
            workspace.Text=preferences.ActiveWorkspace;ResetConversationContext();RefreshWorkspaceChoices();
        }
        internal void AddWorkspace(string folder) {
            string full=GuiPreferences.Normalize(folder);if(!Directory.Exists(full)) throw new DirectoryNotFoundException("Choose an existing workspace folder.");
            ChangeWorkspaces(delegate {if(!preferences.Workspaces.Contains(full,StringComparer.OrdinalIgnoreCase)) preferences.Workspaces.Add(full);preferences.ActiveWorkspace=full;});
        }
        internal void SetWorkspace(string folder) {
            string full=GuiPreferences.Normalize(folder);if(!preferences.Workspaces.Contains(full,StringComparer.OrdinalIgnoreCase)) throw new ArgumentException("Add this workspace before selecting it.");
            if(String.Equals(full,preferences.ActiveWorkspace,StringComparison.OrdinalIgnoreCase)) return;
            ChangeWorkspaces(delegate {preferences.ActiveWorkspace=full;});
        }
        private void RemoveWorkspace() {
            string selected=Convert.ToString(workspaceChoices.SelectedItem);if(selected.Length==0) return;
            RemoveWorkspaceFolder(selected);
        }
        internal void RemoveWorkspaceFolder(string selected) {
            ChangeWorkspaces(delegate {preferences.Workspaces.RemoveAll(x=>String.Equals(x,selected,StringComparison.OrdinalIgnoreCase));if(String.Equals(selected,preferences.ActiveWorkspace,StringComparison.OrdinalIgnoreCase)) preferences.ActiveWorkspace=preferences.Workspaces.FirstOrDefault(Directory.Exists)??"";});
        }
        private void RefreshWorkspaceChoices() {
            if(workspaceChoices==null) return;refreshingWorkspaces=true;
            try {workspaceChoices.Items.Clear();workspaceChoices.Items.AddRange(preferences.Workspaces.Cast<object>().ToArray());workspaceChoices.SelectedItem=preferences.ActiveWorkspace;
                if(workspaceNotice!=null) workspaceNotice.Text=Directory.Exists(preferences.ActiveWorkspace)?"Commands start here. All saved workspace folders and their subfolders are available.":"Select an existing starting folder before sending a request. Other saved folders remain in the list.";
            }finally{refreshingWorkspaces=false;}
        }
        private void ReloadSettings() {
            Command(new[]{"configure","--show"},delegate(int code,string text) {
                if(code!=0) return;
                try {
                    var config=json.Deserialize<Dictionary<string,object>>(text);
                    var interaction=(Dictionary<string,object>)config["interaction"];
                    savedLocation=Convert.ToString(interaction["location"]);
                    defaultLocation.SelectedIndex=defaultLocation.Items.IndexOf(Convert.ToString(interaction["location"]));
                    var agents=(Dictionary<string,object>)config["agents"]; var tts=(Dictionary<string,object>)config["tts"];
                    object localEnabled;var localSettings=(Dictionary<string,object>)agents["local"];savedLocalEnabled=!localSettings.TryGetValue("enabled",out localEnabled) || (bool)localEnabled;
                    savedRuntime=Convert.ToString(interaction["runtime"]);savedEngine=Convert.ToString(tts["engine"]);savedVoice=Convert.ToString(tts["defaultVoice"]);
                    savedVoices.Clear();object perEngine;if(tts.TryGetValue("voiceDefaults",out perEngine) && perEngine is Dictionary<string,object>) foreach(var pair in (Dictionary<string,object>)perEngine) savedVoices[pair.Key]=Convert.ToString(pair.Value);
                    SetControl("location",interaction["location"]); SetControl("runtime",interaction["runtime"]); SetControl("speech.enabled",interaction["speech"]);
                    SetControl("cloud.model",((Dictionary<string,object>)agents["cloud"])["model"]); SetControl("local.model",((Dictionary<string,object>)agents["local"])["model"]);
                    speak.Checked=(bool)interaction["speech"];SetControl("speech.device",tts["device"]); SetControl("speech.autoStart",tts["autoStart"]);
                    SetControl("speech.idleTimeoutMinutes",tts.ContainsKey("idleTimeoutMinutes")?tts["idleTimeoutMinutes"]:10);
                    sharedSettingsLoaded=true;
                    RefreshRuntimes(delegate {RefreshVoice(delegate {RefreshModels();});});
                } catch(Exception e) { Error(e); }
            });
        }
        private void SetControl(string key,object value) { string text=key=="runtime" && value==null ? "none" : value is bool ? value.ToString().ToLowerInvariant() : Convert.ToString(value);ChangeSettings(delegate {var control=settings[key]; if(control is ComboBox) {var choice=(ComboBox)control;if((key.EndsWith(".model") || key=="speech.idleTimeoutMinutes") && !choice.Items.Contains(text)) choice.Items.Add(text);choice.SelectedItem=text;} else control.Text=text;});savedSettingValues[key]=text; }
        private void RefreshModels() {
            // Query the providers' existing read-only CLI commands. The GUI
            // must also work with older installed WHAS management backends.
            string local=GuiProcess.FindApplication("ollama.exe");
            if(local==null) {modelNotice.Text="Ollama was not found; the saved local model is retained.";RefreshCloudModels();return;}
            Run(local,new[]{"list"},delegate(int code,string text) {
                modelNotice.Text=code==0?"Local model choices loaded from Ollama.":"Ollama discovery failed; the saved local model is retained.";
                if(code==0) ApplyModelChoices("local.model",text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).Skip(1).Select(x=>Regex.Split(x.Trim(),"\\s+")[0]).Where(x=>x!="NAME" && Regex.IsMatch(x,"^[A-Za-z0-9][A-Za-z0-9._/:-]*$")).ToArray(),false);
                RefreshCloudModels();
            },true);
        }
        private void RefreshCloudModels() {
            string cloud=GuiProcess.FindApplication("opencode.exe");
            if(cloud==null) {modelNotice.Text+=" OpenCode was not found; its default/saved model is retained.";return;}
            var environment=new Dictionary<string,string>();string config=Path.Combine(root,"opencode.json");if(File.Exists(config)) environment["OPENCODE_CONFIG"]=config;
            Run(cloud,new[]{"models"},delegate(int code,string text) {
                modelNotice.Text+=code==0?" Cloud choices loaded from OpenCode; provider access still requires authentication.":" OpenCode discovery failed; its default/saved model is retained. Check the activity log.";
                if(code==0) ApplyModelChoices("cloud.model",text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).Select(x=>x.Trim()).Where(x=>Regex.IsMatch(x,"^[A-Za-z0-9._-]+/[^\\s]+$") && !x.StartsWith("ollama/",StringComparison.Ordinal)).ToArray(),true);
            },true,environment);
        }
        private void ApplyModelChoices(string key,string[] names,bool cloudModel) {
            ChangeSettings(delegate {
            var choice=(ComboBox)settings[key];string selected=Convert.ToString(choice.SelectedItem);
            choice.Items.Clear();if(cloudModel) choice.Items.Add("");foreach(string name in names) if(!choice.Items.Contains(name)) choice.Items.Add(name);
            if(!String.IsNullOrEmpty(selected) && !choice.Items.Contains(selected)) choice.Items.Add(selected);
            choice.SelectedItem=selected;
            });
        }
        private void BuildVoice() {
            var page=(FlowLayoutPanel)tabs.TabPages.Cast<TabPage>().First(x=>x.Text=="Voice").Controls[0];
            Section(page,"Engines and voices");
            voiceEngine=Choice(page,"Speech engine",new string[0]); voiceName=Choice(page,"Saved voice",new[]{"default"});actions.Add(voiceEngine);actions.Add(voiceName);
            voiceSupport.Width=800; voiceSupport.Height=50;voiceSupport.Text="Open Speech to check installed engines and voices. Available strategies can be installed here."; page.Controls.Add(voiceSupport);
            Button(page,"Refresh engines and voices",delegate { RefreshVoice(); });
            voiceInstall=Button(page,"Install selected engine…",delegate { if(MessageBox.Show(DialogOwner??this,"Install the selected engine and its private dependencies?","Install speech",MessageBoxButtons.YesNo)!=DialogResult.Yes) return; Command(new[]{"tts","install",Convert.ToString(voiceEngine.SelectedItem),"--yes"},delegate(int code,string text){RefreshVoice();}); });
            installedVoiceActions.Add(Button(page,"Set default engine",delegate { Command(new[]{"tts","default",Convert.ToString(voiceEngine.SelectedItem)},delegate(int code,string text){if(code==0) {savedEngine=Convert.ToString(voiceEngine.SelectedItem);RefreshVoice();}}); }));
            installedVoiceActions.Add(Button(page,"Preview engine removal",delegate { Command(new[]{"tts","uninstall",Convert.ToString(voiceEngine.SelectedItem)},null); }));
            installedVoiceActions.Add(Button(page,"Remove selected engine…",delegate { if(MessageBox.Show(DialogOwner??this,"Remove unchanged engine files? Personal references remain. Select another default first if necessary.","Remove speech engine",MessageBoxButtons.YesNo)!=DialogResult.Yes) return; Command(new[]{"tts","uninstall",Convert.ToString(voiceEngine.SelectedItem),"--apply","--yes"},delegate(int code,string text){RefreshVoice();}); }));
            voiceSelectionNotice=new Label {Width=760,Height=58};page.Controls.Add(voiceSelectionNotice);
            installedVoiceActions.Add(Button(page,"Play test phrase",delegate { Maintenance("speak",new[]{"--speech-text","This is a preview of the selected voice.","--voice-name",Convert.ToString(voiceName.SelectedItem),"--tts-engine",Convert.ToString(voiceEngine.SelectedItem)},null); }));
            voiceDefault=Button(page,"Set this as default voice",delegate {SetVoiceDefault(Convert.ToString(voiceEngine.SelectedItem),Convert.ToString(voiceName.SelectedItem),null);});installedVoiceActions.Add(voiceDefault);
            voiceRemove=Button(page,"Delete this voice…",delegate {
                string selected=Convert.ToString(voiceName.SelectedItem); if(selected=="default") throw new InvalidOperationException("The built-in voice cannot be removed.");
                if(MessageBox.Show(DialogOwner??this,"Delete this personal reference and matching transcript?","Delete reference",MessageBoxButtons.YesNo)!=DialogResult.Yes) return;
                Maintenance("voice-remove",new[]{"--voice-name",selected,"--tts-engine",Convert.ToString(voiceEngine.SelectedItem)},delegate(int code,string text){if(code==0) RefreshVoice();});
            });
            Section(page,"Add a voice");TextLine(page,"Choose a WAV recording, give the voice a name, then save. Choosing a file does not save, play or select it as the default.",48);
            TextLine(page,"WAV recording",24);voiceReferencePath=new TextBox {Width=760,ReadOnly=true};page.Controls.Add(voiceReferencePath);
            voiceChoose=Button(page,"Choose WAV recording…",delegate {using(var picker=new OpenFileDialog {Filter="WAV recordings (*.wav)|*.wav",CheckFileExists=true}) {if(picker.ShowDialog(DialogOwner??this)==DialogResult.OK) SelectVoiceRecording(picker.FileName);}});
            TextLine(page,"Voice name",24);voiceReferenceName=new TextBox {Width=500};page.Controls.Add(voiceReferenceName);voiceReferenceName.TextChanged+=delegate {voiceImportError="";UpdateVoiceActions();};
            voiceImportNotice=new Label {Width=760,Height=60};page.Controls.Add(voiceImportNotice);
            voiceMakeDefault=new CheckBox {Text="Make this the default voice for this engine",Width=700};voiceMakeDefault.CheckedChanged+=delegate {UpdateVoiceActions();};page.Controls.Add(voiceMakeDefault);
            voiceAdd=Button(page,"Save voice",delegate {SaveVoiceReference();});
            voiceEngine.SelectedIndexChanged+=delegate { if(voiceEngine.SelectedItem==null) return;voiceReferencePath.Clear();voiceReferenceName.Clear();voiceMakeDefault.Checked=false; var entry=voiceInventory[Convert.ToString(voiceEngine.SelectedItem)]; bool supported=(bool)entry["voiceCloning"]; voiceSupport.Text=!voiceInventoryLoaded?"Installed state has not loaded. Select Refresh engines and voices.":!(bool)entry["installed"] ? "Available; install this engine before use." : supported ? ((bool)entry["transcriptRequired"] ? "Installed. Custom voices need a WAV recording and matching UTF-8 transcript." : "Installed. Custom voices use a reference WAV recording.") : "Installed. Built-in voices only; custom reference recordings are not supported."; voiceName.Items.Clear(); foreach(object item in (object[])entry["voices"]) voiceName.Items.Add(item); if(voiceName.Items.Count>0) voiceName.SelectedIndex=0;string active=Convert.ToString(voiceEngine.SelectedItem);string chosen=savedVoices.ContainsKey(active)?savedVoices[active]:savedVoice;if(voiceName.Items.Contains(chosen)) voiceName.SelectedItem=chosen;UpdateVoiceActions(); };
            voiceName.SelectedIndexChanged+=delegate { UpdateVoiceActions(); };
            foreach(Dictionary<string,object> item in json.Deserialize<object[]>(catalog??"[]")) {string id=Convert.ToString(item["id"]);var capabilities=(Dictionary<string,object>)item["capabilities"];object reference;bool transcript=item.TryGetValue("voiceReference",out reference) && ((Dictionary<string,object>)reference).ContainsKey("transcriptRequired") && (bool)((Dictionary<string,object>)reference)["transcriptRequired"];voiceDeviceChoices[id]=((IList)item["devices"]).Count>1;voiceInventory[id]=new Dictionary<string,object>{{"installed",false},{"voiceCloning",capabilities["voiceCloning"]},{"transcriptRequired",transcript},{"voices",new object[]{"default"}}};voiceEngine.Items.Add(id);}
            if(voiceEngine.Items.Count>0) voiceEngine.SelectedIndex=0;
            UpdateVoiceActions();
        }
        internal void SelectVoiceRecording(string path) {
            if(IsBusy) throw new InvalidOperationException("Wait for the current operation.");
            if(!voiceInventoryLoaded || voiceEngine.SelectedItem==null || !(bool)voiceInventory[Convert.ToString(voiceEngine.SelectedItem)]["installed"] || !(bool)voiceInventory[Convert.ToString(voiceEngine.SelectedItem)]["voiceCloning"]) throw new InvalidOperationException("Install an engine that supports custom reference recordings first.");
            if(!File.Exists(path) || !String.Equals(Path.GetExtension(path),".wav",StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Choose an existing WAV recording.");
            voiceImportError="";voiceReferencePath.Text=Path.GetFullPath(path);
            if(String.IsNullOrWhiteSpace(voiceReferenceName.Text)) {string name=Regex.Replace(Path.GetFileNameWithoutExtension(path),"[^A-Za-z0-9_-]","-").Trim('-','_');if(name.Length>40) name=name.Substring(0,40);voiceReferenceName.Text=name.Length==0 || name=="default"?"my-voice":name;}
            UpdateVoiceActions();
        }
        private string VoiceImportProblem() {
            if(voiceEngine.SelectedItem==null || !voiceInventoryLoaded) return "Wait for speech inventory to load.";
            var entry=voiceInventory[Convert.ToString(voiceEngine.SelectedItem)];
            if(!(bool)entry["installed"]) return "Install this engine before adding a voice.";
            if(!(bool)entry["voiceCloning"]) return "This engine does not support custom reference recordings.";
            if(!File.Exists(voiceReferencePath.Text)) return "1. Choose a WAV recording. It will not be saved yet.";
            string name=voiceReferenceName.Text.Trim();
            if(!Regex.IsMatch(name,"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$") || String.Equals(name,"default",StringComparison.OrdinalIgnoreCase)) return "2. Enter a unique name: 1–40 letters, numbers, hyphens or underscores. Start with a letter or number; default is reserved.";
            if(voiceName.Items.Cast<object>().Any(x=>String.Equals(Convert.ToString(x),name,StringComparison.OrdinalIgnoreCase))) return "That voice name already exists. Choose a different name; saving never overwrites a voice.";
            if((bool)entry["transcriptRequired"]) {string transcript=Path.ChangeExtension(voiceReferencePath.Text,".txt");try {if(!File.Exists(transcript)) return "F5 requires a matching UTF-8 .txt transcript beside the WAV, with the same filename. Add it, then choose the WAV again.";if(new FileInfo(transcript).Length>16384) return "The F5 transcript must contain 1–4000 characters.";string words=new UTF8Encoding(false,true).GetString(File.ReadAllBytes(transcript)).Trim('\uFEFF').Trim();if(words.Length==0 || words.Length>4000) return "The F5 transcript must contain 1–4000 characters.";}catch(IOException){return "The matching transcript could not be read.";}catch(DecoderFallbackException){return "The matching transcript must be UTF-8 text.";}}
            return null;
        }
        internal void SaveVoiceReference() {
            string problem=VoiceImportProblem();if(problem!=null) throw new ArgumentException(problem);
            string engine=Convert.ToString(voiceEngine.SelectedItem),name=voiceReferenceName.Text.Trim();
            bool makeDefault=voiceMakeDefault.Checked;
            Maintenance("voice-add",new[]{"--reference-path",voiceReferencePath.Text,"--voice-name",name,"--tts-engine",engine},delegate(int code,string text){if(code!=0) {voiceImportError="Save did not complete successfully. Your recording and name are kept. Check the activity log and refresh saved voices before retrying.";return;}RefreshVoice(delegate {if(voiceName.Items.Contains(name)) voiceName.SelectedItem=name;UpdateVoiceActions();status.Text="Saved voice '"+name+"'. Select Set this as default voice to use it for this engine's answers.";if(makeDefault) SetVoiceDefault(engine,name,null);});});
        }
        private void SetVoiceDefault(string engine,string name,Action done) {
            Maintenance("voice-default",new[]{"--tts-engine",engine,"--voice-name",name},delegate(int code,string text){if(code==0) {savedVoices[engine]=name;UpdateVoiceActions();status.Text="Default voice for "+engine+": "+(name=="default"?"Built-in voice":name)+". New spoken answers use it.";if(done!=null) done();}});
        }
        private void UpdateVoiceActions() {
            if(voiceAdd==null || voiceRemove==null) return;
            bool selected=voiceEngine!=null && voiceEngine.SelectedItem!=null && voiceInventory.ContainsKey(Convert.ToString(voiceEngine.SelectedItem));
            bool installed=voiceInventoryLoaded && selected && (bool)voiceInventory[Convert.ToString(voiceEngine.SelectedItem)]["installed"];
            bool idle=!IsBusy;
            foreach(var button in installedVoiceActions) button.Enabled=installed && idle && voiceName.SelectedItem!=null;
            if(voiceInstall!=null) voiceInstall.Enabled=voiceInventoryLoaded && selected && !installed && idle;
            bool supported=installed;
            if(supported) { var entry=voiceInventory[Convert.ToString(voiceEngine.SelectedItem)]; supported=(bool)entry["installed"] && (bool)entry["voiceCloning"]; }
            voiceChoose.Enabled=supported && idle;voiceReferenceName.Enabled=supported && idle;
            string problem=VoiceImportProblem();voiceAdd.Enabled=supported && idle && problem==null;
            voiceImportNotice.Text=voiceImportError.Length>0?voiceImportError:problem??(voiceMakeDefault.Checked?"3. Save voice stores this reference and makes it this engine's default voice. It does not train model weights or play audio.":"3. Save voice stores this reference and keeps the current default voice. It does not train model weights or play audio.");
            string engine=selected?Convert.ToString(voiceEngine.SelectedItem):"",chosen=Convert.ToString(voiceName.SelectedItem),saved=savedVoices.ContainsKey(engine)?savedVoices[engine]:savedVoice;
            bool isSaved=String.Equals(chosen,saved,StringComparison.OrdinalIgnoreCase);
            voiceMakeDefault.Enabled=supported && idle;
            voiceDefault.Enabled=installed && idle && voiceName.SelectedItem!=null && !isSaved;
            voiceSelectionNotice.Text="Default voice for this engine: "+(saved=="default"?"Built-in voice":saved)+". Select a saved voice, then Set this as default voice to use it for new spoken answers. Play test phrase only tests your selection.";
            if(isSaved && chosen!="default") voiceSelectionNotice.Text+=" Choose another default before deleting this voice.";
            voiceRemove.Enabled=supported && idle && voiceName.SelectedItem!=null && chosen!="default" && !isSaved;
        }
        private void RefreshVoice(Action done=null) {
            Command(new[]{"tts","inventory"},delegate(int code,string text) {
                if(code!=0) {voiceInventoryLoaded=false;voiceSupport.Text="Could not read installed engines. Check the activity log, then refresh.";UpdateVoiceActions();if(done!=null) done();return;} try {
                    string registry=Path.Combine(root,"tts","engines.json");if(File.Exists(registry)) {var engines=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(registry));if(Convert.ToInt32(engines["schemaVersion"])!=1) throw new ArgumentException("Unsupported speech engine registry.");savedEngine=Convert.ToString(engines["defaultEngine"]);}
                    string selected=voiceInventoryLoaded?Convert.ToString(voiceEngine.SelectedItem):savedEngine;
                    voiceInventory.Clear(); voiceEngine.Items.Clear();
                    foreach(Dictionary<string,object> item in json.Deserialize<object[]>(text)) { string id=Convert.ToString(item["id"]);CorrectLegacyVoices(item); voiceInventory[id]=item; voiceEngine.Items.Add(id); }
                    voiceInventoryLoaded=true;
                    if(voiceEngine.Items.Count>0) {voiceEngine.SelectedItem=voiceEngine.Items.Contains(selected)?selected:voiceEngine.Items[0];string id=Convert.ToString(voiceEngine.SelectedItem);string selectedVoice=savedVoices.ContainsKey(id)?savedVoices[id]:savedVoice;if(voiceName.Items.Contains(selectedVoice)) voiceName.SelectedItem=selectedVoice;}
                    else voiceSupport.Text="No speech strategies are available. Add Speech through Features.";
                    UpdateVoiceActions();if(done!=null) done();
                } catch(Exception e) { Error(e); }
            });
        }
        private void CorrectLegacyVoices(Dictionary<string,object> item) {
            if(item.ContainsKey("referenceInventoryVersion") || !(bool)item["installed"] || !(bool)item["voiceCloning"]) return;
            // Old inventories exposed storage filenames as voice IDs. Read only
            // the declared reference files; do not start or import an ML engine.
            var manifest=json.Deserialize<object[]>(catalog).Cast<Dictionary<string,object>>().First(x=>Convert.ToString(x["id"])==Convert.ToString(item["id"]));object reference,patterns;
            if(!manifest.TryGetValue("voiceReference",out reference) || !((Dictionary<string,object>)reference).TryGetValue("files",out patterns)) {item["voices"]=new object[]{"default"};return;}
            var state=new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue}.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(root,".whas-installation.json")));
            var record=((IList)state["TtsStrategies"]).Cast<Dictionary<string,object>>().Single(x=>Convert.ToString(x["Id"])==Convert.ToString(item["id"]) && Convert.ToString(x["Status"])=="Installed");
            string relative=Convert.ToString(((Dictionary<string,object>)record["Context"])["VoicesPath"]);
            if(Path.IsPathRooted(relative)) throw new ArgumentException("Voice directory must belong to this installation.");
            string directory=Path.GetFullPath(Path.Combine(root,relative));if(!directory.StartsWith(Path.GetFullPath(root).TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Voice directory escapes the installation.");
            for(string part=directory;part!=null;part=Path.GetDirectoryName(part)) if(Directory.Exists(part) && (File.GetAttributes(part)&FileAttributes.ReparsePoint)!=0) throw new ArgumentException("Linked voice directories are unsupported.");
            string[] files=((IList)patterns).Cast<string>().ToArray();foreach(string pattern in files) if(!Regex.IsMatch(pattern,@"^\{name\}[A-Za-z0-9_.-]*\.(wav|pt|txt)$")) throw new ArgumentException("Invalid voice file pattern.");
            var names=new List<object>{"default"};string suffix=files[0].Substring(6);
            if(Directory.Exists(directory)) foreach(string file in Directory.GetFiles(directory)) {
                string name=Path.GetFileName(file);if(!name.EndsWith(suffix,StringComparison.Ordinal)) continue;name=name.Substring(0,name.Length-suffix.Length);
                if(name=="default" || !Regex.IsMatch(name,"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$")) continue;
                if(files.All(pattern=> {string candidate=Path.Combine(directory,pattern.Replace("{name}",name));return File.Exists(candidate) && (File.GetAttributes(candidate)&FileAttributes.ReparsePoint)==0;})) names.Add(name);
            }
            item["voices"]=names.ToArray();
        }
        private static void PrepareRender(Control control) {
            // CreateControl skips invisible descendants of an unshown Form.
            // Force handles for offscreen WM_PRINT; never Show/activate it.
            IntPtr handle=control.Handle;
            control.PerformLayout();
            foreach(Control child in control.Controls) PrepareRender(child);
        }
        public void Render(string file) { rendering=true; PrepareRender(this); PerformLayout(); using(var bitmap=new Bitmap(Width,Height)) { DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height)); bitmap.Save(file); } }
        public void RenderPages(string directory) {
            rendering=true; Directory.CreateDirectory(directory); CreateControl();
            for(int i=0;i<tabs.TabPages.Count;i++) {
                tabs.SelectedIndex=i; PerformLayout();
                var flow=tabs.TabPages[i].Controls[0] as FlowLayoutPanel;
                if(flow!=null) { FitPage(flow); flow.PerformLayout(); }
                Render(Path.Combine(directory,i.ToString("00")+".png"));
            }
        }
    }

}

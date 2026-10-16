// Windows Forms is included with the Windows .NET Framework. No UI runtime
// download, web server, embedded browser or account is required by this UI.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace WindowsHybridAgenticStack {
    public sealed class GuiProcess : IDisposable {
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

    public sealed class WhasWindow : Form {
        private readonly bool setup;
        private readonly string executable;
        private string root;
        private readonly TabControl tabs=new TabControl();
        private readonly TextBox output=new TextBox();
        private readonly Label status=new Label();
        private readonly ProgressBar progress=new ProgressBar();
        private readonly Button cancel=new Button();
        private readonly JavaScriptSerializer json=new JavaScriptSerializer();
        private GuiProcess operation;
        private readonly List<Control> actions=new List<Control>();
        private readonly TextBox destination=new TextBox();
        private readonly CheckBox cloud=new CheckBox(), local=new CheckBox(), voice=new CheckBox();
        private readonly CheckedListBox engines=new CheckedListBox(), models=new CheckedListBox();
        private readonly ComboBox defaultEngine=new ComboBox(), defaultModel=new ComboBox();
        private ComboBox defaultLocation;
        private readonly List<string> engineIds=new List<string>();
        private readonly CheckBox retainModels=new CheckBox();
        private DataGridView checkGrid;
        private bool checkPassed;
        private bool rendering;
        private string checkedSelection;
        private TextBox prompt, session, conversation;
        private TextBox workspace;
        private ComboBox action, route, runtime;
        private CheckBox speak;
        private readonly Dictionary<string,Control> settings=new Dictionary<string,Control>();
        private ComboBox voiceEngine, voiceName;
        private Button voiceAdd, voiceRemove;
        private readonly Label voiceSupport=new Label();
        private readonly Dictionary<string,Dictionary<string,object>> voiceInventory=new Dictionary<string,Dictionary<string,object>>();

        public WhasWindow(bool isSetup,string path,string setupCatalog) {
            setup=isSetup; executable=path; root=ResolveRoot(path);
            Text=setup ? "WHAS Setup" : "WHAS";
            Font=new Font("Segoe UI",10); AutoScaleMode=AutoScaleMode.Dpi;
            Size=new Size(980,800); MinimumSize=new Size(820,640); StartPosition=FormStartPosition.CenterScreen;
            BackColor=Color.FromArgb(246,248,251);
            var heading=new Label {Text=setup ? "Windows Hybrid Agentic Stack — Setup" : "Windows Hybrid Agentic Stack", Dock=DockStyle.Top,Height=62,Padding=new Padding(22,18,0,0),Font=new Font("Segoe UI",16,FontStyle.Bold)};
            tabs.Dock=DockStyle.Fill; tabs.Padding=new Point(16,8);
            output.Multiline=true; output.ReadOnly=true; output.ScrollBars=ScrollBars.Both; output.WordWrap=false;
            output.Dock=DockStyle.Bottom; output.Height=170; output.Font=new Font("Consolas",9); output.BackColor=Color.White;
            status.Dock=DockStyle.Bottom; status.Height=30; status.Padding=new Padding(12,4,0,0); status.Text="Ready";
            var bottom=new Panel {Dock=DockStyle.Bottom,Height=30};
            progress.Dock=DockStyle.Fill; progress.Style=ProgressBarStyle.Continuous;
            cancel.Text="Cancel operation"; cancel.Dock=DockStyle.Right; cancel.Width=170; cancel.Enabled=false;
            cancel.Click+=delegate { if (operation != null) { try { operation.Cancel(); status.Text="Cancellation requested; changes already made may need cleanup."; } catch(Exception e) { Error(e); } } };
            bottom.Controls.Add(progress); bottom.Controls.Add(cancel);
            Controls.Add(tabs); Controls.Add(output); Controls.Add(status); Controls.Add(bottom); Controls.Add(heading);
            if (setup) BuildSetup(setupCatalog); else BuildUsage();
            FormClosing+=delegate(object sender,FormClosingEventArgs e) {
                if (operation != null && operation.Running) { e.Cancel=true; MessageBox.Show(this,"An operation is running. Cancel it and wait for completion before closing.","Operation in progress"); }
            };
            FormClosed+=delegate { if (operation != null) operation.Dispose(); };
        }
        private static string ResolveRoot(string path) {
            string adjacent=Path.GetDirectoryName(path);
            if (File.Exists(Path.Combine(adjacent,".whas-installation.json"))) return adjacent;
            string marker=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".windows-hybrid-agentic-stack","bin","install-root.txt");
            if (File.Exists(marker)) return File.ReadAllText(marker).Trim();
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),"AI","WindowsHybridAgenticStack");
        }
        private FlowLayoutPanel Page(string name) {
            TabPage page=new TabPage(name); page.Padding=new Padding(18);
            FlowLayoutPanel flow=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true};
            page.Controls.Add(flow); tabs.TabPages.Add(page); return flow;
        }
        private void TextLine(FlowLayoutPanel page,string text,int height) { page.Controls.Add(new Label {Text=text,Width=840,Height=height,Margin=new Padding(0,6,0,5)}); }
        private Button Button(FlowLayoutPanel page,string text,Action click) {
            Button button=new Button {Text=text,AutoSize=true,MinimumSize=new Size(180,34),Margin=new Padding(0,8,10,3)};
            button.Click+=delegate { try { click(); } catch(Exception e) { Error(e); } }; page.Controls.Add(button); actions.Add(button); return button;
        }
        private ComboBox Choice(FlowLayoutPanel page,string label,IEnumerable<string> choices) {
            TextLine(page,label,24); var box=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList,Width=400};
            box.Items.AddRange(choices.Cast<object>().ToArray()); if(box.Items.Count>0) box.SelectedIndex=0; page.Controls.Add(box); return box;
        }
        private void Error(Exception error) { status.Text="Failed: "+error.Message; MessageBox.Show(this,error.Message,"WHAS",MessageBoxButtons.OK,MessageBoxIcon.Error); }
        private void Ui(Action work) { try { if (!IsDisposed && IsHandleCreated) BeginInvoke(work); } catch(InvalidOperationException) {} }
        private void Run(string file,IEnumerable<string> arguments,Action<int,string> completed) {
            if (operation != null && operation.Running) throw new InvalidOperationException("Wait for the current operation.");
            if(workspace!=null && !Directory.Exists(workspace.Text)) throw new DirectoryNotFoundException("Choose an existing workspace folder.");
            if (operation != null) operation.Dispose();
            foreach(Control button in actions) button.Enabled=false;
            progress.Style=ProgressBarStyle.Marquee; status.Text="Starting operation…"; output.Clear();
            var result=new StringBuilder(); operation=new GuiProcess();
            try {
                operation.Start(file,arguments,delegate(string line,bool error) {
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
                    progress.Style=ProgressBarStyle.Continuous; cancel.Enabled=false;
                    foreach(Control button in actions) button.Enabled=true;
                    status.Text=code==0 ? "Completed" : "Stopped or failed (exit "+code+"). Review details; changes may remain.";
                    if(completed != null) completed(code,result.ToString());
                    UpdateVoiceActions();
                }); },null,workspace==null ? null : Path.GetFullPath(workspace.Text));
                cancel.Enabled=operation.CanCancel;
            } catch { foreach(Control button in actions) button.Enabled=true; progress.Style=ProgressBarStyle.Continuous; cancel.Enabled=false; throw; }
        }
        private string Cli() {
            string bin=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".windows-hybrid-agentic-stack","bin");
            string marker=Path.Combine(bin,"install-root.txt");
            if (!File.Exists(marker) || !String.Equals(File.ReadAllText(marker).Trim(),root,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("This installation is not the active command registration. Open setup to inspect the selected installation.");
            return Path.Combine(bin,"whas.exe");
        }
        private void Command(IEnumerable<string> args,Action<int,string> done) { Run(Cli(),args,done); }
        private void BuildSetup(string catalog) {
            var select=Page("1. Choose");
            TextLine(select,"Choose components, then select models and speech engines. Existing installations use the same ownership and cleanup rules.",44);
            foreach(var pair in new[]{Tuple.Create(cloud,"Cloud agents"),Tuple.Create(local,"Local agents (Ollama)"),Tuple.Create(voice,"Speech output")}) {
                pair.Item1.Text=pair.Item2; pair.Item1.Width=500; pair.Item1.Checked=true; select.Controls.Add(pair.Item1);
            }
            TextLine(select,"Installation directory",24); destination.Text=root; destination.Width=760; select.Controls.Add(destination);
            Button(select,"Choose folder…",delegate { using(var picker=new FolderBrowserDialog()) { picker.SelectedPath=destination.Text; if(picker.ShowDialog(this)==DialogResult.OK) destination.Text=picker.SelectedPath; } });
            defaultLocation=Choice(select,"Default request location",new[]{"automatic","cloud","local"});
            Button(select,"Next: models and engines",delegate { tabs.SelectedIndex=1; });
            var components=Page("2. Models & engines");
            TextLine(components,"Local models — select downloads, then choose a default. Existing models are reused. Requirements and download sizes vary by model and quantization.",48);
            models.Width=550; models.Height=78; models.CheckOnClick=true;
            models.Items.Add("qwen3:8b",true); models.Items.Add("qwen2.5:1.5b",false); components.Controls.Add(models);
            var custom=new TextBox {Width=550}; components.Controls.Add(custom);
            Button(components,"Add model name",delegate { string value=custom.Text.Trim(); if(!Regex.IsMatch(value,"^[A-Za-z0-9][A-Za-z0-9._/:-]*$")) throw new ArgumentException("Enter a valid Ollama model name."); if(!models.Items.Contains(value)) models.Items.Add(value,true); UpdateModels(); });
            defaultModel.Width=400; defaultModel.DropDownStyle=ComboBoxStyle.DropDownList; components.Controls.Add(defaultModel);
            models.ItemCheck+=delegate { BeginInvoke((Action)UpdateModels); }; UpdateModels();
            TextLine(components,"Speech engines — the default starts on demand. Other installed engines remain selectable. Review licences before downloading.",44);
            engines.Width=700; engines.Height=84; engines.CheckOnClick=true;
            foreach(Dictionary<string,object> engine in json.Deserialize<object[]>(catalog)) {
                string id=Convert.ToString(engine["id"]); engineIds.Add(id);
                engines.Items.Add(id+" — "+engine["license"],id=="chatterbox-turbo");
            }
            components.Controls.Add(engines); defaultEngine.Width=400; defaultEngine.DropDownStyle=ComboBoxStyle.DropDownList; components.Controls.Add(defaultEngine);
            engines.ItemCheck+=delegate { BeginInvoke((Action)UpdateEngines); }; UpdateEngines();
            Button(components,"Next: prerequisite checks",delegate { tabs.SelectedIndex=2; });
            var checks=Page("3. Check");
            TextLine(checks,"Checks are read-only. Install missing external prerequisites yourself using the links below, then select Check again. A passing check is required before installation.",62);
            checkGrid=new DataGridView {Width=840,Height=190,ReadOnly=true,AllowUserToAddRows=false,AllowUserToDeleteRows=false,RowHeadersVisible=false,AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill,BackgroundColor=Color.White};
            foreach(string title in new[]{"Component","Required","Status","Details"}) checkGrid.Columns.Add(title,title); checkGrid.Columns[3].FillWeight=300; checks.Controls.Add(checkGrid);
            Button(checks,"Check again",delegate { var selection=Selection(); checkGrid.Rows.Clear(); checkedSelection=String.Join("\n",selection); Run(executable,new[]{"--check"}.Concat(selection),delegate(int code,string text) { checkPassed=code==0; if(checkPassed) status.Text="Prerequisites passed. Continue to Review & install."; }); });
            Link(checks,"Python 3.11","https://www.python.org/downloads/release/python-3119/");
            Link(checks,"Visual C++ x64 runtime","https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist");
            Link(checks,"NVIDIA drivers (optional CUDA)","https://www.nvidia.com/Download/index.aspx");
            Link(checks,"OpenCode installation","https://opencode.ai/docs/"); Link(checks,"Ollama installation","https://ollama.com/download/windows");
            var install=Page("4. Review & install");
            TextLine(install,"Review prints the exact backend plan without changes. Installation downloads the selected dependencies/models and registers both command-line and graphical interfaces.",64);
            Button(install,"Review selection",delegate { Run(executable,new[]{"--plan"}.Concat(Selection()),null); });
            Button(install,"Install selected components",delegate {
                var selection=Selection(); if(!checkPassed || checkedSelection!=String.Join("\n",selection)) throw new InvalidOperationException("Run prerequisite checks for the current selection first.");
                if(MessageBox.Show(this,"Install the reviewed selection and its downloads?","Confirm installation",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes) return;
                Run(executable,new[]{"--install","--yes"}.Concat(selection),delegate(int code,string text) { if(code==0) status.Text="Installed. Open WHAS from the installation folder. Existing terminals must refresh PATH or reopen."; });
            });
            var uninstall=Page("Uninstall");
            TextLine(uninstall,"Use the installation directory on the Choose tab. Preview first: unchanged owned files and installer-created models are removed; personal voices, agent data, modified files and external prerequisites are preserved.",82);
            retainModels.Text="Retain installer-created Ollama models"; retainModels.Width=600; uninstall.Controls.Add(retainModels);
            Button(uninstall,"Preview removal",delegate { Run(executable,Removal(false),null); });
            Button(uninstall,"Uninstall…",delegate {
                if(MessageBox.Show(this,"Remove this tracked installation? Personal/modified files are preserved. Review the preview before proceeding.","Confirm uninstall",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes) return;
                Run(executable,Removal(true),delegate(int code,string text) { if(code==0) status.Text="Uninstallation complete. Review the receipt; reopen existing terminals to refresh PATH."; });
            });
        }
        private void Link(FlowLayoutPanel page,string title,string uri) {
            var link=new LinkLabel {Text=title,AutoSize=true,Margin=new Padding(0,5,0,5)}; link.LinkClicked+=delegate { Process.Start(new ProcessStartInfo(uri){UseShellExecute=true}); }; page.Controls.Add(link);
        }
        private void UpdateModels() { string selected=Convert.ToString(defaultModel.SelectedItem); defaultModel.Items.Clear(); foreach(object item in models.CheckedItems) defaultModel.Items.Add(item); if(defaultModel.Items.Contains(selected)) defaultModel.SelectedItem=selected; else if(defaultModel.Items.Count>0) defaultModel.SelectedIndex=0; }
        private void UpdateEngines() { string selected=Convert.ToString(defaultEngine.SelectedItem); defaultEngine.Items.Clear(); foreach(int i in engines.CheckedIndices) defaultEngine.Items.Add(engineIds[i]); if(defaultEngine.Items.Contains(selected)) defaultEngine.SelectedItem=selected; else if(defaultEngine.Items.Count>0) defaultEngine.SelectedIndex=0; }
        private string[] Selection() {
            var args=new List<string>{"--core","--install-path",Path.GetFullPath(destination.Text)};
            if(defaultLocation.SelectedIndex>0) args.AddRange(new[]{"--default-location",Convert.ToString(defaultLocation.SelectedItem)});
            string existing=Path.Combine(destination.Text,"config","config.json"); if(File.Exists(existing)) args.AddRange(new[]{"--config",existing});
            if(cloud.Checked) args.Add("--cloud");
            if(local.Checked) { if(defaultModel.SelectedItem==null) throw new ArgumentException("Choose a default local model."); args.AddRange(new[]{"--local","--local-models",String.Join(",",models.CheckedItems.Cast<string>()),"--default-local-model",Convert.ToString(defaultModel.SelectedItem)}); }
            if(voice.Checked) { if(defaultEngine.SelectedItem==null) throw new ArgumentException("Choose a default speech engine."); var ids=engines.CheckedIndices.Cast<int>().Select(i=>engineIds[i]).ToList(); string chosen=Convert.ToString(defaultEngine.SelectedItem); ids.Remove(chosen); ids.Insert(0,chosen); args.AddRange(new[]{"--voice","--tts-engine",String.Join(",",ids)}); }
            return args.ToArray();
        }
        private string[] Removal(bool apply) { var args=new List<string>{"--uninstall","--install-path",Path.GetFullPath(destination.Text)}; if(retainModels.Checked) args.Add("--retain-managed-models"); if(apply) args.AddRange(new[]{"--apply","--yes"}); return args.ToArray(); }
        private void BuildUsage() {
            var use=Page("Ask & chat");
            TextLine(use,"Choose a question, task or contextual conversation. Local/cloud and runtime selections apply to this request; change saved defaults in Settings.",48);
            TextLine(use,"Workspace — agent tools operate in this folder",24);
            string documents=Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            workspace=new TextBox {Width=800,Text=Directory.Exists(documents)?documents:Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)}; use.Controls.Add(workspace);
            Button(use,"Choose workspace…",delegate { using(var picker=new FolderBrowserDialog()) { picker.SelectedPath=workspace.Text; if(picker.ShowDialog(this)==DialogResult.OK) workspace.Text=picker.SelectedPath; } });
            action=Choice(use,"Operation",new[]{"ask","perform","chat"}); route=Choice(use,"Location",new[]{"default","local","cloud"}); runtime=Choice(use,"Runtime",new[]{"default","opencode"});
            Button(use,"Refresh available runtimes",delegate { RefreshRuntimes(); });
            conversation=new TextBox {Multiline=true,ReadOnly=true,Width=800,Height=150,ScrollBars=ScrollBars.Vertical}; use.Controls.Add(conversation);
            prompt=new TextBox {Multiline=true,Width=800,Height=85,ScrollBars=ScrollBars.Vertical}; use.Controls.Add(prompt);
            session=new TextBox {Width=500}; TextLine(use,"Session ID (chat only; blank starts a new conversation)",24); use.Controls.Add(session);
            speak=new CheckBox {Text="Speak the answer",Width=350}; use.Controls.Add(speak);
            Button(use,"New conversation",delegate { session.Clear(); prompt.Clear(); output.Clear(); conversation.Clear(); });
            Button(use,"Send",delegate {
                if(String.IsNullOrWhiteSpace(prompt.Text)) throw new ArgumentException("Enter a question or message.");
                bool chatting=Convert.ToString(action.SelectedItem)=="chat"; string message=prompt.Text;
                var args=new List<string>{Convert.ToString(action.SelectedItem)};
                if(route.SelectedIndex>0) args.Add("--"+route.SelectedItem);
                if(runtime.SelectedIndex>0) args.AddRange(new[]{"--runtime",Convert.ToString(runtime.SelectedItem)});
                args.Add(speak.Checked?"--voice":"--no-voice");
                if(action.SelectedItem.ToString()=="chat") { if(session.Text.Trim().Length>0) args.AddRange(new[]{"--session",session.Text.Trim()}); args.AddRange(new[]{"--message",prompt.Text}); }
                else args.Add(prompt.Text);
                Run(Cli(),args,delegate(int code,string text) { if(code==0) { string answer=text.Trim(); if(chatting) { try { var response=json.Deserialize<Dictionary<string,object>>(text); session.Text=Convert.ToString(response["sessionId"]); answer=Convert.ToString(response["answer"]); } catch { status.Text="Received an invalid conversation response."; return; } } conversation.AppendText("You: "+message+Environment.NewLine+"Assistant: "+answer+Environment.NewLine+Environment.NewLine); output.Clear(); prompt.Clear(); } });
            });
            BuildSettings(); BuildVoice();
            var accounts=Page("Accounts");
            TextLine(accounts,"Use OpenCode's own graphical provider interface for supported account sign-in and API-key connections. Provider authentication is shared with its CLI; WHAS does not copy keys into settings or installation records.",88);
            Button(accounts,"Open provider account interface",delegate { using(var manager=new ProviderWindow(root)) manager.ShowDialog(this); });
            var agents=Page("Agents & models");
            TextLine(agents,"OpenCode supplies restricted questions, tool-enabled tasks and contextual sessions.",66);
            Button(agents,"List agent runtimes",delegate { Command(new[]{"agent","list"},null); });
            Button(agents,"List local models",delegate { Command(new[]{"model","list"},null); });
            Button(agents,"Open setup / model selection",delegate { OpenSetup(); });
            var memory=Page("Sessions & memory");
            TextLine(memory,"Chat resumes only an explicit session ID. A blank session starts fresh. One-shot ask/perform do not resume previous conversations. Sessions are isolated between local and cloud use.",100);
            TextLine(memory,"Personal agent data is preserved during uninstall. Manage native runtime memory through its documented interface. WHAS does not silently enable a gateway, schedule, memory upload or cross-runtime history sharing.",90);
            Button(memory,"List WHAS conversation associations",delegate { Command(new[]{"session","list"},null); });
            var sessionRuntime=Choice(memory,"Runtime for association removal",new[]{"opencode"});
            var forget=new TextBox {Width=500}; TextLine(memory,"Session ID to forget (native history and memory remain)",24); memory.Controls.Add(forget);
            Button(memory,"Forget association…",delegate { if(MessageBox.Show(this,"Forget only this WHAS association? This does not delete native history or persistent memory.","Forget association",MessageBoxButtons.YesNo)!=DialogResult.Yes) return; Command(new[]{"session","forget",Convert.ToString(sessionRuntime.SelectedItem),forget.Text.Trim(),"--yes"},null); });
            Button(memory,"Open installation folder",delegate { Process.Start(new ProcessStartInfo(root){UseShellExecute=true}); });
            var maintenance=Page("Maintenance");
            TextLine(maintenance,"Install, maintain or uninstall through the same setup application, regardless of whether this installation began with PowerShell or an EXE.",60);
            Button(maintenance,"Open setup / uninstall",delegate { OpenSetup(); });
            Button(maintenance,"Open installation guide",delegate { string doc=Path.Combine(root,"docs","installation.md"); Process.Start(new ProcessStartInfo(File.Exists(doc)?doc:"https://github.com/thestonefox/windows-hybrid-agentic-stack"){UseShellExecute=true}); });
        }
        private void OpenSetup() { string file=Path.Combine(root,"whas-setup.exe"); if(!File.Exists(file)) throw new FileNotFoundException("The graphical setup component is missing; repair the installation."); Process.Start(new ProcessStartInfo(file){UseShellExecute=true}); }
        private void RefreshRuntimes() {
            Command(new[]{"agent","list"},delegate(int code,string text) {
                if(code!=0) return;
                string selected=Convert.ToString(runtime.SelectedItem); runtime.Items.Clear(); runtime.Items.Add("default");
                var saved=(ComboBox)settings["runtime"]; string savedChoice=Convert.ToString(saved.SelectedItem); saved.Items.Clear(); saved.Items.Add("none");
                foreach(string line in text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries)) { var entry=json.Deserialize<Dictionary<string,object>>(line); if((bool)entry["Available"]) { string id=Convert.ToString(entry["Id"]); runtime.Items.Add(id); saved.Items.Add(id); } }
                runtime.SelectedItem=runtime.Items.Contains(selected)?selected:"default"; saved.SelectedItem=saved.Items.Contains(savedChoice)?savedChoice:"none";
            });
        }
        private void BuildSettings() {
            var page=Page("Settings"); TextLine(page,"Shared configuration — changes apply to new requests in both CLI and GUI. Existing conversations and running services are not silently switched.",48);
            settings["location"]=Choice(page,"Default location",new[]{"cloud","local"});
            settings["runtime"]=Choice(page,"Default runtime",new[]{"none","opencode"});
            foreach(string key in new[]{"cloud.model","local.model","speech.voice"}) { TextLine(page,key,24); var box=new TextBox {Width=540}; settings[key]=box; page.Controls.Add(box); }
            settings["speech.enabled"]=Choice(page,"Speech by default",new[]{"false","true"});
            settings["speech.device"]=Choice(page,"Speech device (takes effect on engine installation)",new[]{"auto","cpu","cuda"});
            settings["speech.autoStart"]=Choice(page,"Start speech on demand",new[]{"true","false"});
            Button(page,"Reload shared settings",delegate { ReloadSettings(); });
            var settingPicker=Choice(page,"Setting to save",settings.Keys.ToArray());
            Button(page,"Save selected setting",delegate { string name=Convert.ToString(settingPicker.SelectedItem); var control=settings[name]; string value=control is ComboBox ? Convert.ToString(((ComboBox)control).SelectedItem) : control.Text; Command(new[]{"configure","--set",name,value},null); });
            TextLine(page,"Save one setting at a time. Reload before editing after CLI changes. No component is installed by saving a default.",48);
            Shown+=delegate { if(!rendering) { try { ReloadSettings(); } catch(Exception e) { status.Text=e.Message; } } };
        }
        private void ReloadSettings() {
            Command(new[]{"configure","--show"},delegate(int code,string text) {
                if(code!=0) return;
                try {
                    var config=json.Deserialize<Dictionary<string,object>>(text);
                    var interaction=(Dictionary<string,object>)config["interaction"];
                    var agents=(Dictionary<string,object>)config["agents"]; var tts=(Dictionary<string,object>)config["tts"];
                    SetControl("location",interaction["location"]); SetControl("runtime",interaction["runtime"]); SetControl("speech.enabled",interaction["speech"]);
                    SetControl("cloud.model",((Dictionary<string,object>)agents["cloud"])["model"]); SetControl("local.model",((Dictionary<string,object>)agents["local"])["model"]);
                    SetControl("speech.voice",tts["defaultVoice"]); SetControl("speech.device",tts["device"]); SetControl("speech.autoStart",tts["autoStart"]);
                } catch(Exception e) { Error(e); }
            });
        }
        private void SetControl(string key,object value) { string text=key=="runtime" && value==null ? "none" : value is bool ? value.ToString().ToLowerInvariant() : Convert.ToString(value); var control=settings[key]; if(control is ComboBox) ((ComboBox)control).SelectedItem=text; else control.Text=text; }
        private void BuildVoice() {
            var page=Page("Voice");
            voiceEngine=Choice(page,"Speech engine",new string[0]); voiceName=Choice(page,"Voice / reference name",new[]{"default"});
            voiceSupport.Width=800; voiceSupport.Height=50; page.Controls.Add(voiceSupport);
            Button(page,"Refresh engines and voices",delegate { RefreshVoice(); });
            Button(page,"Install selected engine…",delegate { if(MessageBox.Show(this,"Install the selected engine and its private dependencies?","Install speech",MessageBoxButtons.YesNo)!=DialogResult.Yes) return; Command(new[]{"tts","install",Convert.ToString(voiceEngine.SelectedItem),"--yes"},null); });
            Button(page,"Set default engine",delegate { Command(new[]{"tts","default",Convert.ToString(voiceEngine.SelectedItem)},null); });
            Button(page,"Preview engine removal",delegate { Command(new[]{"tts","uninstall",Convert.ToString(voiceEngine.SelectedItem)},null); });
            Button(page,"Remove selected engine…",delegate { if(MessageBox.Show(this,"Remove unchanged engine files? Personal references remain. Select another default first if necessary.","Remove speech engine",MessageBoxButtons.YesNo)!=DialogResult.Yes) return; Command(new[]{"tts","uninstall",Convert.ToString(voiceEngine.SelectedItem),"--apply","--yes"},null); });
            var name=new TextBox {Width=500}; TextLine(page,"Name for a new reference sample",24); page.Controls.Add(name);
            var add=Button(page,"Add WAV reference…",delegate {
                string engine=Convert.ToString(voiceEngine.SelectedItem); var entry=voiceInventory[engine];
                if(!(bool)entry["voiceCloning"]) throw new InvalidOperationException("This strategy does not support reference voice samples.");
                using(var picker=new OpenFileDialog {Filter="WAV recordings (*.wav)|*.wav",CheckFileExists=true}) {
                    if(picker.ShowDialog(this)!=DialogResult.OK) return;
                    if((bool)entry["transcriptRequired"] && (!File.Exists(Path.ChangeExtension(picker.FileName,".txt")) || String.IsNullOrWhiteSpace(File.ReadAllText(Path.ChangeExtension(picker.FileName,".txt"))))) throw new InvalidOperationException("F5 requires a matching UTF-8 .txt transcript beside the WAV. Add it before importing.");
                    Command(new[]{"tts","voice-add","--Path",picker.FileName,"--Name",name.Text,"--engine",engine},null);
                }
            });
            voiceAdd=add;
            Button(page,"Preview selected voice",delegate { Command(new[]{"tts","say","This is a preview of the selected voice.","--Voice",Convert.ToString(voiceName.SelectedItem),"--engine",Convert.ToString(voiceEngine.SelectedItem)},null); });
            Button(page,"Set default voice",delegate { Command(new[]{"configure","--set","speech.voice",Convert.ToString(voiceName.SelectedItem),"--engine",Convert.ToString(voiceEngine.SelectedItem)},null); });
            voiceRemove=Button(page,"Remove selected reference…",delegate {
                string selected=Convert.ToString(voiceName.SelectedItem); if(selected=="default") throw new InvalidOperationException("The built-in voice cannot be removed.");
                if(MessageBox.Show(this,"Delete this personal reference and matching transcript?","Delete reference",MessageBoxButtons.YesNo)!=DialogResult.Yes) return;
                Command(new[]{"tts","voice-remove","--Name",selected,"--engine",Convert.ToString(voiceEngine.SelectedItem),"--yes"},null);
            });
            voiceEngine.SelectedIndexChanged+=delegate { if(voiceEngine.SelectedItem==null) return; var entry=voiceInventory[Convert.ToString(voiceEngine.SelectedItem)]; bool supported=(bool)entry["voiceCloning"]; add.Enabled=supported; voiceSupport.Text=!(bool)entry["installed"] ? "Available; install this engine before use." : supported ? ((bool)entry["transcriptRequired"] ? "Reference WAV and matching UTF-8 transcript required. Adding a sample conditions speech; it does not train weights." : "Reference WAV supported. Adding a sample conditions speech; it does not train weights.") : "Built-in voices only. This strategy does not support reference-sample cloning."; voiceName.Items.Clear(); foreach(object item in (object[])entry["voices"]) voiceName.Items.Add(item); if(voiceName.Items.Count>0) voiceName.SelectedIndex=0; };
            voiceName.SelectedIndexChanged+=delegate { UpdateVoiceActions(); };
            UpdateVoiceActions();
        }
        private void UpdateVoiceActions() {
            if(voiceAdd==null || voiceRemove==null) return;
            bool supported=voiceEngine!=null && voiceEngine.SelectedItem!=null && voiceInventory.ContainsKey(Convert.ToString(voiceEngine.SelectedItem));
            if(supported) { var entry=voiceInventory[Convert.ToString(voiceEngine.SelectedItem)]; supported=(bool)entry["installed"] && (bool)entry["voiceCloning"]; }
            voiceAdd.Enabled=supported && (operation==null || !operation.Running);
            voiceRemove.Enabled=voiceAdd.Enabled && voiceName.SelectedItem!=null && Convert.ToString(voiceName.SelectedItem)!="default";
        }
        private void RefreshVoice() {
            Command(new[]{"tts","inventory"},delegate(int code,string text) {
                if(code!=0) return; try {
                    voiceInventory.Clear(); voiceEngine.Items.Clear();
                    foreach(Dictionary<string,object> item in json.Deserialize<object[]>(text)) { string id=Convert.ToString(item["id"]); voiceInventory[id]=item; voiceEngine.Items.Add(id); }
                    if(voiceEngine.Items.Count>0) voiceEngine.SelectedIndex=0;
                } catch(Exception e) { Error(e); }
            });
        }
        public void Render(string file) { rendering=true; CreateControl(); PerformLayout(); using(var bitmap=new Bitmap(Width,Height)) { DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height)); bitmap.Save(file); } }
    }

    public static class GuiHost {
        [STAThread] public static int Main(string[] args) {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            string file=System.Reflection.Assembly.GetExecutingAssembly().Location;
            using(var window=new WhasWindow(false,file,null)) {
                if(args.Length==2 && args[0]=="--render") { window.Render(args[1]); return 0; }
                Application.Run(window); return 0;
            }
        }
    }
}

// WPF presentation over the existing shared action controller. No WinForms
// controls are hosted or shown in this window; both interfaces use one backend.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using F=System.Windows.Forms;

namespace WindowsHybridAgenticStack {
    public sealed class FluentWindow : Window, IDisposable {
        private readonly WhasWindow controller;
        private readonly Grid shell=new Grid();
        private readonly ListBox navigation=new ListBox();
        private readonly DockPanel sidebar=new DockPanel();
        private readonly Grid appHeader=new Grid();
        private readonly TextBlock appTitle=new TextBlock();
        private readonly Button configurationToggle=new Button();
        private readonly ContentControl pageHost=new ContentControl();
        private readonly TextBlock status=new TextBlock();
        private readonly TextBox log=new TextBox();
        private readonly Border logPanel=new Border();
        private readonly Button cancel=new Button();
        private readonly Button logToggle=new Button();
        private readonly Button clearLog=new Button();
        private readonly Button setupNext=new Button();
        private F.Button setupNextSource;
        private string setupPage;
        private readonly ProgressBar activity=new ProgressBar();
        private readonly List<Action> bindings=new List<Action>();
        private readonly List<Button> prerequisiteActions=new List<Button>();
        private readonly Dictionary<string,object>[] strategies;
        private readonly DispatcherTimer timer=new DispatcherTimer();
        private StackPanel checkRows;
        private TextBlock checkSummary;
        private string lastChecks="", lastStatus="";
        private bool navigating, rendering, disposed, logOpen, windowClosed;
        public bool Busy {get{return controller.IsBusy;}}
        private sealed class NativeOwner : F.IWin32Window {public IntPtr Handle {get;set;}}
        private sealed class ChatRow {
            public WhasWindow.ConversationReply Reply;
            public TextBox Question,Answer;
            public Grid Response;
            public TextBlock Waiting;
        }
        private sealed class ChoiceItem {
            public string Value;
            public string Display;
            public override string ToString() {
                if(Display!=null) return Display;
                switch(Value) {
                    case "":return "Use OpenCode default";
                    case "cloud":return "Cloud";case "local":return "This PC";
                    case "system":return "System theme";case "light":return "Light";case "dark":return "Dark";
                    case "default":return "Use saved default";case "none":return "None";case "opencode":return "OpenCode";
                    case "chatterbox-turbo":return "Chatterbox Turbo";case "piper-tts":return "Piper TTS";case "f5-tts":return "F5-TTS";
                    case "true":return "On";case "false":return "Off";case "ask":return "One-off question";case "perform":return "Run a task";case "chat":return "Conversation";
                    default:return Value;
                }
            }
        }
        public FluentWindow(bool setup,string executable,string catalog,string root,string theme):this(setup,executable,catalog,root,theme,null) {}
        public FluentWindow(bool setup,string executable,string catalog,string root,string theme,string preferencesPath) {
            Title="WHAS"; Width=1160; Height=880; MinWidth=940; MinHeight=680;
            FontFamily=new FontFamily("Segoe UI"); FontSize=14; Background=Brush("#F3F3F3");
            shell.Background=Background;
            WindowStartupLocation=WindowStartupLocation.CenterScreen; UseLayoutRounding=true;
            var dictionary=(ResourceDictionary)XamlReader.Parse(theme); shell.Resources=dictionary;
            Icon=(ImageSource)dictionary["BrandIcon"];
            controller=new WhasWindow(setup,executable,catalog,root,preferencesPath); controller.PreparePresentation(false);
            ApplyTheme();controller.AppearanceChanged+=AppearanceChanged;
            Microsoft.Win32.SystemEvents.UserPreferenceChanged+=SystemThemeChanged;
            strategies=(new JavaScriptSerializer().Deserialize<object[]>(catalog??"[]")).Cast<Dictionary<string,object>>().ToArray();
            shell.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(224)});
            shell.ColumnDefinitions.Add(new ColumnDefinition());
            shell.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});shell.RowDefinitions.Add(new RowDefinition()); shell.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
            sidebar.Margin=new Thickness(0,20,8,12);Grid.SetRow(sidebar,1);
            var brand=new StackPanel {Margin=new Thickness(24,4,16,28)};
            var brandRow=new StackPanel {Orientation=Orientation.Horizontal};
            brandRow.Children.Add(new Border {Background=Brush("#173E76"),CornerRadius=new CornerRadius(8),Width=32,Height=32,Child=new TextBlock {Text="W",Foreground=Brushes.White,FontSize=18,FontWeight=FontWeights.SemiBold,HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center}});
            brandRow.Children.Add(new TextBlock {Text="WHAS",FontSize=19,FontWeight=FontWeights.SemiBold,Margin=new Thickness(10,2,0,0)});
            brand.Children.Add(brandRow); brand.Children.Add(Text("Your AI workspace",12,true,new Thickness(0,10,0,0)));
            DockPanel.SetDock(brand,Dock.Top); sidebar.Children.Add(brand); sidebar.Children.Add(navigation); shell.Children.Add(sidebar);
            appHeader.Margin=new Thickness(24,24,24,0);appHeader.ColumnDefinitions.Add(new ColumnDefinition());appHeader.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            appTitle.FontSize=30;appTitle.FontWeight=FontWeights.SemiBold;appHeader.Children.Add(appTitle);
            configurationToggle.FontFamily=new FontFamily("Segoe MDL2 Assets");configurationToggle.FontSize=20;configurationToggle.Width=40;configurationToggle.Height=40;configurationToggle.Style=(Style)shell.Resources["Quiet"];configurationToggle.Click+=delegate {SelectPage(controller.PresentationPages.SelectedIndex==0?1:0);};Grid.SetColumn(configurationToggle,1);appHeader.Children.Add(configurationToggle);Grid.SetColumn(appHeader,1);shell.Children.Add(appHeader);
            pageHost.Margin=new Thickness(24,16,24,16);pageHost.HorizontalContentAlignment=HorizontalAlignment.Stretch;pageHost.VerticalContentAlignment=VerticalAlignment.Stretch;Grid.SetRow(pageHost,1); Grid.SetColumn(pageHost,1); shell.Children.Add(pageHost);
            BuildFooter(); Content=shell;
            navigation.SelectionChanged+=delegate {if(!navigating && navigation.SelectedIndex>=0) SelectPage((int)((ListBoxItem)navigation.SelectedItem).Tag);};
            controller.PresentationPages.SelectedIndexChanged+=delegate {if(!navigating && !controller.PresentationRebuilding) SelectPage(controller.PresentationPages.SelectedIndex);};
            controller.PresentationChanged+=RebuildNavigation;
            SourceInitialized+=delegate {controller.DialogOwner=new NativeOwner {Handle=new WindowInteropHelper(this).Handle};};
            Loaded+=delegate {if(!rendering) controller.LoadPresentationSettings();};
            Closing+=delegate(object sender,System.ComponentModel.CancelEventArgs e) {if(Busy) {e.Cancel=true; MessageBox.Show(this,controller.IsAssistantRequestRunning?"A request is running. Cancel it and wait for completion before closing.":"An operation is running. Wait for completion before closing.","Operation in progress",MessageBoxButton.OK,MessageBoxImage.Information);}};
            Closed+=delegate {windowClosed=true;Dispose();};
            timer.Interval=TimeSpan.FromMilliseconds(150); timer.Tick+=delegate {Sync();}; timer.Start();
            RebuildNavigation();
        }
        private static SolidColorBrush Brush(string colour) {return (SolidColorBrush)new BrushConverter().ConvertFromString(colour);}
        private TextBlock Text(string value,double size=14,bool muted=false,Thickness? margin=null) {
            var text=new TextBlock {Text=value,FontSize=size,TextWrapping=TextWrapping.Wrap,Margin=margin??new Thickness(0)};text.SetResourceReference(TextBlock.ForegroundProperty,muted?"Muted":"Ink");return text;
        }
        private TextBox SelectableText(string value,string label,Thickness? margin=null) {
            var text=new TextBox {Text=value??"",FontSize=14,Style=(Style)shell.Resources["SelectableText"],Margin=margin??new Thickness(0)};
            text.PreviewMouseWheel+=delegate(object sender,MouseWheelEventArgs e) {
                DependencyObject parent=VisualTreeHelper.GetParent(text);while(parent!=null && !(parent is ScrollViewer)) parent=VisualTreeHelper.GetParent(parent);
                if(parent!=null) {e.Handled=true;((ScrollViewer)parent).RaiseEvent(new MouseWheelEventArgs(e.MouseDevice,e.Timestamp,e.Delta) {RoutedEvent=UIElement.MouseWheelEvent});}
            };
            Accessible(text,label);return text;
        }
        private static void UpdateSelectableText(TextBox text,string value) {
            value=value??"";if(text.Text==value) return;
            int start=text.SelectionStart,length=text.SelectionLength;
            text.Text=value;start=Math.Min(start,value.Length);text.Select(start,Math.Min(length,value.Length-start));
        }
        private void ApplyTheme() {
            bool dark=controller.Preferences.Theme=="dark";
            if(controller.Preferences.Theme=="system") {using(var key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) dark=key!=null && Convert.ToInt32(key.GetValue("AppsUseLightTheme",1))==0;}
            string[] keys={"Canvas","Surface","Ink","Muted","FrameBorder","InputBorder","ControlOutline","SelectionFill","SwitchTrack","ScrollThumb","ScrollThumbHover","Accent","AccentForeground"};
            string[] light={"#F3F3F3","#FFFFFF","#1B1B1B","#616161","#D1D1D1","#BDBDBD","#858585","#E4EDF6","#F9F9F9","#B0B0B0","#767676","#173E76","#FFFFFF"};
            string[] night={"#202020","#2B2B2B","#F5F5F5","#C0C0C0","#484848","#666666","#A0A0A0","#243F53","#383838","#777777","#A0A0A0","#60CDFF","#101010"};
            for(int i=0;i<keys.Length;i++) shell.Resources[keys[i]]=Brush((dark?night:light)[i]);
            Background=(Brush)shell.Resources["Canvas"];shell.Background=Background;Foreground=(Brush)shell.Resources["Ink"];
            status.SetResourceReference(TextBlock.ForegroundProperty,"Muted");
        }
        private void AppearanceChanged() {ApplyTheme();Navigate(controller.PresentationPages.SelectedIndex);}
        private void SystemThemeChanged(object sender,Microsoft.Win32.UserPreferenceChangedEventArgs e) {if(!disposed && controller.Preferences.Theme=="system") Dispatcher.BeginInvoke((Action)delegate {if(!disposed) AppearanceChanged();});}
        private static void Accessible(DependencyObject control,string label) {System.Windows.Automation.AutomationProperties.SetName(control,label);}
        private Border Card(UIElement child,Thickness? padding=null) {var card=new Border {BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(8),Padding=padding??new Thickness(20,16,20,16),Margin=new Thickness(0,0,0,8),Child=child};card.SetResourceReference(Border.BackgroundProperty,"Surface");card.SetResourceReference(Border.BorderBrushProperty,"FrameBorder");return card;}
        private Button Action(string label,Action click,string style=null) {
            var button=new Button {Content=label,Margin=new Thickness(0,0,8,0)};
            if(style!=null) button.Style=(Style)shell.Resources[style];
            button.Click+=delegate {try{click(); Sync();}catch(Exception error){MessageBox.Show(this,error.Message,"WHAS",MessageBoxButton.OK,MessageBoxImage.Error);}};
            Accessible(button,label); return button;
        }
        private Button FindAction(string text) {
            foreach(F.TabPage page in controller.PresentationPages.TabPages) foreach(var button in Descendants(page).OfType<F.Button>()) if(button.Text==text) return BoundButton(button);
            throw new InvalidOperationException("Missing application action: "+text);
        }
        private Button BoundButton(F.Button source) {
            string label=source.Text;
            string style=label.StartsWith("Next:") || label=="Apply selected features" || label=="Check again" || label=="Send"?"Primary":null;
            var button=Action(label,delegate {if(label.StartsWith("Review") || label.StartsWith("Preview") || label.StartsWith("List ")) OpenLog(true); controller.InvokePresentationAction(source);},style);
            bindings.Add(delegate {button.IsEnabled=!source.IsDisposed && source.Enabled;}); return button;
        }
        private static IEnumerable<F.Control> Descendants(F.Control parent) {foreach(F.Control child in parent.Controls) {yield return child;foreach(var nested in Descendants(child)) yield return nested;}}
        private void BuildFooter() {
            var footer=new Grid {Margin=new Thickness(24,0,24,10),MinHeight=36}; footer.ColumnDefinitions.Add(new ColumnDefinition()); footer.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto}); footer.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            status.VerticalAlignment=VerticalAlignment.Center; status.FontSize=12; status.SetResourceReference(TextBlock.ForegroundProperty,"Muted"); status.TextTrimming=TextTrimming.CharacterEllipsis; status.TextWrapping=TextWrapping.NoWrap; status.Margin=new Thickness(0,0,16,0); footer.Children.Add(status);
            footer.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            clearLog.Content="Clear log";clearLog.Style=(Style)shell.Resources["Quiet"];clearLog.Visibility=Visibility.Collapsed;clearLog.Click+=delegate {controller.ClearActivityLog();log.Clear();};Grid.SetColumn(clearLog,2);footer.Children.Add(clearLog);
            logToggle.Content="Show activity log"; logToggle.Style=(Style)shell.Resources["Quiet"]; logToggle.Click+=delegate {OpenLog(!logOpen);}; Grid.SetColumn(logToggle,3); footer.Children.Add(logToggle);
            footer.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            setupNext.Style=(Style)shell.Resources["Primary"];setupNext.Margin=new Thickness(16,0,0,0);setupNext.Visibility=Visibility.Collapsed;
            double actionWidth=0;
            foreach(string label in new[]{"Choose Models & Engines","Check Prerequisites","Go to Apply Features","Apply selected features"}) {
                var measure=new Button {Content=label,Style=setupNext.Style,FontFamily=FontFamily,FontSize=FontSize};
                measure.Measure(new Size(Double.PositiveInfinity,Double.PositiveInfinity));actionWidth=Math.Max(actionWidth,measure.DesiredSize.Width);
            }
            setupNext.Width=Math.Ceiling(actionWidth);
            setupNext.Click+=delegate {if(setupNextSource!=null){if(setupPage=="Apply features")OpenLog(true);controller.InvokePresentationAction(setupNextSource);}};
            Grid.SetColumn(setupNext,4);footer.Children.Add(setupNext);
            cancel.Visibility=Visibility.Collapsed;
            log.IsReadOnly=true; log.AcceptsReturn=true; log.FontFamily=new FontFamily("Consolas"); log.FontSize=12; log.VerticalScrollBarVisibility=ScrollBarVisibility.Auto; log.HorizontalScrollBarVisibility=ScrollBarVisibility.Auto;
            logPanel.Child=log; logPanel.Height=160; logPanel.Margin=new Thickness(24,0,24,12); logPanel.Visibility=Visibility.Collapsed;
            var bottom=new StackPanel(); activity.Height=3; activity.IsIndeterminate=true; activity.Margin=new Thickness(0); bottom.Children.Add(logPanel); bottom.Children.Add(footer);bottom.Children.Add(activity);
            Grid.SetRow(bottom,2); Grid.SetColumnSpan(bottom,2); shell.Children.Add(bottom);
        }
        private void OpenLog(bool open) {logOpen=open;logPanel.Visibility=open?Visibility.Visible:Visibility.Collapsed;clearLog.Visibility=open?Visibility.Visible:Visibility.Collapsed;logToggle.Content=open?"Hide activity log":"Show activity log";}
        private void RebuildNavigation() {
            navigating=true; navigation.Items.Clear();
            bool installed=controller.PresentationPages.TabPages[0].Text=="Assistant";
            sidebar.Visibility=installed?Visibility.Collapsed:Visibility.Visible;shell.ColumnDefinitions[0].Width=new GridLength(installed?0:224);appHeader.Visibility=installed?Visibility.Visible:Visibility.Collapsed;
            for(int i=0;i<controller.PresentationPages.TabPages.Count;i++) {
                var page=controller.PresentationPages.TabPages[i];
                if((!installed && (page.Text!="Remove WHAS" || controller.HasRemovalTarget)) || page.Text=="Assistant" || page.Text=="Configuration") navigation.Items.Add(new ListBoxItem {Content=page.Text,Tag=i});
            }
            navigating=false; SelectPage(Math.Max(0,controller.PresentationPages.SelectedIndex));
        }
        public void SelectPage(int index) {
            if(index<0 || index>=controller.PresentationPages.TabPages.Count) return;
            navigating=true;
            navigation.SelectedIndex=controller.PresentationPages.TabPages[0].Text=="Assistant"?(index==0?0:1):navigation.Items.Cast<ListBoxItem>().ToList().FindIndex(x=>(int)x.Tag==index);
            navigating=false; Navigate(index);
        }
        private void Navigate(int index) {
            navigating=true; controller.PresentationPages.SelectedIndex=index; navigating=false;
            bindings.Clear(); prerequisiteActions.Clear(); checkRows=null; checkSummary=null; lastChecks="";
            var source=controller.PresentationPages.TabPages[index]; var stack=new StackPanel();
            bool installed=controller.PresentationPages.TabPages[0].Text=="Assistant";
            ConfigureSetupAction(installed?null:source.Text);
            appTitle.Text=index==0?"Assistant":"Configuration";
            configurationToggle.Content=index==0?"\uE713":"\uE72B";configurationToggle.ToolTip=index==0?"Configuration":"Back to Assistant";Accessible(configurationToggle,index==0?"Configuration":"Back to Assistant");
            if(installed && index==0) {pageHost.Content=BuildAssistant();Sync();return;}
            bool configuration=controller.PresentationPages.TabPages[0].Text=="Assistant" && index!=0;
            if(configuration) BuildConfigurationNavigation(stack,source.Text);
            string description=source.Text=="Features"?(installed?"Add, repair or remove features in your existing installation.":"Choose the features you want. You can add more later."):source.Text=="Models & engines"?"Choose your downloads and the defaults WHAS will use.":source.Text=="Prerequisites"?"Check that your PC is ready for the features you selected.":null;
            var header=new Grid {Margin=new Thickness(0,0,0,24)}; header.ColumnDefinitions.Add(new ColumnDefinition()); header.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            header.Children.Add(new TextBlock {Text=source.Text=="Configuration"?"General":source.Text=="Voice"?"Speech":installed && source.Text=="Features"?"Maintenance":source.Text,FontSize=30,FontWeight=FontWeights.SemiBold,TextWrapping=TextWrapping.Wrap});
            if(source.Text=="Prerequisites") {var again=FindAction("Check again");again.Content="Check Again";Accessible(again,"Check Again"); Grid.SetColumn(again,1); header.Children.Add(again);}
            if(source.Text=="Apply features") {
                var again=Action("Check Again",ReviewSetupSelection,"Primary");Grid.SetColumn(again,1);header.Children.Add(again);
                bindings.Add(delegate {again.IsEnabled=!Busy && controller.SetupReady;});
            }
            stack.Children.Add(header); if(description!=null) stack.Children.Add(Text(description,14,true,new Thickness(0,-12,0,24)));
            if(source.Text=="Features" && installed) BuildMaintenance(stack);
            else if(source.Text=="Features") BuildFeatures(stack);
            else if(source.Text=="Workspaces") BuildWorkspaces(stack,source);
            else if(source.Text=="Voice") BuildSpeech(stack,source);
            else if(source.Text=="Models & engines") BuildModels(stack,source);
            else if(source.Text=="Prerequisites") BuildChecks(stack);
            else if(source.Text=="Apply features") BuildApplyFeatures(stack);
            else BuildGeneric(stack,(F.FlowLayoutPanel)source.Controls[0]);
            pageHost.Content=new ScrollViewer {Content=stack,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,Padding=new Thickness(0,0,8,0)};
            Sync();
            controller.PreparePage(source.Text);
            if(source.Text=="Apply features" && controller.SetupReady && !controller.SetupReviewed && !Busy) ReviewSetupSelection();
        }
        private void BuildConfigurationNavigation(StackPanel page,string current) {
            var tabs=new WrapPanel {Margin=new Thickness(0,0,0,20)};
            foreach(var section in new[]{new[]{"General","Configuration"},new[]{"Workspaces","Workspaces"},new[]{"Models","Models"},new[]{"Speech","Voice"},new[]{"Conversations","Sessions & memory"},new[]{"Maintenance","Features"}}) {
                int target=controller.PresentationPages.TabPages.Cast<F.TabPage>().ToList().FindIndex(x=>x.Text==section[1]);
                bool selected=current==section[1] || (section[0]=="Maintenance" && new[]{"Models & engines","Prerequisites","Apply features","Remove WHAS"}.Contains(current));
                var button=Action(section[0],delegate {SelectPage(target);},selected?"Navigation":"Quiet");button.Margin=new Thickness(0,0,4,6);tabs.Children.Add(button);
            }
            page.Children.Add(tabs);
            if(controller.IsSetup && new[]{"Features","Models & engines","Prerequisites","Apply features"}.Contains(current)) {
                var steps=new WrapPanel {Margin=new Thickness(0,0,0,16)};
                foreach(var step in new[]{new[]{"Choose features","Features"},new[]{"Models & engines","Models & engines"},new[]{"Prerequisites","Prerequisites"},new[]{"Review & apply","Apply features"}}) {
                    int target=controller.PresentationPages.TabPages.Cast<F.TabPage>().ToList().FindIndex(x=>x.Text==step[1]);
                    var button=Action(step[0],delegate {SelectPage(target);},current==step[1]?"Primary":"Quiet");button.Margin=new Thickness(0,0,4,4);steps.Children.Add(button);
                }
                page.Children.Add(steps);
            }
        }
        private Grid BuildAssistant() {
            var page=new Grid();page.RowDefinitions.Add(new RowDefinition());page.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});page.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});
            var responses=new Grid {Margin=new Thickness(0,0,0,16)};
            var messages=new StackPanel();
            var history=new ScrollViewer {Content=messages,Focusable=false,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,Padding=new Thickness(16)};Accessible(history,"Response history");
            var answer=new Border {Child=history,Focusable=false,MinHeight=100,CornerRadius=new CornerRadius(5),BorderThickness=new Thickness(1)};Accessible(answer,"Responses");answer.SetResourceReference(Border.BackgroundProperty,"Canvas");answer.SetResourceReference(Border.BorderBrushProperty,"InputBorder");responses.Children.Add(answer);
            var newChat=FindAction("New conversation");newChat.Content="New chat";Accessible(newChat,"New chat");newChat.Style=(Style)shell.Resources["Quiet"];newChat.HorizontalAlignment=HorizontalAlignment.Right;newChat.VerticalAlignment=VerticalAlignment.Bottom;newChat.MinHeight=24;newChat.Padding=new Thickness(4,0,4,0);newChat.Margin=new Thickness(0,0,24,-12);newChat.SetResourceReference(Control.BackgroundProperty,"Canvas");newChat.ToolTip="Clear this chat and start with no previous conversation context";responses.Children.Add(newChat);
            int revision=-1;var rows=new List<ChatRow>();
            bindings.Add(delegate {
                string waitingText="Waiting for reply"+new string('.',1+(int)(DateTime.UtcNow.Ticks/TimeSpan.TicksPerMillisecond/450%3));
                foreach(var row in rows) if(row.Waiting!=null) row.Waiting.Text=waitingText;
                if(revision==controller.ConversationRevision) return;
                bool reset=revision<0 || rows.Count>controller.ConversationReplies.Count || rows.Where((row,index)=>!Object.ReferenceEquals(row.Reply,controller.ConversationReplies[index])).Any();
                revision=controller.ConversationRevision;
                if(reset) {messages.Children.Clear();rows.Clear();}
                if(rows.Count==0) {
                    messages.Children.Clear();
                    if(controller.ConversationReplies.Count==0) {var greeting=SelectableText("Hi, how can I help?","Greeting");greeting.SetResourceReference(Control.ForegroundProperty,"Muted");greeting.FontStyle=FontStyles.Italic;messages.Children.Add(greeting);}
                }
                foreach(var reply in controller.ConversationReplies.Skip(rows.Count)) {
                    var question=SelectableText(reply.Key,"Your message text");question.Foreground=Brush("#FFFFFF");question.TextAlignment=TextAlignment.Left;
                    var bubble=new Border {Child=question,Background=Brush("#173E76"),CornerRadius=new CornerRadius(8),Padding=new Thickness(14,10,14,10),Margin=new Thickness(0,0,0,20),HorizontalAlignment=HorizontalAlignment.Right};Accessible(bubble,"Your question");
                    // Constrain bubbles to the viewport while allowing short questions to size to their text.
                    bubble.SetBinding(FrameworkElement.MaxWidthProperty,new System.Windows.Data.Binding("ActualWidth") {Source=messages});messages.Children.Add(bubble);
                    var row=new ChatRow {Reply=reply,Question=question,Answer=SelectableText(reply.Value,"Assistant reply"),Response=new Grid {Margin=new Thickness(0,0,0,20)}};
                    if(reply.Pending) {row.Waiting=Text(waitingText,14,true);Accessible(row.Waiting,"Waiting for reply");row.Response.Children.Add(row.Waiting);}else row.Response.Children.Add(row.Answer);
                    messages.Children.Add(row.Response);rows.Add(row);
                }
                foreach(var row in rows) if(!row.Reply.Pending) {
                    if(row.Waiting!=null) {row.Response.Children.Clear();row.Response.Children.Add(row.Answer);row.Waiting=null;}
                    UpdateSelectableText(row.Answer,row.Reply.Value);
                }
                // Retain text controls and selections when another reply streams.
                // Do not pull an active selection away to the bottom of history.
                if(!rows.Any(row=>(row.Question.IsKeyboardFocusWithin && row.Question.SelectionLength>0) || (row.Answer.IsKeyboardFocusWithin && row.Answer.SelectionLength>0)))
                    history.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded,(Action)delegate {history.ScrollToEnd();});
            });page.Children.Add(responses);
            var composer=new StackPanel();var input=new Grid();
            var message=BoundText((F.TextBox)Field("prompt"),"Your message");message.AcceptsReturn=true;message.VerticalContentAlignment=VerticalAlignment.Top;message.Padding=new Thickness(10,8,10,8);message.MinHeight=80;message.MaxHeight=160;input.Children.Add(message);
            message.ToolTip="Enter to send; Shift+Enter for a new line";message.PreviewKeyDown+=delegate(object sender,KeyEventArgs e){if(HandleMessageKey(e.Key,Keyboard.Modifiers,e.IsRepeat)) e.Handled=true;};
            var placeholder=Text("Type your message here…",14,true,new Thickness(10,8,10,8));placeholder.FontStyle=FontStyles.Italic;placeholder.IsHitTestVisible=false;input.Children.Add(placeholder);message.TextChanged+=delegate {placeholder.Visibility=message.Text.Length==0?Visibility.Visible:Visibility.Collapsed;};placeholder.Visibility=message.Text.Length==0?Visibility.Visible:Visibility.Collapsed;composer.Children.Add(input);
            var controls=new Grid {Margin=new Thickness(0,12,0,0)};foreach(bool flexible in new[]{false,false,true,false,false}) controls.ColumnDefinitions.Add(new ColumnDefinition {Width=flexible?new GridLength(1,GridUnitType.Star):GridLength.Auto});
            var route=BoundChoice((F.ComboBox)Field("route"),"Run on");route.Width=180;route.ToolTip="Run on";controls.Children.Add(route);
            var speak=BoundCheck((F.CheckBox)Field("speak"),"Speak the answer");speak.VerticalAlignment=VerticalAlignment.Center;speak.Margin=new Thickness(12,0,16,0);Grid.SetColumn(speak,1);controls.Children.Add(speak);
            var operation=BoundChoice((F.ComboBox)Field("action"),"Operation");operation.Width=180;operation.ToolTip="Conversation keeps the current conversation's context. One-off question starts fresh. Use Run a task for file or system tools.";Grid.SetColumn(operation,3);controls.Children.Add(operation);
            var sourceSend=controller.PresentationPages.TabPages.Cast<F.TabPage>().SelectMany(x=>Descendants(x).OfType<F.Button>()).First(x=>x.Text=="Send");
            var send=Action("Send",delegate {controller.InvokePresentationAction(controller.IsAssistantRequestRunning?controller.PresentationCancel:sourceSend);},"Primary");send.Width=96;send.Margin=new Thickness(8,0,0,0);
            bindings.Add(delegate {bool requesting=controller.IsAssistantRequestRunning;string label=requesting?"Cancel":"Send";send.Content=label;send.Style=(Style)shell.Resources[requesting?"Cancel":"Primary"];Accessible(send,label);send.IsEnabled=requesting?controller.PresentationCancel.Enabled:!Busy && sourceSend.Enabled;});
            Grid.SetColumn(send,4);controls.Children.Add(send);composer.Children.Add(controls);
            var frame=Card(composer,new Thickness(16));frame.Margin=new Thickness(0);Grid.SetRow(frame,1);page.Children.Add(frame);
            var hint=Text("Conversation keeps this window's context. Use New chat to start fresh.",12,true,new Thickness(0,10,0,0));Grid.SetRow(hint,2);page.Children.Add(hint);return page;
        }
        private bool HandleMessageKey(Key key,ModifierKeys modifiers,bool repeat) {
            if(key!=Key.Return || (modifiers&ModifierKeys.Shift)!=0) return false;
            if(!repeat && !Busy && !String.IsNullOrWhiteSpace(((F.TextBox)Field("prompt")).Text)) {
                var send=controller.PresentationPages.TabPages.Cast<F.TabPage>().SelectMany(x=>Descendants(x).OfType<F.Button>()).First(x=>x.Text=="Send");controller.InvokePresentationAction(send);
            }
            return true;
        }
        private void BuildWorkspaces(StackPanel page,F.TabPage source) {
            page.Children.Add(Text("All saved folders and their subfolders are available to Run a task. The starting folder controls where relative paths and commands begin.",14,true,new Thickness(0,0,0,20)));
            page.Children.Add(Text("AVAILABLE FOLDERS",12,true,new Thickness(0,0,0,12)));
            foreach(string folder in controller.Preferences.Workspaces) {
                string path=folder;var row=new Grid();row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
                var name=SelectableText(path,"Available folder");name.VerticalAlignment=VerticalAlignment.Center;name.Margin=new Thickness(0,0,16,0);row.Children.Add(name);
                var remove=Action("Remove",delegate {controller.RemoveWorkspaceFolder(path);Navigate(controller.PresentationPages.SelectedIndex);},"Quiet");remove.ToolTip="Remove from the list; keep folder and files";Grid.SetColumn(remove,1);row.Children.Add(remove);bindings.Add(delegate {remove.IsEnabled=!Busy;});page.Children.Add(Card(row));
                if(!Directory.Exists(path)) page.Children.Add(Text("This folder is currently unavailable.",12,true,new Thickness(0,0,0,12)));
            }
            if(controller.Preferences.Workspaces.Count==0) page.Children.Add(Text("No workspaces yet. Add a folder to start.",14,true,new Thickness(0,0,0,16)));
            var add=FindAction("Add workspace…");add.HorizontalAlignment=HorizontalAlignment.Left;add.Margin=new Thickness(0,8,0,24);page.Children.Add(add);
            page.Children.Add(Text("STARTING FOLDER",12,true,new Thickness(0,0,0,12)));
            var choice=Descendants(source).OfType<F.ComboBox>().First();page.Children.Add(Card(BoundChoice(choice,"Starting folder")));
            page.Children.Add(Text("Changing this list or the starting folder starts a new conversation. Removing an entry never deletes files. Conversation and one-off questions do not use file tools.",12,true,new Thickness(0,12,0,0)));
            string previous=String.Join("\n",controller.Preferences.Workspaces);bindings.Add(delegate {string current=String.Join("\n",controller.Preferences.Workspaces);if(previous!=current) Dispatcher.BeginInvoke((Action)delegate {if(!disposed && controller.PresentationPages.SelectedTab.Text=="Workspaces") Navigate(controller.PresentationPages.SelectedIndex);});});
        }
        private F.Control Field(string name) {return controller.PresentationField(name);}
        private void BuildSpeech(StackPanel page,F.TabPage source) {
            var engine=new StackPanel();engine.Children.Add(Text("Speech engine",18,false,new Thickness(0,0,0,12)));
            engine.Children.Add(BoundChoice((F.ComboBox)Field("voiceEngine"),"Speech engine"));
            var engineDefault=Text("",12,true,new Thickness(0,10,0,0));engine.Children.Add(engineDefault);bindings.Add(delegate {engineDefault.Text="Default speech engine: "+(String.IsNullOrEmpty(controller.SavedSpeechEngine)?"Not configured":new ChoiceItem {Value=controller.SavedSpeechEngine}.ToString())+". Assistant replies use this default. Selecting or previewing an engine does not change it; use Set default engine to change future answers.";});
            engine.Children.Add(LiveLabel((F.Label)Field("voiceSupport")));
            var engineActions=new WrapPanel {Margin=new Thickness(0,8,0,0)};foreach(string label in new[]{"Refresh engines and voices","Install selected engine…","Set default engine"}) {var button=FindAction(label);button.Margin=new Thickness(0,0,8,8);engineActions.Children.Add(button);}engine.Children.Add(engineActions);
            engine.Children.Add(Text("Engine removal keeps personal voice recordings. Preview the selected engine's changes before removing it.",12,true,new Thickness(0,12,0,12)));var engineRemoval=new WrapPanel();foreach(string label in new[]{"Preview engine removal","Remove selected engine…"}) {var button=FindAction(label);button.Margin=new Thickness(0,0,8,8);engineRemoval.Children.Add(button);}engine.Children.Add(engineRemoval);page.Children.Add(Card(engine));
            var guidance=new StackPanel();var guidanceTitle=Text("",18,false,new Thickness(0,0,0,10));var guidanceBody=Text("",13,true);guidance.Children.Add(guidanceTitle);guidance.Children.Add(guidanceBody);var builtinPreview=FindAction("Play test phrase");builtinPreview.HorizontalAlignment=HorizontalAlignment.Left;builtinPreview.Margin=new Thickness(0,12,0,0);guidance.Children.Add(builtinPreview);page.Children.Add(Card(guidance));
            bindings.Add(delegate {string name=new ChoiceItem {Value=controller.SelectedSpeechEngine}.ToString();bool cloning=controller.SelectedSpeechCloning,transcript=controller.SelectedSpeechTranscript;guidanceTitle.Text=name+(cloning?" reference recordings":" voice");guidanceBody.Text=cloning?(transcript?"Requires a WAV recording and a matching UTF-8 .txt transcript in the same folder: recording.wav + recording.txt. The transcript must contain the words spoken in that recording. Choose the WAV below; its matching transcript is checked automatically.":"Custom voices use a reference WAV recording. No transcript file is required. Choose a recording, give it a name, then save it below."):"Uses this engine's packaged voice. Custom WAV references and voice cloning are not supported.";if(!controller.SelectedSpeechInstalled) guidanceBody.Text+=" Install this engine above before using its voices.";builtinPreview.Visibility=!cloning && controller.SelectedSpeechInstalled?Visibility.Visible:Visibility.Collapsed;});
            var voices=new StackPanel();voices.Children.Add(Text("Saved voices",18,false,new Thickness(0,0,0,12)));voices.Children.Add(BoundChoice((F.ComboBox)Field("voiceName"),"Saved voice"));voices.Children.Add(LiveLabel((F.Label)Field("voiceSelectionNotice")));
            var voiceActions=new WrapPanel {Margin=new Thickness(0,8,0,0)};foreach(string label in new[]{"Play test phrase","Set this as default voice","Delete this voice…"}) {var button=FindAction(label);button.Margin=new Thickness(0,0,8,8);voiceActions.Children.Add(button);}voices.Children.Add(voiceActions);var savedCard=Card(voices);page.Children.Add(savedCard);bindings.Add(delegate {savedCard.Visibility=controller.SelectedSpeechCloning && controller.SelectedSpeechInstalled?Visibility.Visible:Visibility.Collapsed;});
            var add=new StackPanel();add.Children.Add(Text("Add a voice",18,false,new Thickness(0,0,0,8)));add.Children.Add(Text("Choose a recording, name the voice, then save it. Tick Make default below to use it for this engine's spoken answers immediately after saving.",13,true,new Thickness(0,0,0,16)));
            add.Children.Add(Text("1. WAV recording",13,true,new Thickness(0,0,0,8)));var recording=new Grid();recording.ColumnDefinitions.Add(new ColumnDefinition());recording.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            recording.Children.Add(BoundText((F.TextBox)Field("voiceReferencePath"),"WAV recording"));var choose=FindAction("Choose WAV recording…");choose.Margin=new Thickness(12,0,0,0);Grid.SetColumn(choose,1);recording.Children.Add(choose);add.Children.Add(recording);
            var transcriptPanel=new StackPanel {Margin=new Thickness(0,12,0,0)};transcriptPanel.Children.Add(Text("Matching transcript (.txt, required)",13,true,new Thickness(0,0,0,8)));var transcriptPath=new TextBox {IsReadOnly=true};Accessible(transcriptPath,"Required matching transcript");transcriptPanel.Children.Add(transcriptPath);var transcriptStatus=Text("",12,true,new Thickness(0,6,0,0));transcriptPanel.Children.Add(transcriptStatus);add.Children.Add(transcriptPanel);bindings.Add(delegate {transcriptPanel.Visibility=controller.SelectedSpeechTranscript?Visibility.Visible:Visibility.Collapsed;string wav=((F.TextBox)Field("voiceReferencePath")).Text;transcriptPath.Text=String.IsNullOrEmpty(wav)?"":Path.ChangeExtension(wav,".txt");transcriptStatus.Text=wav.Length==0?"Choose a WAV recording to locate its matching transcript.":File.Exists(transcriptPath.Text)?"Matching transcript found. It must contain the words spoken in the recording.":"Missing transcript. Create this UTF-8 .txt file beside the WAV, then choose the WAV again.";});
            add.Children.Add(Text("2. Voice name",13,true,new Thickness(0,16,0,8)));add.Children.Add(BoundText((F.TextBox)Field("voiceReferenceName"),"Voice name"));add.Children.Add(LiveLabel((F.Label)Field("voiceImportNotice")));
            var makeDefault=BoundCheck((F.CheckBox)Field("voiceMakeDefault"),"Make this the default voice for this engine");makeDefault.Margin=new Thickness(0,12,0,0);add.Children.Add(makeDefault);
            var save=FindAction("Save voice");save.Content="3. Save voice";save.Style=(Style)shell.Resources["Primary"];save.HorizontalAlignment=HorizontalAlignment.Left;save.Margin=new Thickness(0,12,0,0);add.Children.Add(save);var addCard=Card(add);page.Children.Add(addCard);bindings.Add(delegate {addCard.Visibility=controller.SelectedSpeechCloning && controller.SelectedSpeechInstalled?Visibility.Visible:Visibility.Collapsed;});
            var advanced=new StackPanel();var controls=((F.FlowLayoutPanel)source.Controls[0]).Controls.Cast<F.Control>().TakeWhile(x=>x.Text!="Engines and voices").Skip(2).ToArray();int hardwareStart=Array.FindIndex(controls,x=>x.Text=="Hardware");BuildGeneric(advanced,(F.FlowLayoutPanel)source.Controls[0],controls.Take(hardwareStart).ToArray(),false);
            var hardware=new StackPanel();BuildGeneric(hardware,(F.FlowLayoutPanel)source.Controls[0],controls.Skip(hardwareStart).ToArray(),false);advanced.Children.Add(hardware);bindings.Add(delegate {hardware.Visibility=controller.SelectedSpeechDeviceChoice?Visibility.Visible:Visibility.Collapsed;});
            page.Children.Add(Text("Speech settings",20,false,new Thickness(0,24,0,16)));page.Children.Add(Card(advanced));
        }
        private void BuildMaintenance(StackPanel page) {
            controller.RefreshFeatureStatus();
            if(String.IsNullOrEmpty(controller.MaintenanceFeature)) {
            page.Children.Add(Text("Features",20,false,new Thickness(0,0,0,16)));
            foreach(var entry in new[]{new[]{"cloud","Cloud AI"},new[]{"local","Local AI"},new[]{"voice","Speech"}}) {
                string feature=entry[0];var source=(F.CheckBox)Field(feature);bool configured=source.AccessibleDescription.StartsWith("Cloud route") || source.AccessibleDescription.StartsWith("Local route") || source.AccessibleDescription.StartsWith("Installed:");
                var row=new Grid();row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});var title=new StackPanel();title.Children.Add(Text(entry[1],16));title.Children.Add(Text(source.AccessibleDescription,12,true,new Thickness(0,6,16,0)));row.Children.Add(title);
                var actions=new WrapPanel {VerticalAlignment=VerticalAlignment.Center};var change=Action(configured?"Repair…":"Add…",delegate {controller.BeginMaintenance(feature);Navigate(controller.PresentationPages.SelectedIndex);});actions.Children.Add(change);bindings.Add(delegate {change.IsEnabled=!Busy;});
                if(configured) {var remove=Action("Remove…",delegate {if(feature=="voice") {int speech=controller.PresentationPages.TabPages.Cast<F.TabPage>().ToList().FindIndex(x=>x.Text=="Voice");SelectPage(speech);}else {OpenLog(true);controller.RemoveRoute(feature);}},"Quiet");remove.ToolTip=feature=="voice"?"Choose an engine in Speech and remove it; personal voices are kept":"Remove this WHAS route; keep provider accounts, applications and model files";actions.Children.Add(remove);bindings.Add(delegate {remove.IsEnabled=!Busy;});}Grid.SetColumn(actions,1);row.Children.Add(actions);page.Children.Add(Card(row));
            }
            var shared=Action("Repair shared app files…",delegate {controller.BeginMaintenance("core");Navigate(controller.PresentationPages.SelectedIndex);},"Quiet");shared.HorizontalAlignment=HorizontalAlignment.Left;shared.Margin=new Thickness(0,8,0,20);page.Children.Add(shared);bindings.Add(delegate {shared.IsEnabled=!Busy;});
            page.Children.Add(Text("Removing Cloud or Local AI removes its WHAS route and keeps accounts, prerequisites and model files. Speech removal is managed per engine in Speech; personal voice recordings are preserved.",12,true,new Thickness(0,8,0,0)));
            page.Children.Add(Text("Removal",20,false,new Thickness(0,32,0,16)));
            var removal=controller.PresentationPages.TabPages.Cast<F.TabPage>().First(x=>x.Text=="Remove WHAS");
            var removalControls=((F.FlowLayoutPanel)removal.Controls[0]).Controls.Cast<F.Control>().ToArray();
            BuildGeneric(page,(F.FlowLayoutPanel)removal.Controls[0],removalControls.Where(x=>!(x is F.Button)).ToArray());
            var removalActions=new WrapPanel {Margin=new Thickness(0,8,0,16)};
            var preview=FindAction("Preview removal");var uninstall=FindAction("Uninstall…");uninstall.Style=(Style)shell.Resources["Cancel"];
            preview.Margin=new Thickness(0,0,8,0);removalActions.Children.Add(preview);removalActions.Children.Add(uninstall);page.Children.Add(removalActions);
            bool previewRequested=false;preview.Click+=delegate {previewRequested=true;uninstall.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded,(Action)delegate {uninstall.BringIntoView();});};
            bindings.Add(delegate {if(previewRequested && !Busy){previewRequested=false;uninstall.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded,(Action)delegate {uninstall.BringIntoView();});}});return;
            }
            string selected=controller.MaintenanceFeature;
            var back=Action("Back to features",delegate {controller.CloseMaintenance();Navigate(controller.PresentationPages.SelectedIndex);},"Quiet");back.HorizontalAlignment=HorizontalAlignment.Left;page.Children.Add(back);bindings.Add(delegate {back.IsEnabled=!Busy;});
            page.Children.Add(Text("CHANGE OPTIONS — "+(selected=="core"?"SHARED APP FILES":selected=="voice"?"SPEECH":selected.ToUpperInvariant()+" AI"),16,false,new Thickness(0,20,0,16)));
            if(selected=="local") {
                var options=new StackPanel();options.Children.Add(Text("Models to add or repair",14));options.Children.Add(BoundList((F.CheckedListBox)Field("models"),true));
                options.Children.Add(Text("Additional Ollama model",12,true,new Thickness(0,12,0,0)));var source=controller.PresentationPages.TabPages.Cast<F.TabPage>().First(x=>x.Text=="Models & engines");var custom=Descendants(source).OfType<F.TextBox>().First();var row=new Grid {Margin=new Thickness(0,8,0,16)};row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});row.Children.Add(BoundText(custom,"Additional Ollama model"));var add=FindAction("Add model name");add.Content="Add";add.Margin=new Thickness(8,0,0,0);Grid.SetColumn(add,1);row.Children.Add(add);options.Children.Add(row);options.Children.Add(Text("Default local model",12,true,new Thickness(0,8,0,8)));options.Children.Add(BoundChoice((F.ComboBox)Field("defaultModel"),"Default local model"));page.Children.Add(Card(options));
            }
            if(selected=="voice") {var options=new StackPanel();options.Children.Add(Text("Engines to add or repair",14));options.Children.Add(BoundList((F.CheckedListBox)Field("engines"),true));options.Children.Add(Text("Default speech engine",12,true,new Thickness(0,12,0,8)));options.Children.Add(BoundChoice((F.ComboBox)Field("defaultEngine"),"Default speech engine"));page.Children.Add(Card(options));}
            if(selected=="cloud") page.Children.Add(Text("Repair the Cloud AI route using the saved model/provider configuration. Manage OpenCode sign-in under Models.",13,true,new Thickness(0,0,0,16)));
            if(selected=="core") page.Children.Add(Text("Update shared commands and application files. No optional engines or models are downloaded. Existing settings, accounts and personal voices are kept.",13,true,new Thickness(0,0,0,16)));
            var commands=new WrapPanel {Margin=new Thickness(0,16,0,16)};
            var check=Action("Check readiness",delegate {controller.CheckMaintenance();});var review=Action("Review changes",delegate {OpenLog(true);controller.ReviewMaintenance();});var apply=Action("Apply changes…",delegate {controller.ApplyMaintenance();},"Primary");foreach(var button in new[]{check,review,apply}) {button.Margin=new Thickness(0,0,8,8);commands.Children.Add(button);}page.Children.Add(commands);
            bindings.Add(delegate {check.IsEnabled=!Busy;try {review.IsEnabled=!Busy && controller.MaintenanceChecked;apply.IsEnabled=!Busy && controller.MaintenanceReviewed;}catch(ArgumentException){review.IsEnabled=apply.IsEnabled=false;}});
            page.Children.Add(Text("Check readiness, review the activity-log plan, then apply this change. Changing options requires a fresh check and review.",12,true,new Thickness(0,0,0,16)));BuildChecks(page);checkSummary.Text="Select Check readiness to check this change.";
        }
        private TextBlock LiveLabel(F.Label source) {var text=Text(source.Text,12,true,new Thickness(0,10,0,0));bindings.Add(delegate {text.Text=source.Text;});return text;}
        private void BuildFeatures(StackPanel page) {
            controller.RefreshFeatureStatus();
            var heading=new DockPanel {Margin=new Thickness(0,0,0,12)}; var all=FindAction("Select all features"); all.Content="Select all"; all.Style=(Style)shell.Resources["Quiet"];
            var none=FindAction("Select none (shared app only)"); none.Content="Clear selection"; none.Style=(Style)shell.Resources["Quiet"];
            var commands=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right}; commands.Children.Add(all);commands.Children.Add(none); DockPanel.SetDock(commands,Dock.Right); heading.Children.Add(commands);heading.Children.Add(Text("FEATURES",12,true,new Thickness(0,10,0,0))); page.Children.Add(heading);
            Feature(page,"\uE753","Cloud AI","Use models from your connected cloud providers.",(F.CheckBox)Field("cloud"));
            Feature(page,"\uE7F4","Local AI","Run models on this PC with Ollama.",(F.CheckBox)Field("local"));
            Feature(page,"\uE767","Speech","Read responses aloud using a local speech engine.",(F.CheckBox)Field("voice"));
            page.Children.Add(Text("INSTALLATION",12,true,new Thickness(0,20,0,12)));
            var location=new StackPanel(); location.Children.Add(Text("Installation folder"));
            var folder=new Grid {Margin=new Thickness(0,10,0,0)}; folder.ColumnDefinitions.Add(new ColumnDefinition()); folder.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            var path=BoundText((F.TextBox)Field("destination"),"Installation folder"); path.Margin=new Thickness(0,0,10,0); folder.Children.Add(path);
            var browse=FindAction("Choose folder…"); browse.Content="Browse…"; Grid.SetColumn(browse,1); folder.Children.Add(browse); location.Children.Add(folder); page.Children.Add(Card(location));
            var route=new Grid(); route.ColumnDefinitions.Add(new ColumnDefinition()); route.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(220)});
            var caption=new StackPanel {Margin=new Thickness(0,0,16,0)};caption.Children.Add(Text("Default processing")); caption.Children.Add(Text("Run requests on this PC or in the cloud unless you choose otherwise.",12,true,new Thickness(0,4,0,0))); route.Children.Add(caption);
            var choice=BoundChoice((F.ComboBox)Field("defaultLocation"),"Default processing"); Grid.SetColumn(choice,1); route.Children.Add(choice); page.Children.Add(Card(route));
            page.Children.Add(Text("Selections add or repair features. They do not remove existing features.",12,true,new Thickness(0,12,0,18)));
            page.Children.Add(Text("OpenCode provides the cloud/local workflow and requires its own provider sign-in. Missing prerequisites must be installed before applying features.",12,true,new Thickness(0,0,0,8)));
            var guide=Action("Installation and account setup guide ↗",delegate{Process.Start(new ProcessStartInfo("https://github.com/thestonefox/windows-hybrid-agentic-stack/blob/main/docs/installation.md"){UseShellExecute=true});},"Quiet");guide.HorizontalAlignment=HorizontalAlignment.Left;guide.Margin=new Thickness(0,0,0,16);page.Children.Add(guide);
        }
        private void Feature(StackPanel page,string glyph,string title,string subtitle,F.CheckBox source) {
            var row=new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(40)});row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            var icon=Text(glyph,22,true);icon.FontFamily=new FontFamily("Segoe MDL2 Assets");icon.VerticalAlignment=VerticalAlignment.Center;row.Children.Add(icon);
            var words=new StackPanel {Margin=new Thickness(8,0,20,0)};words.Children.Add(new TextBlock {Text=title,FontWeight=FontWeights.SemiBold});words.Children.Add(Text(subtitle,12,true,new Thickness(0,4,0,0)));Grid.SetColumn(words,1);row.Children.Add(words);
            var installed=Text(source.AccessibleDescription,12,true,new Thickness(0,6,0,0));words.Children.Add(installed);bindings.Add(delegate {installed.Text=source.AccessibleDescription;});
            var toggle=BoundCheck(source,title);toggle.Content=null;toggle.Style=(Style)shell.Resources["Switch"];toggle.VerticalAlignment=VerticalAlignment.Center;Grid.SetColumn(toggle,2);row.Children.Add(toggle);page.Children.Add(Card(row));
        }
        private void BuildModels(StackPanel page,F.TabPage source) {
            var row=new Grid();
            foreach(int width in new[]{20,0,20,16,20,0,20}) row.ColumnDefinitions.Add(new ColumnDefinition {Width=width==0?new GridLength(1,GridUnitType.Star):new GridLength(width)});
            for(int i=0;i<7;i++) row.RowDefinitions.Add(new RowDefinition {Height=i==0 || i==6?new GridLength(16):GridLength.Auto});
            foreach(int column in new[]{0,4}) {var background=Card(null);background.Margin=new Thickness(0);Grid.SetColumn(background,column);Grid.SetColumnSpan(background,3);Grid.SetRowSpan(background,7);row.Children.Add(background);}
            ModelCell(row,new TextBlock {Text="Local models",FontSize=18,FontWeight=FontWeights.SemiBold},1,1);
            ModelCell(row,new TextBlock {Text="Speech engines",FontSize=18,FontWeight=FontWeights.SemiBold},5,1);
            var modelNotice=Text(controller.SetupModelNotice,12,true,new Thickness(0,6,0,18));ModelCell(row,modelNotice,1,2);
            bindings.Add(delegate {modelNotice.Text=((F.CheckBox)Field("local")).Checked?controller.SetupModelNotice:"Local AI is off. No local models will be downloaded.";});
            ModelCell(row,Text("Install one or more engines. The default starts on demand.",12,true,new Thickness(0,6,0,18)),5,2);
            ModelCell(row,Text("Default local model",12,true,new Thickness(0,0,0,8)),1,3);
            ModelCell(row,Text("Default speech engine",12,true,new Thickness(0,0,0,8)),5,3);
            ModelCell(row,BoundChoice((F.ComboBox)Field("defaultModel"),"Default local model"),1,4);
            ModelCell(row,BoundChoice((F.ComboBox)Field("defaultEngine"),"Default speech engine"),5,4);
            var left=new StackPanel();var right=new StackPanel();
            left.Children.Add(Text("Models to use",12,true,new Thickness(0,20,0,4)));
            left.Children.Add(BoundList((F.CheckedListBox)Field("models"),true));
            var refresh=Action("Refresh available models",controller.RefreshSetupModels);refresh.HorizontalAlignment=HorizontalAlignment.Left;refresh.Margin=new Thickness(0,8,0,0);left.Children.Add(refresh);
            bindings.Add(delegate {refresh.IsEnabled=!Busy && ((F.CheckBox)Field("local")).Checked;});
            left.Children.Add(Text("Additional Ollama model",12,true,new Thickness(0,20,0,8)));
            var customRow=new Grid();customRow.ColumnDefinitions.Add(new ColumnDefinition());customRow.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
            var custom=Descendants(source).OfType<F.TextBox>().First();var input=BoundText(custom,"Additional Ollama model");input.Margin=new Thickness(0,0,8,0);customRow.Children.Add(input);
            var add=FindAction("Add model name");add.Content="Add";add.Margin=new Thickness(0);Grid.SetColumn(add,1);customRow.Children.Add(add);left.Children.Add(customRow);
            right.Children.Add(Text("Engines to install",12,true,new Thickness(0,20,0,4)));
            var engineList=(F.CheckedListBox)Field("engines");
            for(int i=0;i<engineList.Items.Count;i++) {
                int index=i;string name=Convert.ToString(engineList.Items[i]);var strategy=strategies.First(x=>Convert.ToString(x["name"])==name);string id=Convert.ToString(strategy["id"]);
                var group=new StackPanel();var engineRow=new StackPanel {Orientation=Orientation.Horizontal};
                var check=new CheckBox {Content=name,IsChecked=engineList.GetItemChecked(index),Margin=new Thickness(0,8,0,8),MaxWidth=220};Accessible(check,name);
                check.Checked+=delegate {engineList.SelectedIndex=index;engineList.SetItemChecked(index,true);};check.Unchecked+=delegate {engineList.SelectedIndex=index;engineList.SetItemChecked(index,false);};
                engineRow.Children.Add(check);engineRow.Children.Add(LicenceInfo(name,true));group.Children.Add(engineRow);
                var sourceDevice=controller.SetupDevice(id);StackPanel hardware=null;
                if(sourceDevice.Items.Count>1) {
                    hardware=new StackPanel {Margin=new Thickness(24,0,0,8)};
                    var device=BoundChoice(sourceDevice,"Speech device");Accessible(device,name+" device");hardware.Children.Add(device);
                    device.ToolTip="Prefer GPU uses a compatible NVIDIA GPU when detected, otherwise CPU. Setup reports the device used.";group.Children.Add(hardware);
                }
                var devicePanel=hardware;
                bindings.Add(delegate {bool selected=engineList.GetItemChecked(index);if(check.IsChecked!=selected) check.IsChecked=selected;check.IsEnabled=engineList.Enabled;if(devicePanel!=null)devicePanel.Visibility=selected && ((F.CheckBox)Field("voice")).Checked?Visibility.Visible:Visibility.Collapsed;});
                right.Children.Add(group);
            }
            ModelCell(row,left,1,5);ModelCell(row,right,5,5);page.Children.Add(row);
        }
        private void ConfigureSetupAction(string page) {
            setupPage=page;string source=null,label=null;
            if(page=="Features"){source="Next: models and engines";label="Choose Models & Engines";}
            if(page=="Models & engines"){source="Next: prerequisite checks";label="Check Prerequisites";}
            if(page=="Prerequisites"){source="Next: review and apply";label="Go to Apply Features";}
            if(page=="Apply features"){source="Apply selected features";label="Apply selected features";}
            setupNextSource=source==null?null:controller.PresentationPages.TabPages.Cast<F.TabPage>().SelectMany(x=>Descendants(x).OfType<F.Button>()).First(x=>x.Text==source);
            setupNext.Content=label??"";Accessible(setupNext,label??"");setupNext.Visibility=source==null?Visibility.Collapsed:Visibility.Visible;
        }
        private void BuildApplyFeatures(StackPanel page) {
            page.Children.Add(Text("Review the installation folder, selected features, models and speech engines before applying changes.",14,true,new Thickness(0,0,0,16)));
            var summary=new StackPanel {Margin=new Thickness(0,16,0,0)};Accessible(summary,"Installation review");page.Children.Add(summary);string signature=null;
            bindings.Add(delegate {
                string next=controller.SetupReviewed?String.Join("\n",controller.SetupReview.Select(x=>x.Key+"="+x.Value)):Busy?"Reviewing selection…":controller.SetupReady?"The review is not ready. Select Check Again to retry.":"Check prerequisites for the current selection before reviewing and applying features.";
                if(next==signature)return;signature=next;summary.Children.Clear();
                if(!controller.SetupReviewed){summary.Children.Add(Text(next,13,true));return;}
                foreach(var item in controller.SetupReview){var body=new StackPanel();body.Children.Add(Text(item.Key,14,false,new Thickness(0,0,0,6)));body.Children.Add(SelectableText(item.Value,item.Key+" review"));summary.Children.Add(Card(body));}
            });
        }
        private void ReviewSetupSelection() {
            var source=controller.PresentationPages.TabPages.Cast<F.TabPage>().SelectMany(x=>Descendants(x).OfType<F.Button>()).First(x=>x.Text=="Review selection");
            controller.InvokePresentationAction(source);
        }
        private static void ModelCell(Grid grid,UIElement element,int column,int row) {Grid.SetColumn(element,column);Grid.SetRow(element,row);grid.Children.Add(element);}
        private void BuildChecks(StackPanel page) {
            checkSummary=Text("Checking your PC…",13,true,new Thickness(0,0,0,16));page.Children.Add(checkSummary);
            checkRows=new StackPanel();page.Children.Add(checkRows);RefreshChecks();
        }
        private static string InstallLink(string component) {
            if(component.StartsWith("Python")) return "https://www.python.org/downloads/release/python-3119/";
            if(component=="Visual C++ x64") return "https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist";
            if(component=="NVIDIA GPU") return "https://www.nvidia.com/Download/index.aspx";
            if(component=="OpenCode") return "https://opencode.ai/docs/";
            if(component=="Ollama") return "https://ollama.com/download/windows";
            return null;
        }
        private void RefreshChecks() {
            if(checkRows==null) return;var grid=(F.DataGridView)Field("checkGrid");
            string signature=String.Join("\n",grid.Rows.Cast<F.DataGridViewRow>().Select(r=>String.Join("|",r.Cells.Cast<F.DataGridViewCell>().Select(c=>Convert.ToString(c.Value)))));
            if(signature==lastChecks) return;lastChecks=signature;checkRows.Children.Clear();prerequisiteActions.Clear();int failures=0;
            foreach(F.DataGridViewRow data in grid.Rows) {
                string name=Convert.ToString(data.Cells[0].Value), required=Convert.ToString(data.Cells[1].Value), state=Convert.ToString(data.Cells[2].Value), detail=Convert.ToString(data.Cells[3].Value);
                if(state=="FAIL" && required=="Yes") failures++;
                var row=new Grid();row.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(152)});row.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(72)});row.ColumnDefinitions.Add(new ColumnDefinition());row.ColumnDefinitions.Add(new ColumnDefinition {Width=GridLength.Auto});
                var identity=new StackPanel {VerticalAlignment=VerticalAlignment.Center};identity.Children.Add(new TextBlock {Text=name,FontWeight=FontWeights.SemiBold,FontSize=13});identity.Children.Add(Text(required=="Yes"?"Required":"Optional / information",11,true,new Thickness(0,3,0,0)));row.Children.Add(identity);
                string foreground=state=="PASS"?"#0F6C35":state=="FAIL"?"#B42318":state=="WARN"?"#8A5700":"#476078";
                var badge=new Border {Background=Brush(state=="PASS"?"#E9F5EC":state=="FAIL"?"#FCECEB":state=="WARN"?"#FFF3DA":"#EDF2F7"),CornerRadius=new CornerRadius(4),Padding=new Thickness(8,4,8,4),HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Center,Child=new TextBlock {Text=state,Foreground=Brush(foreground),FontSize=11,FontWeight=FontWeights.SemiBold}}; Grid.SetColumn(badge,1);row.Children.Add(badge);
                var details=Text(detail,12,true,new Thickness(4,0,12,0)); details.VerticalAlignment=VerticalAlignment.Center;Grid.SetColumn(details,2);row.Children.Add(details);
                string uri=InstallLink(name);if(uri!=null && (state=="FAIL" || state=="WARN")) {
                    row.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});row.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});Grid.SetColumnSpan(details,2);
                    var actions=new StackPanel {Orientation=Orientation.Horizontal,Margin=new Thickness(4,12,0,0)};
                    var download=Action("Open download page ↗",delegate {Process.Start(new ProcessStartInfo(uri){UseShellExecute=true});});actions.Children.Add(download);prerequisiteActions.Add(download);
                    if(WhasWindow.PrerequisitePackage(name)!=null) {
                        bool available=WhasWindow.FindWinGet()!=null;
                        var install=Action("Install with WinGet",delegate {OpenLog(true);controller.InstallPrerequisite(name);},"Primary");
                        install.Tag=available;install.IsEnabled=available && !Busy;
                        install.ToolTip=available?"Installs this component using WinGet and accepts its package agreements. Windows may ask for administrator approval.":"WinGet is unavailable. Use Open download page, then select Check Again.";
                        actions.Children.Add(install);prerequisiteActions.Add(install);
                        if(!available) {var hint=Text("WinGet is unavailable. Use the download page, then select Check Again.",11,true,new Thickness(4,8,0,0));row.RowDefinitions.Add(new RowDefinition {Height=GridLength.Auto});Grid.SetColumn(hint,2);Grid.SetColumnSpan(hint,2);Grid.SetRow(hint,2);row.Children.Add(hint);}
                    }
                    Grid.SetColumn(actions,2);Grid.SetColumnSpan(actions,2);Grid.SetRow(actions,1);row.Children.Add(actions);
                }
                checkRows.Children.Add(Card(row,new Thickness(16,12,16,12)));
            }
            checkSummary.Text=grid.Rows.Count==0?(controller.IsSetup?"Checking your PC…":"Select Check readiness to check this change."):failures==0?"No missing prerequisites detected. Review any compatibility warnings.":failures+" required component"+(failures==1?" is":"s are")+" missing. Install them, then check again.";
        }
        private TextBox BoundText(F.TextBox source,string label) {
            var box=new TextBox {Text=source.Text,IsReadOnly=source.ReadOnly,AcceptsReturn=source.Multiline,TextWrapping=source.Multiline?TextWrapping.Wrap:TextWrapping.NoWrap};
            if(source.Multiline) {box.MinHeight=Math.Min(source.Height,180);box.MaxHeight=300;box.VerticalScrollBarVisibility=ScrollBarVisibility.Auto;}
            Accessible(box,label);bool syncing=false;
            box.TextChanged+=delegate {if(!syncing && !source.IsDisposed) source.Text=box.Text;};
            bindings.Add(delegate {if(source.IsDisposed) return;if(box.Text!=source.Text) {syncing=true;box.Text=source.Text;syncing=false;}box.IsEnabled=source.Enabled;});return box;
        }
        private ComboBox BoundChoice(F.ComboBox source,string label) {
            var box=new ComboBox {HorizontalAlignment=HorizontalAlignment.Stretch};Accessible(box,label);bool syncing=false;
            box.SelectionChanged+=delegate {if(!syncing && box.SelectedItem!=null && !source.IsDisposed) source.SelectedItem=((ChoiceItem)box.SelectedItem).Value;};
            bindings.Add(delegate {
                if(source.IsDisposed) return;syncing=true;
                var values=source.Items.Cast<object>().Select(Convert.ToString);
                if(label=="Run on") values=values.Where(x=>x!="default").OrderBy(x=>x==controller.SavedProcessing?0:1);
                var items=values.Select(x=>new ChoiceItem {Value=x,Display=ChoiceDisplay(x,label)}).ToArray();
                if(!items.Select(x=>x.Value+"|"+x.Display).SequenceEqual(box.Items.Cast<ChoiceItem>().Select(x=>x.Value+"|"+x.Display))) {box.Items.Clear();foreach(var item in items) box.Items.Add(item);}
                string selected=Convert.ToString(source.SelectedItem);if(label=="Run on" && selected=="default") selected=controller.SavedProcessing;
                box.SelectedItem=box.Items.Cast<ChoiceItem>().FirstOrDefault(x=>x.Value==selected);box.IsEnabled=source.Enabled;syncing=false;
            });return box;
        }
        private string ChoiceDisplay(string value,string label) {
            if(label=="Speech device") return value=="auto"?"Prefer GPU":value=="cpu"?"CPU":"GPU";
            if(value=="default" && (label=="Voice / reference name" || label=="Saved voice")) return "Built-in voice";
            if(label=="Run on") return (value=="local"?"This PC":"Cloud")+(value==controller.SavedProcessing?" (Default)":"");
            return null;
        }
        private CheckBox BoundCheck(F.CheckBox source,string label) {
            var check=new CheckBox {Content=label,IsChecked=source.Checked};Accessible(check,label);bool syncing=false;
            check.Checked+=delegate {if(!syncing) source.Checked=true;};check.Unchecked+=delegate {if(!syncing) source.Checked=false;};
            bindings.Add(delegate {if(source.IsDisposed) return;syncing=true;check.IsChecked=source.Checked;check.IsEnabled=source.Enabled;syncing=false;});return check;
        }
        private sealed class LicenceDetails {
            public string Text;
            public readonly List<string> Sources=new List<string>();
        }
        private LicenceDetails LicenceFor(string name,bool engine) {
            var details=new LicenceDetails();
            if(!engine) {
                string upstream=name=="qwen3:8b"?"Qwen3-8B":name=="qwen2.5:1.5b"?"Qwen2.5-1.5B":null;
                details.Text=upstream==null?"Licence not verified. Review the licence for this exact model before downloading or using it.":"Model weights: Apache-2.0. Review the upstream licence and the Ollama model information.";
                if(upstream!=null) {
                    details.Sources.Add("https://huggingface.co/Qwen/"+upstream+"/blob/main/LICENSE");
                    details.Sources.Add("https://ollama.com/library/"+name);
                }
                return details;
            }
            var strategy=strategies.FirstOrDefault(x=>Convert.ToString(x["name"])==name);
            if(strategy==null) {details.Text="Licence not verified.";return details;}
            var lines=new List<string>();object value;
            lines.Add("Engine / package: "+(strategy.TryGetValue("license",out value)?Convert.ToString(value):"Licence not verified."));
            if(strategy.TryGetValue("models",out value) && value is object[]) {
                var assets=((object[])value).Cast<Dictionary<string,object>>().ToArray();
                foreach(string licence in assets.Select(x=>x.ContainsKey("license")?Convert.ToString(x["license"]):"Licence not verified.").Distinct()) lines.Add("Downloaded model / assets: "+licence);
                foreach(var asset in assets) if(asset.TryGetValue("source",out value)) {
                    Uri uri;if(Uri.TryCreate(Convert.ToString(value),UriKind.Absolute,out uri) && (uri.Scheme=="https" || uri.Scheme=="http")) {
                        string url=uri.Host=="huggingface.co"?uri.AbsoluteUri.Replace("/resolve/","/blob/"):uri.AbsoluteUri;
                        if(!details.Sources.Contains(url)) details.Sources.Add(url);
                    }
                }
            }
            details.Text=String.Join(Environment.NewLine,lines);return details;
        }
        private Button LicenceInfo(string name,bool engine) {
            var details=LicenceFor(name,engine);
            var info=Action("\u24D8",delegate {
                var body=new StackPanel {Margin=new Thickness(20)};body.Children.Add(Text(details.Text));
                foreach(string source in details.Sources) {
                    string url=source;var link=Action(url,delegate {Process.Start(new ProcessStartInfo(url) {UseShellExecute=true});},"Quiet");
                    link.Content=Text(url,12);link.HorizontalContentAlignment=HorizontalAlignment.Left;link.Margin=new Thickness(0,8,0,0);body.Children.Add(link);
                }
                var dialog=new Window {Title=name+" — licence",Owner=this,Width=580,Height=360,MinWidth=360,MinHeight=240,WindowStartupLocation=WindowStartupLocation.CenterOwner,Content=new ScrollViewer {Content=body,VerticalScrollBarVisibility=ScrollBarVisibility.Auto},Background=(Brush)shell.Resources["Canvas"],Foreground=(Brush)shell.Resources["Ink"]};
                dialog.Resources.MergedDictionaries.Add(shell.Resources);dialog.ShowDialog();
            },"Quiet");
            info.Padding=new Thickness(4,0,4,0);info.MinHeight=24;info.MinWidth=24;info.FontSize=16;info.Margin=new Thickness(6,0,0,0);
            Accessible(info,"Licence information for "+name);
            var tip=new ToolTip {Content=Text(details.Text+Environment.NewLine+"Select for details and source links.",12),MaxWidth=420};info.ToolTip=tip;
            ToolTipService.SetShowDuration(info,30000);
            info.GotKeyboardFocus+=delegate {tip.PlacementTarget=info;tip.IsOpen=true;};info.LostKeyboardFocus+=delegate {tip.IsOpen=false;};info.Click+=delegate {tip.IsOpen=false;};
            return info;
        }
        private StackPanel BoundList(F.CheckedListBox source,bool licences=false) {
            var stack=new StackPanel();string signature="";
            bindings.Add(delegate {
                if(source.IsDisposed) return;bool setupModels=Object.ReferenceEquals(source,Field("models"));string current=String.Join("|",source.Items.Cast<object>().Select(x=>Convert.ToString(x)+(setupModels?controller.SetupModelStatus(Convert.ToString(x)):"")));
                if(current==signature && stack.Children.Count==source.Items.Count) return;signature=current;stack.Children.Clear();
                for(int i=0;i<source.Items.Count;i++) {
                    int index=i;var check=new CheckBox {Content=Convert.ToString(source.Items[i]),IsChecked=source.GetItemChecked(i),Margin=new Thickness(0,8,0,8)};
                    Accessible(check,Convert.ToString(source.Items[i]));check.Checked+=delegate {source.SelectedIndex=index;source.SetItemChecked(index,true);};check.Unchecked+=delegate {source.SelectedIndex=index;source.SetItemChecked(index,false);};
                    var row=new StackPanel {Orientation=Orientation.Horizontal,Tag=check};row.Children.Add(check);
                    if(licences) {check.MaxWidth=220;row.Children.Add(LicenceInfo(Convert.ToString(source.Items[i]),Object.ReferenceEquals(source,Field("engines"))));}
                    if(setupModels)row.Children.Add(Text(controller.SetupModelStatus(Convert.ToString(source.Items[i])),11,true,new Thickness(8,9,0,0)));
                    stack.Children.Add(row);
                }
            });
            bindings.Add(delegate {if(source.IsDisposed) return;for(int i=0;i<Math.Min(source.Items.Count,stack.Children.Count);i++) {var check=(CheckBox)((StackPanel)stack.Children[i]).Tag;bool value=source.GetItemChecked(i);if(check.IsChecked!=value) check.IsChecked=value;check.IsEnabled=source.Enabled;}});return stack;
        }
        private UIElement ConvertControl(F.Control control,string label) {
            if(control is F.TextBox) return BoundText((F.TextBox)control,label);
            if(control is F.ComboBox) return BoundChoice((F.ComboBox)control,label);
            if(control is F.CheckBox) return BoundCheck((F.CheckBox)control,control.Text);
            if(control is F.Button) return BoundButton((F.Button)control);
            if(control is F.CheckedListBox) return BoundList((F.CheckedListBox)control);
            if(control is F.LinkLabel) {var link=(F.LinkLabel)control;return Action(link.Text,delegate{controller.InvokePresentationLink(link);},"Quiet");}
            return null;
        }
        private void BuildGeneric(StackPanel page,F.FlowLayoutPanel source,F.Control[] controls=null,bool skipTitle=true) {
            WrapPanel commands=null;bool first=skipTitle;
            var children=controls??source.Controls.Cast<F.Control>().ToArray();
            for(int i=0;i<children.Length;i++) {
                var control=children[i];if(first && control is F.Label) {first=false;continue;}first=false;
                if(control is F.Button) {if(commands==null){commands=new WrapPanel {Margin=new Thickness(0,8,0,16)};page.Children.Add(commands);}var button=BoundButton((F.Button)control);button.Margin=new Thickness(0,0,8,8);commands.Children.Add(button);continue;} commands=null;
                if(control is F.Label) {
                    if(Convert.ToString(control.Tag)=="section-heading") {var heading=Text(control.Text,18,false,new Thickness(0,16,0,12));heading.FontWeight=FontWeights.SemiBold;page.Children.Add(heading);continue;}
                    var caption=Text(control.Text,13,true,new Thickness(0,0,0,8));
                    if(i+1<children.Length && (children[i+1] is F.TextBox || children[i+1] is F.ComboBox)) {
                        var body=new StackPanel();body.Children.Add(caption);var input=ConvertControl(children[++i],control.Text);
                        body.Children.Add(input);
                        page.Children.Add(Card(body));
                    }
                    else {page.Children.Add(caption);bindings.Add(delegate{caption.Text=control.IsDisposed?"":control.Text;});}
                } else {var element=ConvertControl(control,control.AccessibleName??control.Text);if(element!=null) page.Children.Add(Card(element));}
            }
        }
        private void Sync() {
            if(disposed) return;foreach(var update in bindings.ToArray()) update();RefreshChecks();foreach(var button in prerequisiteActions) button.IsEnabled=!Busy && (!(button.Tag is bool) || (bool)button.Tag);
            if(controller.IsSetup && !navigating && !controller.PresentationRebuilding && controller.HasRemovalTarget!=navigation.Items.Cast<ListBoxItem>().Any(x=>Convert.ToString(x.Content)=="Remove WHAS")){RebuildNavigation();return;}
            setupNext.IsEnabled=setupNextSource!=null && setupNextSource.Enabled && !Busy && (setupPage!="Prerequisites" || controller.SetupReady) && (setupPage!="Apply features" || controller.SetupReviewed);
            status.Text=controller.PresentationStatus;status.ToolTip=status.Text;
            activity.Visibility=Busy?Visibility.Visible:Visibility.Hidden;
            if(log.Text!=controller.PresentationOutput.Text) {log.Text=controller.PresentationOutput.Text;if(logOpen) log.ScrollToEnd();}
            if(status.Text!=lastStatus && (status.Text.StartsWith("Failed:") || status.Text.StartsWith("Stopped or failed"))) OpenLog(true);lastStatus=status.Text;
            if(checkSummary!=null && !Busy && ((F.DataGridView)Field("checkGrid")).Rows.Count==0 && status.Text.StartsWith("Prerequisite checks need attention")) {checkSummary.Text="The check could not complete. Open the activity log for details, then try again.";OpenLog(true);}
        }
        public void Render(string file) {
            rendering=true;controller.PreparePresentation(true);Sync();
            shell.Measure(new Size(Width,Height));shell.Arrange(new Rect(0,0,Width,Height));shell.UpdateLayout();
            var image=new RenderTargetBitmap((int)Width,(int)Height,96,96,PixelFormats.Pbgra32);image.Render(shell);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(image));using(var output=File.Create(file)) encoder.Save(output);
        }
        public void RenderPages(string directory) {rendering=true;controller.PreparePresentation(true);Directory.CreateDirectory(directory);for(int i=0;i<controller.PresentationPages.TabPages.Count;i++) {SelectPage(i);Render(Path.Combine(directory,i.ToString("00")+".png"));}}
        public void Dispose() {if(disposed) return;disposed=true;timer.Stop();Microsoft.Win32.SystemEvents.UserPreferenceChanged-=SystemThemeChanged;controller.AppearanceChanged-=AppearanceChanged;controller.PresentationChanged-=RebuildNavigation;controller.Close();controller.Dispose();if(!windowClosed) Close();}
    }
}

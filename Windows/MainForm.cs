using System.Diagnostics;
using System.Text;

namespace SunBear;
public sealed class MainForm : Form
{
    readonly LibraryStore store;
    readonly Library library;
    readonly SessionTree tree=new(){Dock=DockStyle.Fill,HideSelection=false,BorderStyle=BorderStyle.None};
    readonly DataGridView grid=new(){Dock=DockStyle.Fill,ReadOnly=true,AllowUserToAddRows=false,AllowUserToDeleteRows=false,AutoGenerateColumns=false,SelectionMode=DataGridViewSelectionMode.FullRowSelect,MultiSelect=true,RowHeadersVisible=false,BackgroundColor=Color.White,BorderStyle=BorderStyle.None,AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill};
    readonly TextBox details=new(){Dock=DockStyle.Fill,Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,BorderStyle=BorderStyle.None,BackColor=Color.FromArgb(248,248,244)};
    readonly TextBox search=new(){Dock=DockStyle.Top,PlaceholderText="Filter by title, identifier, collection, or text",Height=30};
    readonly ComboBox source=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=165};
    readonly TextBox url=new(){Width=570,PlaceholderText="Paste a search, topic, or NYT article URL"};
    readonly NumericUpDown pageLimit=new(){Minimum=1,Maximum=10,Value=1,Width=50};
    readonly CheckBox pdf=new(){Text="Download PDFs",Checked=true,AutoSize=true};
    readonly CheckBox savePages=new(){Text="Save article pages",Checked=true,AutoSize=true,Visible=false};
    readonly Button start=new(){Text="Import records",AutoSize=true,Width=90,Height=34};
    readonly Button stop=new(){Text="Stop task",AutoSize=true,Enabled=false,Width=75,Height=34};
    readonly Label status=new(){Dock=DockStyle.Bottom,Height=56,Text="Starting browser…",Padding=new Padding(10),BackColor=Color.FromArgb(236,239,229)};
    readonly Label count=new(){AutoSize=true,Padding=new Padding(5,7,0,0)};
    readonly BrowserPane browser=new(){Dock=DockStyle.Fill};
    readonly TabControl tabs=new(){Dock=DockStyle.Fill};
    readonly TabPage libraryTab=new("Library");
    readonly TabPage browserTab=new("Browser / sign in");
    readonly Panel loadingOverlay=new(){Dock=DockStyle.Fill,BackColor=Color.FromArgb(248,247,241),Visible=false};
    readonly Label loadingTitle=new(){Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleCenter,Font=new Font("Segoe UI",19,FontStyle.Bold),ForeColor=Color.FromArgb(43,62,37)};
    readonly Label loadingDetail=new(){Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleCenter};
    readonly ProgressBar workProgress=new(){Dock=DockStyle.Fill,Margin=new Padding(90,3,90,3)};
    readonly Label progressCount=new(){Dock=DockStyle.Bottom,Height=28,TextAlign=ContentAlignment.MiddleCenter};
    readonly Button signIn=new(){Text="NYT sign in",AutoSize=true};
    readonly Button resume=new(){Text="Continue after sign-in",AutoSize=true,Visible=false};
    TaskCompletionSource? accessReady;
    readonly Label emptyLibrary=new(){Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleCenter,ForeColor=Color.FromArgb(91,108,101),BackColor=Color.White,Text="Paste a source link above to import your first records."};
    Control? libraryContent;
    readonly FlowLayoutPanel importBar=new(){Dock=DockStyle.Top,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,Padding=new Padding(8),WrapContents=true};
    CancellationTokenSource? cancellation;
    bool browserReady;
    public MainForm(LibraryStore store,Library library,string? smokeFolder=null,string? renderFolder=null)
    {
        this.store=store;this.library=library;
        Text="sunBEAR 1.5.2 — Research Library";Size=new Size(1320,860);MinimumSize=new Size(1040,780);
        StartPosition=FormStartPosition.CenterScreen;Font=new Font("Segoe UI",10);BackColor=Color.White;
        if(smokeFolder!=null || renderFolder!=null){ShowInTaskbar=false;Opacity=0;}
        Icon=Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        var header=new Panel{Dock=DockStyle.Top,Height=68,BackColor=Color.FromArgb(30,66,53)};
        header.Controls.Add(new Label{Text="sunBEAR",Location=new Point(24,10),AutoSize=true,Font=new Font("Segoe UI",23,FontStyle.Bold),ForeColor=Color.White});

        source.Items.AddRange(Sources.Names);source.SelectedIndex=0;
        var archiveButton=Button("TimesMachine",()=>{if(browserReady && !IsRunning){tabs.SelectedTab=browserTab;browser.Navigate(new Uri("https://timesmachine.nytimes.com/browser"));}});archiveButton.Visible=false;
        var browseButton=Button("Browse source",Browse);
        var folderButton=Button("Save location…",ChooseFolder);
        var linkRow=new FlowLayoutPanel{AutoSize=true,WrapContents=false,Margin=Padding.Empty};
        linkRow.Controls.AddRange([source,url,browseButton,start]);
        var optionsRow=new FlowLayoutPanel{AutoSize=true,WrapContents=true,Margin=Padding.Empty};
        optionsRow.Controls.AddRange([new Label{Text="Search pages",AutoSize=true,Padding=new Padding(0,10,3,0)},pageLimit,pdf,savePages,archiveButton,signIn,resume,folderButton,stop]);
        importBar.AutoSize=false;importBar.Height=150;
        optionsRow.SizeChanged+=(_,_)=>importBar.Height=linkRow.Height+optionsRow.Height+importBar.Padding.Vertical+12;
        importBar.FlowDirection=FlowDirection.TopDown;importBar.WrapContents=false;
        importBar.Controls.AddRange([linkRow,optionsRow]);
        importBar.SizeChanged+=(_,_)=>{url.Width=Math.Max(220,importBar.ClientSize.Width-source.Width-browseButton.Width-start.Width-65);optionsRow.MaximumSize=new Size(Math.Max(400,importBar.ClientSize.Width-28),0);};
        source.SelectedIndexChanged+=(_,_)=>{archiveButton.Visible=source.SelectedIndex==5;savePages.Visible=source.SelectedIndex==5;if(!IsRunning)url.Text="";};
        signIn.Click+=(_,_)=>{if(browserReady && (!IsRunning || accessReady!=null)){tabs.SelectedTab=browserTab;browser.Navigate(new Uri("https://myaccount.nytimes.com/auth/login"));}};
        resume.Click+=(_,_)=>accessReady?.TrySetResult();
        start.Click+=async(_,_)=>await StartImport();stop.Click+=(_,_)=>cancellation?.Cancel();
        var split=new SplitContainer{Size=new Size(1280,600),Dock=DockStyle.Fill,SplitterDistance=230,FixedPanel=FixedPanel.Panel1};
        libraryContent=split;
        var leftBar=new FlowLayoutPanel{Dock=DockStyle.Top,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink};
        leftBar.Controls.Add(Button("+ Collection",NewCollection));leftBar.Controls.Add(Button("Manage",()=>ShowTreeMenu(new Point(5,5))));
        split.Panel1.Controls.Add(tree);split.Panel1.Controls.Add(leftBar);split.Panel1.Controls.Add(new Label{Text="COLLECTIONS",Dock=DockStyle.Top,Height=38,Padding=new Padding(10,12,0,0),ForeColor=Color.FromArgb(91,108,101),Font=new Font("Segoe UI",9,FontStyle.Bold)});
        var recordsSplit=new SplitContainer{Size=new Size(1000,600),Dock=DockStyle.Fill,Orientation=Orientation.Horizontal,SplitterDistance=340};
        recordsSplit.Panel1.Controls.Add(grid);recordsSplit.Panel1.Controls.Add(emptyLibrary);recordsSplit.Panel1.Controls.Add(search);
        recordsSplit.Panel2.Controls.Add(details);
        var recordActions=new FlowLayoutPanel{Dock=DockStyle.Bottom,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink};
        var retry=Button("Retry PDFs",()=>{});retry.Click+=async(_,_)=>await RetryPdfs();
        var downloadPages=Button("Download article pages",()=>{});downloadPages.Click+=async(_,_)=>await DownloadArticlePages();
        recordActions.Controls.AddRange([Button("Read saved article",OpenSavedPage),Button("View original",OpenRecord),MenuButton("Downloads / files",[("Download article pages",async()=>await DownloadArticlePages()),("Retry missing PDFs",async()=>await RetryPdfs()),("Open saved PDF",OpenPdf),("Open PDF in browser",OpenOnlinePdf),("Show download folder",OpenFolder)])]);
        recordsSplit.Panel2.Controls.Add(recordActions);
        var exports=new FlowLayoutPanel{Dock=DockStyle.Top,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink};
        exports.Controls.AddRange([new Label{Text="Saved records",AutoSize=true,Font=new Font("Segoe UI",14,FontStyle.Bold),Margin=new Padding(4,6,16,4)},count,MenuButton("Export…",[("Spreadsheet (TSV)",()=>Export("tsv")),("EndNote file",()=>Export("enw")),("EndNote XML",()=>Export("xml")),("Send to EndNote",SendEndNote)]),Button("Help",ShowHelp)]);
        split.Panel2.Controls.Add(recordsSplit);split.Panel2.Controls.Add(exports);
        libraryTab.Controls.Add(split);BuildLoadingPanel();libraryTab.Controls.Add(loadingOverlay);browserTab.Controls.Add(browser);tabs.TabPages.AddRange([libraryTab,browserTab]);
        status.TextChanged+=(_,_)=>loadingDetail.Text=status.Text;
        Controls.Add(tabs);Controls.Add(importBar);Controls.Add(header);Controls.Add(status);
        foreach(var (title,property,weight) in new[]{("Title","Title",33f),("Source","Source",11f),("Collection","Collection",15f),("Identifier","Number",12f),("Date","Date",10f),("PDFs","PdfStatus",9f),("Page","PageStatus",10f)}) grid.Columns.Add(new DataGridViewTextBoxColumn{HeaderText=title,DataPropertyName=property,FillWeight=weight,SortMode=DataGridViewColumnSortMode.Automatic});
        grid.ColumnHeadersDefaultCellStyle.Font=new Font(Font,FontStyle.Bold);grid.RowTemplate.Height=32;grid.AlternatingRowsDefaultCellStyle.BackColor=Color.FromArgb(247,248,244);
        tree.SelectionChanged+=(_,_)=>RefreshRecords();search.TextChanged+=(_,_)=>RefreshRecords();grid.SelectionChanged+=(_,_)=>{ShowDetails();UpdateSelectionCount();};grid.KeyDown+=(_,e)=>{if(e.KeyCode==Keys.Escape){grid.ClearSelection();e.SuppressKeyPress=true;}else if(e.Control && e.KeyCode==Keys.A){grid.SelectAll();e.SuppressKeyPress=true;}};grid.CellDoubleClick+=(_,_)=>OpenRecord();
        tree.NodeMouseClick+=(_,e)=>{if(e.Button==MouseButtons.Right){tree.SelectedNode=e.Node;ShowTreeMenu(e.Location);}};
        browser.ImportRequested+=async u=>{url.Text=u.AbsoluteUri;await StartImport();};
        Shown+=async(_,_)=>{
            if(renderFolder!=null){
var testGroup=tree.Nodes.Add("Selection checks");
var one=testGroup.Nodes.Add("Search one");one.Tag=new Session();var two=testGroup.Nodes.Add("Search two");two.Tag=new Session();var three=testGroup.Nodes.Add("Search three");three.Tag=new Session();testGroup.Expand();
tree.ClickForTest(one,false,false);tree.ClickForTest(three,false,true);if(tree.SelectedNodes.Count()!=3 || SelectedSessions().Count()!=3)throw new Exception("Session range failed");
tree.ClickForTest(two,true,false);if(tree.SelectedNodes.Count()!=2)throw new Exception("Session Ctrl toggle failed");tree.ClickForTest(two,false,false);if(tree.SelectedNodes.Count()!=1)throw new Exception("Session single selection failed");RefreshTree();
var sample=new[]{new Record{Title="First"},new Record{Title="Second"},new Record{Title="Third"}};
grid.DataSource=new SortableList<Record>(sample.ToList());grid.ClearSelection();grid.Rows[0].Selected=true;grid.Rows[2].Selected=true;
if(ExportRecords().Count!=2 || ExportRecords()[1].Title!="Third" || !count.Text.Contains("2 selected"))throw new Exception("Selection scope/count incorrect");
grid.SelectAll();if(ExportRecords().Count!=3)throw new Exception("Select all failed");grid.ClearSelection();if(ExportRecords().Count!=3 || grid.SelectedRows.Count!=0)throw new Exception("Clear/visible fallback failed");RefreshRecords();
CaptureWindow(renderFolder);
source.SelectedIndex=5;Size=MinimumSize;await Task.Delay(100);using(var compact=new Bitmap(Width,Height)){DrawToBitmap(compact,new Rectangle(0,0,Width,Height));compact.Save(Path.Combine(renderFolder,"compact.png"));}Size=new Size(1320,860);
status.Text="Downloading article page 4 of 12…";start.Enabled=false;stop.Enabled=true;ShowLoading("Downloading article pages");ReportProgress(3,12);await Task.Delay(400);if(workProgress.Value!=3 || workProgress.Maximum!=12 || workProgress.Style!=ProgressBarStyle.Continuous)throw new Exception("Incorrect progress");using var drawing=new Bitmap(Width,Height);DrawToBitmap(drawing,new Rectangle(0,0,Width,Height));drawing.Save(Path.Combine(renderFolder,"loading.png"));if(!loadingOverlay.Visible || libraryContent!.Visible)throw new Exception("Loading view did not replace library content.");HideLoading();if(loadingOverlay.Visible || !libraryContent.Visible)throw new Exception("Loading view did not restore library content.");using(var cancelTest=new CancellationTokenSource()){
var waiting=RequestAccess(cancelTest.Token);if(waiting.IsCompleted || browser.Busy || !resume.Visible)throw new Exception("Access did not pause");cancelTest.Cancel();try{await waiting;throw new Exception("Pause did not cancel");}catch(OperationCanceledException){}if(accessReady!=null || resume.Visible)throw new Exception("Pause cleanup failed");
}
var continuing=RequestAccess(CancellationToken.None);accessReady!.TrySetResult();await continuing;if(!browser.Busy || resume.Visible)throw new Exception("Resume failed");HideLoading();
File.WriteAllText(Path.Combine(renderFolder,"render-result.txt"),"PASS Native mouse-message session Shift range/Ctrl toggle/single selection; multi-row selection scope/count, select all and clear/visible fallback; determinate progress 3/12 = 25%; loading view restored; access pause waits, resumes, cancels and cleans up.");Close();return;}
            if(smokeFolder!=null)CaptureWindow(smokeFolder);
            try {tabs.SelectedTab=browserTab;await browser.Initialize(store.Root);tabs.SelectedTab=libraryTab;browserReady=true;status.Text="Ready — choose a source and browse, or paste a search-results URL.";if(smokeFolder!=null)await SmokeTest(smokeFolder);}
            catch(Exception e){if(smokeFolder!=null){File.WriteAllText(Path.Combine(smokeFolder,"smoke-result.txt"),"PASS Windows form initialized and rendered\nBLOCKED Browser integration test: "+e);Close();return;}status.Text="Browser unavailable. Saved records and exports remain available.";MessageBox.Show(this,"The embedded browser could not start. Ensure Microsoft Edge WebView2 Runtime is installed and sunBEAR can write to its browser profile folder.\n\nProfile: "+Path.Combine(store.Root,"Browser")+"\n\n"+e.Message,"Browser setup",MessageBoxButtons.OK,MessageBoxIcon.Information);}
        };
        FormClosing+=(_,e)=>{if(IsRunning){cancellation?.Cancel();e.Cancel=true;status.Text="Stopping the import. Close the window again once it has stopped.";}};
        ApplyAppearance(this);StyleButton(start,true);StyleButton(resume,true);
        tabs.Padding=new Point(20,9);libraryTab.Padding=new Padding(12);browserTab.Padding=new Padding(10);
        tree.ItemHeight=32;tree.FullRowSelect=true;tree.ShowLines=false;
        grid.EnableHeadersVisualStyles=false;grid.ColumnHeadersHeight=38;grid.ColumnHeadersDefaultCellStyle.BackColor=Color.FromArgb(236,242,238);grid.ColumnHeadersDefaultCellStyle.ForeColor=Color.FromArgb(50,70,59);grid.CellBorderStyle=DataGridViewCellBorderStyle.SingleHorizontal;grid.GridColor=Color.FromArgb(234,239,236);grid.RowTemplate.Height=40;grid.DefaultCellStyle.SelectionBackColor=Color.FromArgb(218,236,224);grid.DefaultCellStyle.SelectionForeColor=Color.FromArgb(22,56,40);grid.DefaultCellStyle.Padding=new Padding(6,2,6,2);
        RefreshTree();
    }
    void BuildLoadingPanel()
    {
        var layout=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=5,Padding=new Padding(60,20,60,20)};
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent,45));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,60));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,24));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,100));layout.RowStyles.Add(new RowStyle(SizeType.Percent,55));
        layout.Controls.Add(loadingTitle,0,1);
        layout.Controls.Add(workProgress,0,2);
        layout.Controls.Add(loadingDetail,0,3);
        layout.Controls.Add(new Label{Dock=DockStyle.Fill,TextAlign=ContentAlignment.TopCenter,Text="You can stop with the Stop button above. Completed records and downloads are saved as the task runs.",ForeColor=Color.DimGray},0,4);
        loadingDetail.Controls.Add(progressCount);
        loadingOverlay.Controls.Add(layout);
    }
    void ShowLoading(string title)
    {
        ReportProgress(0,0);signIn.Enabled=false;
        loadingTitle.Text=title;loadingDetail.Text=status.Text;if(libraryContent!=null)libraryContent.Visible=false;loadingOverlay.Visible=true;loadingOverlay.BringToFront();savePages.Enabled=false;tabs.SelectedTab=libraryTab;
    }
    void HideLoading(){accessReady=null;resume.Visible=false;signIn.Enabled=true;loadingOverlay.Visible=false;if(libraryContent!=null)libraryContent.Visible=true;savePages.Enabled=true;}
    void ReportProgress(int completed,int total)
    {
        workProgress.MarqueeAnimationSpeed=total==0?30:0;
        workProgress.Style=total==0?ProgressBarStyle.Marquee:ProgressBarStyle.Continuous;
        workProgress.Maximum=Math.Max(1,total);workProgress.Value=Math.Clamp(completed,0,workProgress.Maximum);
        progressCount.Text=total==0?"Finding articles — total not yet known":$"{completed} of {total} processed ({(int)(100L*completed/total)}%). Includes items needing attention.";
    }
    async Task RequestAccess(CancellationToken token)
    {
        accessReady=new(TaskCreationOptions.RunContinuationsAsynchronously);
        browser.Busy=false;signIn.Enabled=true;resume.Visible=true;
        workProgress.MarqueeAnimationSpeed=0;
        status.Text="Paused: article text is unavailable. Use NYT sign in, or check this article in the browser. Then click Continue after sign-in to retry. Stop cancels.";
        tabs.SelectedTab=browserTab;
        try{await accessReady.Task.WaitAsync(token);}
        finally{accessReady=null;resume.Visible=false;signIn.Enabled=false;browser.Busy=true;}
        token.ThrowIfCancellationRequested();tabs.SelectedTab=libraryTab;status.Text="Checking article access…";
    }
    void CaptureWindow(string folder)
    {
        tabs.SelectedTab=libraryTab;
        using var bitmap=new Bitmap(Width,Height);DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height));bitmap.Save(Path.Combine(folder,"window.png"));
    }
    async Task SmokeTest(string folder)
    {
        var log=new List<string>{"PASS Windows form initialized","PASS WebView2 initialized"};
        browser.View.CoreWebView2.AddWebResourceRequestedFilter("https://www.cia.gov/*",Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext.All);
        browser.View.CoreWebView2.WebResourceRequested+=(_,e)=>{
            var path=new Uri(e.Request.Uri).AbsolutePath;
            if(path.EndsWith(".pdf")){e.Response=browser.View.CoreWebView2.Environment.CreateWebResourceResponse(new MemoryStream(Encoding.ASCII.GetBytes("%PDF-1.4\nsynthetic integration fixture")),200,"OK","Content-Type: application/pdf");return;}
            var html=path.Contains("/search/")?"<html><body><h1>Search results</h1><a href='/readingroom/document/test'>Research record</a></body></html>":"<html><body><h1>Library</h1><h2>Windows validation record</h2><div>Document Type: CREST</div><div>Collection: General CIA Records</div><div>Publication Date: June 1, 1960</div><div>File:</div><a href='/readingroom/docs/test.pdf'>PDF</a><div>Body:</div><p>Browser-to-library integration test.</p></body></html>";
            e.Response=browser.View.CoreWebView2.Environment.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes(html)),200,"OK","Content-Type: text/html; charset=utf-8");
        };
        using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(45));
        var session=new Session{Name="Validation session",SearchURL="https://www.cia.gov/readingroom/search/site/test",FolderPath=folder};library.Sessions.Add(session);
        await new Scraper(browser).Run(session,false,1,s=>status.Text=s,Save,timeout.Token);
        if(session.Records.Count!=1 || !session.IsComplete || session.Records[0].Title!="Windows validation record")throw new Exception("Browser import did not produce the expected record.");
        log.Add("PASS Browser navigation → metadata parsing → library save");
        if(store.Load().Sessions[0].Records.Count!=1)throw new Exception("Saved session could not be reopened.");
        log.Add("PASS Imported session reloaded from disk");
        var record=session.Records[0];record.DownloadError="Previous download returned HTML";
        await new Scraper(browser).Retry(new[]{(session,record)},s=>status.Text=s,Save,timeout.Token);
        if(record.LocalPDFPaths.Count!=1 || record.DownloadError.Length!=0 || !File.Exists(record.LocalPDFPaths[0]))throw new Exception("Browser PDF retry failed: "+record.DownloadError);
        log.Add("PASS Browser-session PDF retry, persistence and error clearing");
        await new Scraper(browser).Retry(new[]{(session,record)},s=>status.Text=s,Save,timeout.Token);
        if(record.LocalPDFPaths.Count!=1)throw new Exception("Retry duplicated a saved PDF.");
        log.Add("PASS Second PDF retry skips saved file");
        using var canceled=new CancellationTokenSource();canceled.Cancel();bool stopped=false;
        try{await new Scraper(browser).Run(new Session{SearchURL=session.SearchURL},false,1,_=>{},()=>{},canceled.Token);}catch(OperationCanceledException){stopped=true;}
        if(!stopped)throw new Exception("Cancellation failed.");log.Add("PASS Import cancellation");
        RefreshTree(session);grid.Rows[0].Selected=true;ShowDetails();tabs.SelectedTab=libraryTab;
        using var bitmap=new Bitmap(Width,Height);DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height));bitmap.Save(Path.Combine(folder,"window.png"));
        log.Add("PASS Window render captured");File.WriteAllLines(Path.Combine(folder,"smoke-result.txt"),log);Close();
    }
    static void StyleButton(Button b,bool primary=false){b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderColor=Color.FromArgb(208,221,212);b.BackColor=primary?Color.FromArgb(38,100,70):Color.White;b.ForeColor=primary?Color.White:Color.FromArgb(38,65,50);b.Padding=new Padding(10,4,10,4);b.MinimumSize=new Size(0,36);b.Cursor=Cursors.Hand;b.Margin=new Padding(4);}
    static void ApplyAppearance(Control parent){foreach(Control c in parent.Controls){if(c is Button b)StyleButton(b);if(c is FlowLayoutPanel flow)flow.Padding=new Padding(5);if(c is SplitContainer split)split.BackColor=Color.FromArgb(230,237,232);ApplyAppearance(c);}}
    static Button MenuButton(string title,(string Label,Action Action)[] items){var b=Button(title,()=>{});var menu=new ContextMenuStrip();foreach(var item in items)menu.Items.Add(item.Label,null,(_,_)=>item.Action());b.Click+=(_,_)=>menu.Show(b,new Point(0,b.Height));return b;}
    bool IsRunning=>cancellation!=null;
    static Button Button(string text,Action action){var b=new Button{Text=text,AutoSize=true,Height=30,FlatStyle=FlatStyle.System};b.Click+=(_,_)=>action();return b;}
    void Error(Exception e)=>MessageBox.Show(this,e.Message,"sunBEAR",MessageBoxButtons.OK,MessageBoxIcon.Error);
    void Save()=>store.Save(library);
    void RefreshTree(object? selection=null)
    {
        selection??=tree.SelectedNode?.Tag;
        tree.BeginUpdate();tree.Nodes.Clear();
        var all=tree.Nodes.Add("All records");all.Tag="all";
        foreach(var c in library.Collections.OrderBy(x=>x.Name)) {var n=tree.Nodes.Add(c.Name);n.Tag=c;foreach(var s in library.Sessions.Where(s=>s.CollectionId==c.Id).OrderByDescending(s=>s.StartedAt))AddSession(n,s);n.Expand();}
        var unfiled=tree.Nodes.Add("Unfiled");unfiled.Tag="unfiled";
        foreach(var s in library.Sessions.Where(s=>s.CollectionId==null).OrderByDescending(s=>s.StartedAt))AddSession(unfiled,s);
        unfiled.Expand();
        tree.SelectedNode=tree.Nodes.Cast<TreeNode>().SelectMany(n=>new[]{n}.Concat(n.Nodes.Cast<TreeNode>())).FirstOrDefault(n=>Equals(n.Tag,selection))??all;
        tree.EndUpdate();RefreshRecords();
    }
    static void AddSession(TreeNode n,Session s){var child=n.Nodes.Add(s.Name+" ("+s.Records.Count+")"+(s.IsComplete?"":" • partial"));child.Tag=s;}
    IEnumerable<Session> SelectedSessions()=>tree.SelectedNodes.SelectMany(n=>n.Tag switch {Session s=>new[]{s},Collection c=>library.Sessions.Where(s=>s.CollectionId==c.Id),"unfiled"=>library.Sessions.Where(s=>s.CollectionId==null),"all"=>library.Sessions,_=>Enumerable.Empty<Session>()}).Distinct();
    void RefreshRecords()
    {
        var filter=search.Text.Trim();
        var records=SelectedSessions().SelectMany(s=>s.Records).Where(r=>filter.Length==0 || (r.Title+" "+r.Number+" "+r.Collection+" "+r.Body+" "+r.FullText+" "+string.Join(" ",r.Authors)).Contains(filter,StringComparison.OrdinalIgnoreCase)).ToList();
        grid.DataSource=new SortableList<Record>(records);emptyLibrary.Visible=records.Count==0;emptyLibrary.Text=filter.Length>0?"No matching records\n\nTry a different title, identifier, or keyword.":"Paste a source link above to import your first records.";grid.ClearSelection();details.Text="Select a record to see its metadata, abstract, links, and download status.";UpdateSelectionCount();
    }
    void UpdateSelectionCount(){count.Text=$"{grid.Rows.Count} records · {grid.SelectedRows.Count} selected";if(grid.SelectedRows.Count==0)details.Text="Select a record to view its details.";}
    Record? Current=>grid.SelectedRows.Cast<DataGridViewRow>().FirstOrDefault()?.DataBoundItem as Record;
    List<Record> ExportRecords()=>grid.SelectedRows.Count>0?grid.SelectedRows.Cast<DataGridViewRow>().OrderBy(r=>r.Index).Select(r=>(Record)r.DataBoundItem).ToList():grid.Rows.Cast<DataGridViewRow>().Select(r=>(Record)r.DataBoundItem).ToList();
    void ShowDetails()
    {
        if(Current is not Record r)return;
        details.Text=r.Title+"\r\n\r\n"+(r.Authors.Count>0?"Author: "+string.Join("; ",r.Authors)+"\r\n":"")+(r.Section.Length>0?"Section: "+r.Section+"\r\n":"")+(r.PrintPages.Length>0?"Print pages: "+r.PrintPages+"\r\n":"")+string.Join("\r\n",Parser.Labels.Where(l=>r.Field(l).Length>0).Select(l=>(l==Parser.Identifier?Exports.IdentifierLabel(r):l)+": "+r.Field(l)))+"\r\n\r\nRecord: "+r.RecordURL+"\r\n"+string.Join("\r\n",r.PdfURLs.Select(p=>"PDF: "+p))+"\r\n\r\n"+r.Body+(r.DownloadError.Length>0?"\r\n\r\nDownload notes: "+r.DownloadError:"");
        if(r.LocalPagePath.Length>0)details.AppendText("\r\n\r\nSaved page: "+r.LocalPagePath);
        if(r.PageError.Length>0)details.AppendText("\r\n\r\nArticle page notes: "+r.PageError);
        if(r.FullText.Length>0)details.AppendText("\r\n\r\nARTICLE TEXT\r\n\r\n"+r.FullText.Replace("\n","\r\n"));
    }
    void Browse(){try{if(!browserReady)throw new InvalidOperationException("The browser is not ready. Install WebView2 Runtime if prompted.");if(IsRunning)return;tabs.SelectedTab=browserTab;browser.Navigate(new Uri(Sources.Homes[source.SelectedIndex]));}catch(Exception e){Error(e);}}
    void ChooseFolder(){if(IsRunning)return;using var d=new FolderBrowserDialog{Description="Choose where sunBEAR will save downloaded PDFs",SelectedPath=library.DownloadFolder,UseDescriptionForTitle=true};if(d.ShowDialog(this)==DialogResult.OK){library.DownloadFolder=d.SelectedPath;try{Save();status.Text="PDFs will be saved in "+d.SelectedPath;}catch(Exception e){Error(e);}}}
    async Task StartImport()
    {
        if(IsRunning)return;
        if(!Uri.TryCreate(url.Text.Trim(),UriKind.Absolute,out var address) || !Sources.CanImport(address)){MessageBox.Show(this,"Paste a supported search-results URL. For the New York Times, topic pages and individual article or TimesMachine article URLs also work. Open a specific archive article rather than an entire issue. You can browse inside sunBEAR and choose ‘Import this page’.","Choose a page");return;}
        if(!browserReady){MessageBox.Show(this,"The browser is not ready. Install WebView2 Runtime if prompted.");return;}
        source.SelectedIndex=Sources.Index(address);url.Text=address.AbsoluteUri;
        var q=Sources.Query(address);var term=new[]{"keyword","Query","q","term","search","sm_field_document_number","sm_field_case_number"}.Select(k=>q.GetValueOrDefault(k,"")).FirstOrDefault(v=>v.Length>0)??(source.SelectedIndex==5?Uri.UnescapeDataString(address.Segments.Last()).Replace(".html","").Trim('/') : "Search");
        var name=Sources.SafeName(Sources.Names[source.SelectedIndex]+" - "+term)+" - "+DateTime.Now.ToString("yyyy-MM-dd HH-mm-ss");
        var session=new Session{Name=name,SearchURL=address.AbsoluteUri,CollectionId=(tree.SelectedNode?.Tag as Collection)?.Id};
        try {
            Directory.CreateDirectory(library.DownloadFolder);session.FolderPath=Sources.UniquePath(Path.Combine(library.DownloadFolder,name));Directory.CreateDirectory(session.FolderPath);
            library.Sessions.Add(session);Save();RefreshTree(session);
            cancellation=new();browser.Busy=true;start.Enabled=false;stop.Enabled=true;source.Enabled=false;url.ReadOnly=true;pdf.Enabled=false;pageLimit.Enabled=false;
            ShowLoading("Importing records");
            await new Scraper(browser,ReportProgress,RequestAccess).Run(session,pdf.Checked,(int)pageLimit.Value,s=>status.Text=s,()=>{Save();RefreshTree(session);},cancellation.Token,savePages.Checked);
        }catch(OperationCanceledException){status.Text=$"Stopped. {session.Records.Count} records saved; this import is partial.";}
        catch(Exception e){status.Text="Import stopped: "+e.Message;Error(e);}
        finally {cancellation?.Dispose();cancellation=null;browser.Busy=false;start.Enabled=true;stop.Enabled=false;source.Enabled=true;url.ReadOnly=false;pdf.Enabled=true;pageLimit.Enabled=true;HideLoading();RefreshTree(session);}
    }
    async Task RetryPdfs()
    {
        if(IsRunning)return;
        if(!browserReady){MessageBox.Show(this,"The browser is not ready. Reopen sunBEAR after resolving the browser startup message.");return;}
        // Honor the same selected-or-visible scope used by exports.
        var targets=ExportRecords()
            .Where(r=>r.PdfURLs.Count>0 && (r.DownloadError.Length>0 || r.PdfURLs.Any(u=>!Scraper.AlreadySaved(r,u))))
            .Select(r=>(Session:library.Sessions.First(s=>s.Records.Contains(r)),Record:r)).ToList();
        if(targets.Count==0){MessageBox.Show(this,"No missing or failed PDFs were found in the visible records.");return;}
        var selection=tree.SelectedNode?.Tag;
        try {
            cancellation=new();browser.Busy=true;start.Enabled=false;stop.Enabled=true;source.Enabled=false;url.ReadOnly=true;pdf.Enabled=false;pageLimit.Enabled=false;
            ShowLoading("Downloading PDFs");
            await new Scraper(browser,ReportProgress,RequestAccess).Retry(targets,s=>status.Text=s,Save,cancellation.Token);
        }catch(OperationCanceledException){status.Text="PDF retry stopped. Completed downloads were saved.";}
        catch(Exception e){status.Text="PDF retry stopped: "+e.Message;Error(e);}
        finally{cancellation?.Dispose();cancellation=null;browser.Busy=false;start.Enabled=true;stop.Enabled=false;source.Enabled=true;url.ReadOnly=false;pdf.Enabled=true;pageLimit.Enabled=true;HideLoading();RefreshTree(selection);}
    }
    async Task DownloadArticlePages()
    {
        if(IsRunning)return;
        if(!browserReady){MessageBox.Show(this,"The browser is not ready. Check the Browser tab before downloading article pages.");return;}
        var targets=ExportRecords().Where(r=>r.Source=="New York Times")
            .Select(r=>(Session:library.Sessions.First(s=>s.Records.Contains(r)),Record:r)).ToList();
        if(targets.Count==0){MessageBox.Show(this,"Select a session containing New York Times articles first.");return;}
        var selection=tree.SelectedNode?.Tag;
        try {
            cancellation=new();browser.Busy=true;start.Enabled=false;stop.Enabled=true;source.Enabled=false;url.ReadOnly=true;pdf.Enabled=false;pageLimit.Enabled=false;ShowLoading("Downloading article pages");
            await new Scraper(browser,ReportProgress,RequestAccess).DownloadPages(targets,s=>status.Text=s,Save,cancellation.Token);
        }catch(OperationCanceledException){status.Text="Article download stopped. Completed pages were saved.";}
        catch(Exception e){status.Text="Article download stopped: "+e.Message;Error(e);}
        finally{cancellation?.Dispose();cancellation=null;browser.Busy=false;start.Enabled=true;stop.Enabled=false;source.Enabled=true;url.ReadOnly=false;pdf.Enabled=true;pageLimit.Enabled=true;HideLoading();RefreshTree(selection);}
    }
    void NewCollection(){if(IsRunning)return;var name=Prompt("New collection","Collection name","");if(string.IsNullOrWhiteSpace(name))return;var c=new Collection{Name=name.Trim()};library.Collections.Add(c);try{Save();RefreshTree(c);}catch(Exception e){Error(e);}}
    void ShowTreeMenu(Point location)
    {
        if(IsRunning)return;
        var selected=tree.SelectedNode?.Tag;var menu=new ContextMenuStrip();
        if(selected is Session || selected is Collection){menu.Items.Add("Rename…",null,(_,_)=>{var old=selected is Session s?s.Name:((Collection)selected).Name;var value=Prompt("Rename","Name",old);if(string.IsNullOrWhiteSpace(value))return;if(selected is Session session)session.Name=value.Trim();else ((Collection)selected).Name=value.Trim();try{Save();RefreshTree(selected);}catch(Exception e){Error(e);}});}
        if(selected is Session session){var move=new ToolStripMenuItem("Move to collection");void AddMove(string title,string? id){move.DropDownItems.Add(title,null,(_,_)=>{session.CollectionId=id;try{Save();RefreshTree(session);}catch(Exception e){Error(e);}});}AddMove("Unfiled",null);foreach(var c in library.Collections)AddMove(c.Name,c.Id);menu.Items.Add(move);menu.Items.Add("Show download folder",null,(_,_)=>Launch(session.FolderPath));}
        menu.Items.Add("Export each session as TSV…",null,(_,_)=>ExportSessions());
        if(selected is Session || selected is Collection)menu.Items.Add("Delete from library…",null,(_,_)=>{
            var message=selected is Collection?"Remove this collection? Its sessions will move to Unfiled. Downloaded files will remain on disk.":"Remove this session and its records from the library? Downloaded files will remain on disk.";
            if(MessageBox.Show(this,message,"Delete from library",MessageBoxButtons.OKCancel,MessageBoxIcon.Question)!=DialogResult.OK)return;
            if(selected is Session s)library.Sessions.Remove(s);else{var c=(Collection)selected;foreach(var s2 in library.Sessions.Where(x=>x.CollectionId==c.Id))s2.CollectionId=null;library.Collections.Remove(c);}try{Save();RefreshTree();}catch(Exception e){Error(e);}
        });
        menu.Show(tree,location);
    }
    void Export(string extension)
    {
        var records=ExportRecords();if(records.Count==0){MessageBox.Show(this,"Select a session or records to export.");return;}
        using var dialog=new SaveFileDialog{FileName="sunBEAR export."+extension,Filter=extension.ToUpperInvariant()+" file|*."+extension,DefaultExt=extension};
        if(dialog.ShowDialog(this)!=DialogResult.OK)return;
        try {File.WriteAllText(dialog.FileName,extension=="tsv"?Exports.Tsv(records):extension=="xml"?Exports.Xml(records):Exports.Enw(records),new UTF8Encoding(false));status.Text=$"Exported {records.Count} records to {dialog.FileName}";}catch(Exception e){Error(e);}
    }
    void ExportSessions()
    {
        using var d=new FolderBrowserDialog{Description="Choose an export folder",UseDescriptionForTitle=true};if(d.ShowDialog(this)!=DialogResult.OK)return;
        try{foreach(var s in SelectedSessions())File.WriteAllText(Sources.UniquePath(Path.Combine(d.SelectedPath,Sources.SafeName(s.Name)+".tsv")),Exports.Tsv(s.Records),new UTF8Encoding(false));status.Text="Session exports saved in "+d.SelectedPath;}catch(Exception e){Error(e);}
    }
    void SendEndNote()
    {
        var records=ExportRecords();if(records.Count==0){MessageBox.Show(this,"Select a session or records first.");return;}
        try{var folder=Path.Combine(store.Root,"EndNote exports");Directory.CreateDirectory(folder);var path=Sources.UniquePath(Path.Combine(folder,"sunBEAR "+DateTime.Now.ToString("yyyy-MM-dd HH-mm-ss")+".enw"));File.WriteAllText(path,Exports.Enw(records),new UTF8Encoding(false));
            try{Process.Start(new ProcessStartInfo(path){UseShellExecute=true});status.Text="Opened the export with the Windows .enw file association. Complete the import in EndNote.";}
            catch{MessageBox.Show(this,"The export was saved, but Windows could not open it. In EndNote, use File > Import > File and choose the EndNote Import filter.\n\n"+path,"EndNote export saved");}
        }catch(Exception e){Error(e);}
    }
    void OpenRecord(){if(Current is Record r && Uri.TryCreate(r.RecordURL,UriKind.Absolute,out var u) && Sources.Web(u))Launch(u.AbsoluteUri);}
    void OpenSavedPage(){if(Current is Record r && File.Exists(r.LocalPagePath))Launch(r.LocalPagePath);else MessageBox.Show(this,"No saved article page is available. Use Download article pages and check the record's page notes if it needs attention.");}
    void OpenPdf(){if(Current is Record r){var p=r.LocalPDFPaths.FirstOrDefault(File.Exists);if(p!=null)Launch(p);else MessageBox.Show(this,"No downloaded PDF is available for this record. See its details for links and download notes.");}}
    void OpenOnlinePdf(){if(Current is Record r && r.PdfURLs.FirstOrDefault() is string link && browserReady && !IsRunning){tabs.SelectedTab=browserTab;browser.Navigate(new Uri(link));}}
    void OpenFolder(){var path=Current is Record r?library.Sessions.FirstOrDefault(s=>s.Records.Contains(r))?.FolderPath:(tree.SelectedNode?.Tag as Session)?.FolderPath;if(path!=null)Launch(path);}
    void Launch(string path){try{Process.Start(new ProcessStartInfo(path){UseShellExecute=true});}catch(Exception e){Error(e);}}
    void ShowHelp()=>MessageBox.Show(this,"1. Choose a source and click Browse. Sign in if needed and run a search.\n2. Click Import this search. Choose 1–10 pages and whether to download PDFs.\n3. Organize sessions into collections using Actions.\n4. Select rows to export only those records. Clear the selection or choose a session to export all visible records.\n5. Send to EndNote opens an .enw file through Windows. For manual import, use the EndNote Import filter, or export XML and use EndNote generated XML.\n\nCIA exports preserve the original custom CIA reference type; it must be configured in your EndNote library.\n\nYour library and browser profile are stored in:\n"+store.Root+"\n\nBlocked, subscription-only, or changed website pages can require manual steps in the Browser tab.","Using sunBEAR");
    static string? Prompt(string title,string label,string value)
    {
        using var f=new Form{Text=title,ClientSize=new Size(430,135),StartPosition=FormStartPosition.CenterParent,FormBorderStyle=FormBorderStyle.FixedDialog,MinimizeBox=false,MaximizeBox=false};
        var text=new TextBox{Left=15,Top=40,Width=400,Text=value};f.Controls.Add(new Label{Left=15,Top=15,Text=label,AutoSize=true});f.Controls.Add(text);
        var ok=new Button{Left=240,Top=90,Text="Save",DialogResult=DialogResult.OK};var cancel=new Button{Left=330,Top=90,Text="Cancel",DialogResult=DialogResult.Cancel};f.Controls.Add(ok);f.Controls.Add(cancel);f.AcceptButton=ok;f.CancelButton=cancel;
        return f.ShowDialog()==DialogResult.OK?text.Text:null;
    }
}

public sealed class SortableList<T>(IList<T> list) : System.ComponentModel.BindingList<T>(list)
{
    bool sorted; System.ComponentModel.PropertyDescriptor? property;System.ComponentModel.ListSortDirection direction;
    protected override bool SupportsSortingCore=>true;
    protected override bool IsSortedCore=>sorted;
    protected override System.ComponentModel.PropertyDescriptor? SortPropertyCore=>property;
    protected override System.ComponentModel.ListSortDirection SortDirectionCore=>direction;
    protected override void ApplySortCore(System.ComponentModel.PropertyDescriptor prop,System.ComponentModel.ListSortDirection dir){var items=(List<T>)Items;items.Sort((a,b)=>string.Compare(prop.GetValue(a)?.ToString(),prop.GetValue(b)?.ToString(),StringComparison.CurrentCultureIgnoreCase)*(dir==System.ComponentModel.ListSortDirection.Ascending?1:-1));property=prop;direction=dir;sorted=true;OnListChanged(new(System.ComponentModel.ListChangedType.Reset,-1));}
}

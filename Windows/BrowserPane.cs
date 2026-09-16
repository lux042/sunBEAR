using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using System.Text.Json;

namespace SunBear;
public sealed class BrowserPane : UserControl
{
    public WebView2 View { get; } = new() { Dock=DockStyle.Fill };
    public TextBox Address { get; } = new() { Width=650, PlaceholderText="Search or paste a web address" };
    public event Action<ImportPage>? ImportRequested;
    readonly Button preparePdf=new(){Text="Prepare PDF downloads",AutoSize=true,Visible=false};
    readonly Label guidance=new(){Dock=DockStyle.Top,AutoSize=true,MaximumSize=new Size(1100,0),Padding=new Padding(8),ForeColor=Color.FromArgb(50,70,59)};
    public bool Busy { get; set; }
    readonly FlowLayoutPanel bar=new() {Dock=DockStyle.Top,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,Padding=new Padding(4)};
    public BrowserPane()
    {
        Controls.Add(View);Controls.Add(guidance); Controls.Add(bar);
        Button Add(string text,Action action) { var b=new Button {Text=text,AutoSize=true,Height=30}; b.Click+=(_,_)=>action(); bar.Controls.Add(b); return b; }
        Add("Back",()=>{if(!Busy && View.CanGoBack) View.GoBack();});
        Add("Forward",()=>{if(!Busy && View.CanGoForward) View.GoForward();});
        bar.Controls.Add(Address);
        Add("Go",Go);
        Add("Reload",()=>{if(!Busy)View.Reload();});
        var import=Add("Import this page",()=>{});
        import.Click+=async(_,_)=>{if(Busy)return;try{Busy=true;var page=await SnapshotForImport();Busy=false;ImportRequested?.Invoke(page);}catch(Exception e){Busy=false;MessageBox.Show(this,e.Message,"Import page");}};
        preparePdf.Click+=async(_,_)=>await PreparePdf();bar.Controls.Add(preparePdf);
        Address.KeyDown+=(_,e)=>{if(e.KeyCode==Keys.Enter){Go();e.SuppressKeyPress=true;}};
    }
    void Go() { if(!Busy && Uri.TryCreate(Address.Text,UriKind.Absolute,out var u) && Sources.Web(u)) View.CoreWebView2?.Navigate(u.AbsoluteUri); }
    public async Task Initialize(string dataFolder)
    {
        var environment=await CoreWebView2Environment.CreateAsync(null,Path.Combine(dataFolder,"Browser"));
        await View.EnsureCoreWebView2Async(environment);
        View.CoreWebView2.SourceChanged+=(_,_)=>{Address.Text=View.Source?.AbsoluteUri??"";preparePdf.Visible=View.Source is Uri u && (Sources.Index(u) is 1 or 3 || u.Host=="pmc.ncbi.nlm.nih.gov");};
        View.CoreWebView2.NewWindowRequested+=(_,e)=>{e.Handled=true;if(!Busy && Uri.TryCreate(e.Uri,UriKind.Absolute,out var u) && Sources.Web(u)) View.CoreWebView2.Navigate(e.Uri);};
        View.CoreWebView2.NavigationStarting+=(_,e)=>{if(!Uri.TryCreate(e.Uri,UriKind.Absolute,out var u) || (!Sources.Web(u) && e.Uri!="about:blank")) e.Cancel=true;};
    }
    public void Navigate(Uri url) { if(View.CoreWebView2==null) throw new InvalidOperationException("The browser is not ready."); View.CoreWebView2.Navigate(url.AbsoluteUri); }
    public async Task<(string Html,Uri Url)> SnapshotPage()
    {
        return (JsonSerializer.Deserialize<string>(await View.ExecuteScriptAsync("document.documentElement.outerHTML"))??"",View.Source??throw new IOException("No browser page is open."));
    }
    public async Task<ImportPage> SnapshotForImport()
    {
        var json=await View.ExecuteScriptAsync(ImportSnapshotScript);
        using var data=JsonDocument.Parse(json);var root=data.RootElement;
        var current=new Uri(root.GetProperty("url").GetString()!);
        if(View.Source!=current)throw new IOException("The page changed while preparing the import. Try again once it finishes loading.");
        return BrowserImport.Prepare(root.GetProperty("html").GetString()??"",current,root.GetProperty("query").GetString()??"");
    }
    internal const string ImportSnapshotScript = """
    (()=>({url:location.href,html:document.documentElement.outerHTML,
      query:Array.from(document.querySelectorAll('input[type="search"],input[name="query"],input[name="q"],input[aria-label*="search" i]'))
        .filter(n=>n.getClientRects().length>0).map(n=>(n.value||'').trim()).find(Boolean)||''}))()
    """;
    async Task PreparePdf()
    {
        if(Busy)return;
        try{
            Busy=true;var page=await SnapshotPage();var target=BrowserImport.PdfPreparation(page.Html,page.Url);
            if(target==null){guidance.Text="Open a JSTOR article or a PubMed record with a PMC full-text link, then choose Prepare PDF downloads.";return;}
            if(target.Host=="pmc.ncbi.nlm.nih.gov" && !target.AbsolutePath.EndsWith(".pdf",StringComparison.OrdinalIgnoreCase)){
                var pmc=await LoadPage(target,CancellationToken.None);target=BrowserImport.PdfPreparation(pmc.Html,pmc.Url);
                if(target==null){guidance.Text="No PDF link is available here. Open the publisher's PDF manually if offered, then return to your search.";return;}
            }
            guidance.Text="Complete any verification or download terms in this browser yourself. Once the PDF is available, use Back to return to the search and import.";
            Navigate(target);
        }catch(Exception e){guidance.Text=e.Message;}
        finally{Busy=false;}
    }
    public async Task<ArticleCapture> ReadArticle(CancellationToken token)
    {
        ArticleCapture capture=new();string previous="";int stable=0;
        for(int i=0;i<12;i++) {
            token.ThrowIfCancellationRequested();
            var json=await View.ExecuteScriptAsync(ArticlePages.CaptureScript);capture=ArticlePages.Parse(json);
            if(capture.AccessBlocked)return capture;
            if(json==previous)stable++;else stable=0;
            if(capture.Blocks.Count>0 && stable>=2)return capture;
            previous=json;await Task.Delay(500,token);
        }
        return capture;
    }
    public async Task<(string Html,Uri Url)?> ExpandNytResults(string previousHtml,Uri url,CancellationToken token)
    {
        var before=NewYorkTimesParser.Results(previousHtml,url).Select(u=>u.AbsoluteUri).ToHashSet();
        var next=Parser.Next(previousHtml,url);
        if(next!=null && next!=url && NewYorkTimesParser.IsSearch(next))return await LoadPage(next,token);
        // Only activate explicit result-expansion controls; never consent or
        // subscription controls. Scroll supports lists that load on demand.
        await View.ExecuteScriptAsync(ExpandNytScript);
        for(int i=0;i<20;i++) {
            await Task.Delay(500,token);var snapshot=await SnapshotForImport();var current=(Html:snapshot.Html,Url:snapshot.Url);
            if(!NewYorkTimesParser.IsSearch(current.Url))throw new IOException("NYT left the article list. Open the Browser tab and check the page.");
            if(NewYorkTimesParser.Results(current.Html,current.Url).Any(u=>!before.Contains(u.AbsoluteUri)))return current;
        }
        return null;
    }
    internal const string ExpandNytScript = """
    (() => {
      const root = document.querySelector('main') || document;
      const button = Array.from(root.querySelectorAll('button')).find(b =>
        !b.disabled && b.getAttribute('aria-disabled') !== 'true' && b.getClientRects().length > 0 &&
        /^(show more|load more|show more articles|load more articles|show more results|load more results)$/i.test((b.innerText || b.textContent || '').trim()));
      if(button){button.click();return 'clicked';}
      window.scrollTo(0,document.documentElement.scrollHeight);return 'scrolled';
    })()
    """;
    // Run fetch inside the site's browser session. A separate HttpClient does not
    // preserve the browser's network/session context, even when cookies are copied.
    public async Task<byte[]> FetchPdf(Uri url,CancellationToken token)
    {
        var key="__sunbear_pdf_"+Guid.NewGuid().ToString("N");
        var keyJson=JsonSerializer.Serialize(key);
        using var deadline=CancellationTokenSource.CreateLinkedTokenSource(token);deadline.CancelAfter(TimeSpan.FromSeconds(120));
        try {
            await View.ExecuteScriptAsync(BuildPdfFetchScript(url,key));
            while(true) {
                await Task.Delay(200,deadline.Token);
                var json=await View.ExecuteScriptAsync($"window[{keyJson}] ? window[{keyJson}].result : ({{ok:false,error:'The browser page changed during the download.'}})");
                using var document=JsonDocument.Parse(json);
                if(document.RootElement.ValueKind==JsonValueKind.Null)continue;
                return DecodePdfFetchResult(document.RootElement);
            }
        } catch(OperationCanceledException) when(!token.IsCancellationRequested) {throw new IOException("The browser PDF request timed out. Open the PDF in the Browser tab and try again.");}
        finally {
            try {await View.ExecuteScriptAsync($"if(window[{keyJson}]){{window[{keyJson}].controller.abort();delete window[{keyJson}];}}");}catch { }
        }
    }
    internal static byte[] DecodePdfFetchResult(JsonElement result)
    {
        if(!result.TryGetProperty("ok",out var ok) || !ok.GetBoolean())throw new IOException(result.TryGetProperty("error",out var error)?error.GetString():"The browser PDF request failed.");
        return Convert.FromBase64String(result.GetProperty("data").GetString()!);
    }
    internal static string BuildPdfFetchScript(Uri url,string key) => PdfFetchScript.Replace("__KEY_JSON__",JsonSerializer.Serialize(key)).Replace("__URL_JSON__",JsonSerializer.Serialize(url.AbsoluteUri));
    internal const string PdfFetchScript = """
    (() => {
      const key = __KEY_JSON__;
      const state = {controller: new AbortController(), result: null};
      window[key] = state;
      (async () => {
        const response = await fetch(__URL_JSON__, {credentials:'include', cache:'no-store', signal:state.controller.signal});
        if (!response.ok) throw new Error('The source returned HTTP ' + response.status + '. Open the PDF in the Browser tab and check access.');
        const reader = response.body.getReader();
        const chunks = []; let length = 0;
        while (true) {
          const chunk = await reader.read(); if (chunk.done) break;
          length += chunk.value.length;
          if (length > 128 * 1024 * 1024) { await reader.cancel(); throw new Error('This PDF exceeds the 128 MB browser transfer limit. Download it manually in the Browser tab.'); }
          chunks.push(chunk.value);
        }
        const bytes = new Uint8Array(length); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
        if (length < 5 || String.fromCharCode(...bytes.subarray(0,5)) !== '%PDF-') {
          throw new Error('The source returned ' + (response.headers.get('content-type') || 'non-PDF content') + ' instead of a PDF. Open PDF in browser to check the page, then retry.');
        }
        let encoded = '';
        // Divisible by three so independently encoded pieces concatenate safely.
        for (let i=0; i<bytes.length; i+=49152) encoded += btoa(String.fromCharCode(...bytes.subarray(i,i+49152)));
        state.result = {ok:true, data:encoded};
      })().catch(error => { state.result = {ok:false, error:String(error.message || error)}; });
      return true;
    })()
    """;
    public async Task<(string Html,Uri Url)> LoadPage(Uri url,CancellationToken token)
    {
        var completion=new TaskCompletionSource<bool>();
        void Complete(object? sender,CoreWebView2NavigationCompletedEventArgs e) { if(e.IsSuccess) completion.TrySetResult(true); else completion.TrySetException(new IOException("Browser could not load the page: "+e.WebErrorStatus)); }
        View.CoreWebView2.NavigationCompleted+=Complete;
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(token); timeout.CancelAfter(TimeSpan.FromSeconds(60));
        using var registration=timeout.Token.Register(()=>completion.TrySetCanceled(timeout.Token));
        try {
            Navigate(url); await completion.Task;
            // Dynamic catalogs often populate records after navigation completes.
            string html=""; string last=""; int stable=0;
            for(int i=0;i<20;i++) {
                await Task.Delay(500,token);
                html=JsonSerializer.Deserialize<string>(await View.ExecuteScriptAsync("document.documentElement.outerHTML"))??"";
                if(html==last) stable++; else stable=0;
                var current=View.Source??url;
                bool useful=Sources.CanImport(current) && !NewYorkTimesParser.IsArticle(current) ? Parser.ResultLinks(html,current).Count>0 : Parser.Document(html,current).Title!="Untitled";
                if(i>=3 && stable>=2 && useful) break;
                last=html;
            }
            return (html,View.Source??url);
        } finally {View.CoreWebView2.NavigationCompleted-=Complete;}
    }
}

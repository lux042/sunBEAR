using System.Net;
using System.Net.Http;

namespace SunBear;
public sealed class Scraper(BrowserPane browser, Action<int,int>? progress=null, Func<CancellationToken,Task>? requestAccess=null)
{
    public async Task Run(Session session,bool pdfs,int pages,Action<string> status,Action save,CancellationToken token,bool saveArticlePages=true)
    {
        progress?.Invoke(0,0);
        var start=new Uri(session.SearchURL); var source=Sources.Index(start);
        var documents=new HashSet<Uri>(); var visited=new HashSet<Uri>(); Uri? page=start;
        if(source==5) {
            page=null;
            if(NewYorkTimesParser.IsArticle(start)){documents.Add(NewYorkTimesParser.Canonical(start));session.PagesScraped=1;save();}
            else {
                status("Reading NYT article list…");
                var loaded=browser.View.Source?.AbsoluteUri==start.AbsoluteUri?await browser.SnapshotPage():await browser.LoadPage(start,token);
                for(int batch=1;batch<=Math.Clamp(pages,1,10);batch++) {
                    token.ThrowIfCancellationRequested();
                    if(!NewYorkTimesParser.IsSearch(loaded.Url))throw new IOException("NYT redirected away from the article list. Open the Browser tab, sign in if needed, and retry.");
                    documents.UnionWith(NewYorkTimesParser.Results(loaded.Html,loaded.Url));session.PagesScraped=batch;save();
                    if(batch==Math.Clamp(pages,1,10))break;
                    status($"Loading NYT result batch {batch+1}…");
                    var expanded=await browser.ExpandNytResults(loaded.Html,loaded.Url,token);if(expanded==null)break;loaded=expanded.Value;
                }
            }
        }
        while(page!=null && visited.Count<Math.Clamp(pages,1,10) && visited.Add(page)) {
            token.ThrowIfCancellationRequested(); status($"Reading search page {visited.Count}…");
            var loaded=await browser.LoadPage(page,token);
            if(Sources.Index(loaded.Url)!=source || !Sources.CanImport(loaded.Url)) throw new IOException("The site redirected away from this search. Finish signing in inside sunBEAR, run your search, and try again.");
            var found=Parser.ResultLinks(loaded.Html,loaded.Url);
            documents.UnionWith(found); session.PagesScraped=visited.Count; save();
            page=Parser.Next(loaded.Html,loaded.Url);
        }
        if(documents.Count==0) throw new IOException("No records were found. Check the search in the browser, finish any sign-in or site verification, then retry. The site may also have changed its page layout.");
        var completed=0; var failed=0;var pageFailures=0;progress?.Invoke(0,documents.Count);
        foreach(var url in documents) {
            token.ThrowIfCancellationRequested(); status($"Importing {completed+1} of {documents.Count}…");
            var loaded=await browser.LoadPage(url,token);
            ArticleCapture? article=null;
            if(source==5 && saveArticlePages){article=await ReadWithAccess(url,token);loaded=await browser.SnapshotPage();}
            if(Sources.Index(loaded.Url)!=source) throw new IOException("A record redirected to another site. Finish sign-in in the browser and retry.");
            var record=Parser.Document(loaded.Html,url);
            if(record.Title=="Untitled" || record.Title.Contains("Access Denied",StringComparison.OrdinalIgnoreCase) || record.Title.Contains("Just a moment",StringComparison.OrdinalIgnoreCase)) throw new IOException("The source returned a sign-in, verification, or unreadable page instead of a record. Open the Browser tab to resolve it.");
            if(source==5 && System.Text.RegularExpressions.Regex.IsMatch(record.Title,@"^(The New York Times|TimesMachine|Log in|Sign in|Subscribe|Please enable|Verify you|Are you a robot)(?:$|\s*[-:|]|\s+to\b)",System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                throw new IOException("NYT returned a site, sign-in, or verification page rather than article metadata. Open the Browser tab to check access, then retry.");
            if(source==5 && saveArticlePages) {
                try{await ArticlePages.Save(record,session.FolderPath,article!,token);}
                catch(OperationCanceledException){throw;}
                catch(Exception e){record.PageError=e.Message;pageFailures++;}
            }
            if(source==3 && Parser.Pmc(loaded.Html,url) is Uri pmc) {
                try { var pmcPage=await browser.LoadPage(pmc,token); record.PdfURLs.AddRange(Parser.Pdfs(pmcPage.Html,pmcPage.Url).Where(x=>new Uri(x).Host=="pmc.ncbi.nlm.nih.gov")); record.PdfURLs=record.PdfURLs.Distinct().ToList(); }
                catch(OperationCanceledException) {throw;}
                catch(Exception e) {record.DownloadError="PMC discovery: "+e.Message;}
            }
            if(source==5 && pdfs && record.PdfURLs.Count==0 && NewYorkTimesParser.ArchiveArticle(loaded.Html,loaded.Url) is Uri archive && archive!=loaded.Url) {
                try {
                    var archived=await browser.LoadPage(archive,token);
                    if(NewYorkTimesParser.IsArticle(archived.Url))record.PdfURLs=NewYorkTimesParser.Pdfs(archived.Html,archived.Url);
                }catch(OperationCanceledException){throw;}
                catch(Exception e){record.DownloadError="TimesMachine PDF discovery: "+e.Message;}
            }
            session.Records.Add(record); save();
            if(pdfs) {
                foreach(var pdf in record.PdfURLs) {
                    token.ThrowIfCancellationRequested();
                    try {RememberDownload(record,pdf,await Download(new Uri(pdf),new Uri(record.RecordURL),session.FolderPath,token));}
                    catch(OperationCanceledException) {save();throw;}
                    catch(Exception e) {record.DownloadError+=(record.DownloadError.Length>0?"\n":"")+e.Message;failed++;}
                    save();
                }
            }
            completed++;progress?.Invoke(completed,documents.Count);
            await Task.Delay(500,token);
        }
        session.IsComplete=true; save();
        status($"Finished: {session.Records.Count} records from {session.PagesScraped} page(s)."+(failed>0?$" {failed} PDF download(s) need attention.":"")+(pageFailures>0?$" {pageFailures} article page(s) need attention; see record details.":""));
    }
    public async Task DownloadPages(IEnumerable<(Session Session,Record Record)> records,Action<string> status,Action save,CancellationToken token)
    {
        var targets=records.ToList();int done=0,saved=0,failed=0;progress?.Invoke(0,targets.Count);
        foreach(var (session,record) in targets) {
            token.ThrowIfCancellationRequested();status($"Downloading article page {done+1} of {targets.Count}…");
            try {
                var loaded=await browser.LoadPage(new Uri(record.RecordURL),token);
                
                await ArticlePages.Save(record,session.FolderPath,await ReadWithAccess(new Uri(record.RecordURL),token),token);saved++;save();
            }catch(OperationCanceledException){throw;}
            catch(Exception e){record.PageError=e.Message;failed++;save();}
            done++;progress?.Invoke(done,targets.Count);
            status($"Processed {done} of {targets.Count}: {saved} saved, {failed} need attention.");
            await Task.Delay(500,token);
        }
        status($"Article pages: {saved} HTML files saved, {failed} need attention. Existing records retained.");
    }
    async Task<ArticleCapture> ReadWithAccess(Uri article,CancellationToken token)
    {
        while(true) {
            token.ThrowIfCancellationRequested();
            var capture=await browser.ReadArticle(token);
            if(!capture.AccessBlocked && capture.Blocks.Count>0 && Uri.TryCreate(capture.Url,UriKind.Absolute,out var current) && NewYorkTimesParser.IsArticle(current))return capture;
            if(requestAccess==null)return capture;
            await requestAccess(token);
            await browser.LoadPage(article,token);
        }
    }
    async Task<string> Download(Uri url,Uri referer,string folder,CancellationToken token)
    {
        Exception? browserError=null;
        try {
            // Use the existing record/PMC origin when possible. Retry loads the
            // record first so same-origin fetch inherits the site's normal context.
            if(browser.View.Source==null || browser.View.Source.Host!=url.Host && browser.View.Source.Host!=referer.Host)
                await browser.LoadPage(referer,token);
            var bytes=await browser.FetchPdf(url,token);
            await using var browserInput=new MemoryStream(bytes,false);
            return await SavePdf(browserInput,url,folder,token);
        }catch(OperationCanceledException){throw;}
        catch(Exception e){browserError=e;}
        try {return await DownloadDirect(url,referer,folder,token);}
        catch(OperationCanceledException) when(token.IsCancellationRequested){throw;}
        catch(Exception e){throw new IOException("Browser download: "+browserError.Message+"\nDirect download: "+e.Message);}
    }
    async Task<string> DownloadDirect(Uri url,Uri referer,string folder,CancellationToken token)
    {
        var jar=new CookieContainer();
        foreach(var c in await browser.View.CoreWebView2.CookieManager.GetCookiesAsync("")) {
            try {jar.Add(new Cookie(c.Name,c.Value,c.Path,c.Domain){Secure=c.IsSecure,HttpOnly=c.IsHttpOnly});} catch(CookieException) { }
        }
        using var handler=new HttpClientHandler {CookieContainer=jar,AutomaticDecompression=DecompressionMethods.All};
        using var client=new HttpClient(handler){Timeout=TimeSpan.FromSeconds(120)};
        client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent",browser.View.CoreWebView2.Settings.UserAgent);
        client.DefaultRequestHeaders.Referrer=referer;
        using var response=await client.GetAsync(url,HttpCompletionOption.ResponseHeadersRead,token); response.EnsureSuccessStatusCode();
        await using var input=await response.Content.ReadAsStreamAsync(token);
        return await SavePdf(input,url,folder,token);
    }
    internal static void RememberDownload(Record record,string url,string path)
    {
        record.DownloadedPDFs[url]=path;
        if(!record.LocalPDFPaths.Contains(path))record.LocalPDFPaths.Add(path);
    }
    internal static bool AlreadySaved(Record record,string url)
    {
        if(record.DownloadedPDFs.TryGetValue(url,out var path))return File.Exists(path);
        // Backward compatibility with the first build's single-PDF records.
        return record.PdfURLs.Count==1 && record.LocalPDFPaths.Any(File.Exists);
    }
    public async Task Retry(IEnumerable<(Session Session,Record Record)> records,Action<string> status,Action save,CancellationToken token)
    {
        var targets=records.ToList();int completed=0,downloaded=0,failed=0;progress?.Invoke(0,targets.Count);
        foreach(var (session,record) in targets) {
            token.ThrowIfCancellationRequested();status($"Retrying PDFs for record {completed+1} of {targets.Count}…");
            var missing=record.PdfURLs.Where(u=>!AlreadySaved(record,u)).ToList();
            if(missing.Count==0){if(record.PdfURLs.Count>0){record.DownloadError="";save();}completed++;progress?.Invoke(completed,targets.Count);continue;}
            var errors=new List<string>();
            try {
                Directory.CreateDirectory(session.FolderPath);
                await browser.LoadPage(new Uri(record.RecordURL),token);
                foreach(var link in missing) {
                    token.ThrowIfCancellationRequested();
                    try{RememberDownload(record,link,await Download(new Uri(link),new Uri(record.RecordURL),session.FolderPath,token));downloaded++;save();}
                    catch(OperationCanceledException){throw;}
                    catch(Exception e){errors.Add(e.Message);failed++;}
                }
                record.DownloadError=string.Join("\n",errors);save();
            } catch(OperationCanceledException){save();throw;}
            catch(Exception e){record.DownloadError=e.Message;failed++;save();}
            completed++;progress?.Invoke(completed,targets.Count);
        }
        status($"PDF retry finished: {downloaded} saved, {failed} failed. Existing records were retained.");
    }
    internal static async Task<string> SavePdf(Stream input,Uri url,string folder,CancellationToken token)
    {
        var signature=new byte[5]; int got=0;
        while(got<5) {var n=await input.ReadAsync(signature.AsMemory(got),token);if(n==0)break;got+=n;}
        if(got!=5 || System.Text.Encoding.ASCII.GetString(signature)!="%PDF-") throw new IOException("The site returned a webpage instead of a PDF. Sign in or accept its download terms in sunBEAR's browser, then retry. URL: "+url);
        var name=Sources.SafeName(Uri.UnescapeDataString(url.Segments.Last()));
        if(!name.EndsWith(".pdf",StringComparison.OrdinalIgnoreCase)) name+=".pdf";
        var target=Sources.UniquePath(Path.Combine(folder,name));var partial=target+".partial";
        try {
            await using(var output=new FileStream(partial,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {await output.WriteAsync(signature,token);await input.CopyToAsync(output,token);}
            File.Move(partial,target); return target;
        } catch {if(File.Exists(partial)) File.Delete(partial);throw;}
    }
}

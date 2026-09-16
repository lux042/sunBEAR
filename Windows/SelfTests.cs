using System.Xml.Linq;
namespace SunBear;
public static class SelfTests
{
    public static int Run(string? reportPath)
    {
        var output=new List<string>();int failed=0;
        void Test(string name,Action action){try{action();output.Add("PASS "+name);}catch(Exception e){failed++;output.Add("FAIL "+name+": "+e);}}
        void Equal<T>(T expected,T actual){if(!Equals(expected,actual))throw new Exception($"Expected {expected}, got {actual}");}
        void True(bool value){if(!value)throw new Exception("Assertion failed");}
        Test("Rendered NYT search recovers query without changing visible context",()=>{
            var actual=new Uri("https://www.nytimes.com/search?sort=newest");var html="<main><a href='/2026/01/01/world/example.html'>Example</a></main>";
            var page=BrowserImport.Prepare(html,actual,"Ecuador & trade");Equal(actual,page.BrowserUrl);Equal("Ecuador & trade",Sources.Query(page.Url)["query"]);Equal("newest",Sources.Query(page.Url)["sort"]);Equal(html,page.Html);
            foreach(var candidate in new[]{("",html),("Ecuador","<main>No results</main>")}){bool rejected=false;try{BrowserImport.Prepare(candidate.Item2,actual,candidate.Item1);}catch(IOException){rejected=true;}True(rejected);}
            True(!BrowserImport.IsNytSearchPage(new("https://fakenytimes.com/search")));
        });
        Test("NYT games links excluded unless explicitly searched",()=>{
            var html="<main><a href='/2026/01/01/world/news.html'>News</a><a href='/2026/01/01/crosswords/puzzle.html'>Puzzle</a></main>";
            Equal(1,NewYorkTimesParser.Results(html,new("https://www.nytimes.com/search?query=Ecuador")).Count);
            Equal(2,NewYorkTimesParser.Results(html,new("https://www.nytimes.com/search?query=crosswords")).Count);
        });
        Test("PDF preparation restricts links to the selected publisher",()=>{
            Equal("https://www.jstor.org/stable/pdf/123.pdf",BrowserImport.PdfPreparation("<a href='https://evil.test/stable/444'>Bad</a><a href='/stable/123'>Article</a>",new("https://www.jstor.org/action/doBasicSearch?Query=test"))?.AbsoluteUri);
            Equal("https://pmc.ncbi.nlm.nih.gov/articles/PMC123/",BrowserImport.PdfPreparation("<a href='https://pmc.ncbi.nlm.nih.gov/articles/PMC123/'>Full text</a>",new("https://pubmed.ncbi.nlm.nih.gov/123/"))?.AbsoluteUri);
            True(BrowserImport.PdfPreparation("",new("https://example.com/stable/123"))==null);
        });
        Test("Session filter, sort, bulk move and collection removal preserve unrelated records",()=>{
            var c=new Collection{Name="Group"};var a=new Session{Name="Alpha",StartedAt=new DateTime(2020,1,1),Records=[new Record()]};var b=new Session{Name="Beta",StartedAt=new DateTime(2022,1,1),Records=[new Record(),new Record()]};var d=new Session{Name="Other"};var lib=new Library{Collections=[c],Sessions=[a,b,d]};
            Equal(a,LibraryActions.VisibleSessions(lib,"ALP",0).Single());Equal(a,LibraryActions.VisibleSessions(lib,"",1).First());Equal(a,LibraryActions.VisibleSessions(lib,"",2).First());Equal(b,LibraryActions.VisibleSessions(lib,"",3).First());
            LibraryActions.Move(new[]{a,b},c.Id);Equal(c.Id,a.CollectionId);True(d.CollectionId==null);
            LibraryActions.DeleteCollection(lib,c,false);Equal(3,lib.Sessions.Count);True(a.CollectionId==null);Equal(1,a.Records.Count);
            lib.Collections.Add(c);LibraryActions.Move(new[]{a,b},c.Id);LibraryActions.DeleteCollection(lib,c,true);Equal(d,lib.Sessions.Single());
        });
        Test("Supported search URLs and lookalike host rejection",()=>{
            True(Sources.CanImport(new("https://www.cia.gov/readingroom/advanced-search-view?keyword=test")));
            True(Sources.CanImport(new("https://www.jstor.org/action/doBasicSearch?Query=test")));
            True(Sources.CanImport(new("https://eric.ed.gov/?q=test")));
            True(Sources.CanImport(new("https://pubmed.ncbi.nlm.nih.gov/?term=test")));
            True(Sources.CanImport(new("https://catalog.archives.gov/search?q=test")));
            True(!Sources.CanImport(new("https://fakecia.gov/readingroom/search/site")));
            True(!Sources.CanImport(new("https://eric.ed.gov/?id=ED123&q=test")));
            True(!Sources.CanImport(new("file:///C:/search")));
        });
        Test("CIA links, deduplication and structured next page",()=>{
            var u=new Uri("https://www.cia.gov/readingroom/advanced-search-view?keyword=Germany");
            var h="<a href='/readingroom/document/test'>A</a><a href='/readingroom/document/test'>Duplicate</a><a href='/readingroom/document-view/123'>B</a><li class='pager__item--next'><a href='?keyword=Germany&amp;page=1'><span>Next</span></a></li>";
            Equal(2,Parser.ResultLinks(h,u).Count);Equal("https://www.cia.gov/readingroom/advanced-search-view?keyword=Germany&page=1",Parser.Next(h,u)?.AbsoluteUri);
        });
        Test("CIA classic metadata, field order, abstract and PDFs",()=>{
            var h="<h1>Library</h1><h2>Sample &amp; Record</h2><div>Document Type: CREST</div><div>Sequence Number: 9</div><div>Case Number:</div><div>Publication Date: September 21, 1962</div><div>Content Type: MF</div><div>Document Page Count: 12</div><div>File:</div><a href='/readingroom/docs/one.pdf'>PDF</a><a href='/readingroom/docs/two.PDF'>PDF</a><div>Body:</div><p>OCR abstract text.</p><a>Printer-friendly version</a>";
            var r=Parser.Document(h,new("https://www.cia.gov/readingroom/document/test"));
            Equal("Sample & Record",r.Title);Equal("",r.Field("Case Number"));Equal("September 21, 1962",r.Date);Equal("MF",r.Field("Content Type"));Equal("OCR abstract text.",r.Body);Equal(2,r.PdfURLs.Count);
        });
        Test("JSTOR custom elements and canonical links",()=>{
            var u=new Uri("https://www.jstor.org/action/doBasicSearch?Query=climate");var links=Parser.ResultLinks("<search-results-vue-pharos-link href='/stable/resrep16372?searchText=climate'>A</search-results-vue-pharos-link><a href='https://www.jstor.org/stable/10.2307/1234'>B</a>",u);
            Equal(2,links.Count);Equal("https://www.jstor.org/stable/resrep16372",links[0].AbsoluteUri);
        });
        Test("JSTOR metadata, encoded abstract and authenticated PDF URL",()=>{
            var r=Parser.Document("<meta content='Climate &amp; Society' name='citation_title'><meta name='citation_type' content='research report'><meta name='citation_publisher' content='Example Institute'><meta name='description' content='&lt;p&gt;An article abstract.&lt;/p&gt;'>",new("https://www.jstor.org/stable/resrep16372"));
            Equal("Climate & Society",r.Title);Equal("Example Institute",r.Collection);Equal("An article abstract.",r.Body);Equal("https://www.jstor.org/stable/pdf/resrep16372.pdf",r.PdfURLs.Single());Equal(("Report",27),Exports.Reference(r));
        });
        Test("ERIC links, page navigation, metadata and hosted PDFs",()=>{
            var u=new Uri("https://eric.ed.gov/?q=english");var h="<a href='?q=english&amp;id=EJ1458636'>A</a><a href='?id=ED636970&amp;q=english'>B</a><a href='?q=english&amp;pg=2'>Next Page</a>";
            Equal(2,Parser.ResultLinks(h,u).Count);Equal("https://eric.ed.gov/?q=english&pg=2",Parser.Next(h,u)?.AbsoluteUri);
            var r=Parser.Document("<meta name='citation_title' content='A Practitioner&apos;s Study.'><meta name='citation_abstract' content='A concise abstract.'><meta name='citation_pdf_url' content='http://files.eric.ed.gov/fulltext/EJ1458636.pdf'><div><strong>Record Type:</strong> Journal</div><div><strong>Pages:</strong> 11</div>",new("https://eric.ed.gov/?id=EJ1458636"));
            Equal("A Practitioner's Study",r.Title);Equal("11",r.Field("Document Page Count"));Equal("Journal",r.Field("Document Type"));Equal(1,r.PdfURLs.Count);Equal("EJ1458636",r.Number);
        });
        Test("PubMed metadata, PMC discovery and pagination",()=>{
            var u=new Uri("https://pubmed.ncbi.nlm.nih.gov/?term=education");var h="<a class='docsum-title' href='/31235301/'>A</a><button class='next-page-btn'>Next</button>";
            Equal(1,Parser.ResultLinks(h,u).Count);Equal("2",Sources.Query(Parser.Next(h,u)!)["page"]);True(Parser.Next("<button class='next-page-btn' disabled>Next</button>",u)==null);
            var detail="<meta name='citation_title' content='Medical education'><meta name='citation_date' content='01/15/2026'><meta name='citation_journal_title' content='Medical Journal'><div class='abstract-content selected'><p>A useful <b>medical</b> abstract.</p></div><a href='https://pmc.ncbi.nlm.nih.gov/articles/PMC12875206/'>PMC</a>";
            var r=Parser.Document(detail,new("https://pubmed.ncbi.nlm.nih.gov/41657923/"));Equal("41657923",r.Number);Equal("A useful medical abstract.",r.Body);True(Parser.Pmc(detail,u)!=null);Equal(("Journal Article",17),Exports.Reference(r));
        });
        Test("National Archives metadata and navigation",()=>{
            var u=new Uri("https://catalog.archives.gov/search?page=1&q=constitution");Equal(1,Parser.ResultLinks("<a href='/id/1667751'>A</a>",u).Count);Equal("2",Sources.Query(Parser.Next("<button aria-label='Go to page 2'>Next</button>",u)!)["page"]);
            var r=Parser.Document("<main><div>Item</div><h1>Constitution</h1><h2>Dates,</h2><p>September 17, 1787.</p><h2>Record Group 11</h2><div>General Records</div><h2>Scope and Content</h2><p>The signed parchment copy.</p><a href='https://catalog.archives.gov/media/00303.pdf'>PDF</a></main>",new("https://catalog.archives.gov/id/1667751"));
            Equal("Constitution",r.Title);Equal("1667751",r.Number);Equal("General Records",r.Collection);Equal("September 17, 1787.",r.Date);Equal("The signed parchment copy.",r.Body);Equal(1,r.PdfURLs.Count);
        });
        Test("NYT topic, search and historical URL validation",()=>{
            True(Sources.CanImport(new("https://www.nytimes.com/topic/destination/ecuador")));
            True(Sources.CanImport(new("https://www.nytimes.com/search?query=ecuador&startDate=19000101&endDate=19500101")));
            True(Sources.CanImport(new("https://www.nytimes.com/2026/01/01/world/americas/example.html")));
            True(Sources.CanImport(new("https://timesmachine.nytimes.com/timesmachine/1920/01/01/12345.html")));
            True(!Sources.CanImport(new("https://timesmachine.nytimes.com/timesmachine/1920/01/01/issue.html")));
            True(!Sources.CanImport(new("https://fakenytimes.com/topic/destination/ecuador")));
            True(!Sources.CanImport(new("https://myaccount.nytimes.com/auth/login")));
        });
        Test("NYT topic article links, tracking removal and navigation exclusion",()=>{
            var h="<nav><a href='/2026/01/01/world/nav.html'>Nav story</a></nav><main><a href='/2026/01/02/world/ecuador.html?smid=share'>First</a><a href='/2026/01/02/world/ecuador.html'>Duplicate</a><a href='/topic/destination/ecuador'>Topic</a><a href='https://timesmachine.nytimes.com/timesmachine/1920/01/01/12345.html'>Archive</a><a href='https://other.example/2026/01/01/story.html'>Other</a></main>";
            var links=Parser.ResultLinks(h,new("https://www.nytimes.com/topic/destination/ecuador"));Equal(2,links.Count);Equal("https://www.nytimes.com/2026/01/02/world/ecuador.html",links[0].AbsoluteUri);
            Equal("https://select.nytimes.com/gst/abstract.html?res=ABC123",NewYorkTimesParser.Canonical(new("https://select.nytimes.com/gst/abstract.html?res=ABC123&smid=tracking")).AbsoluteUri);
        });
        Test("NYT structured article metadata, individual authors and print pages",()=>{
            var h="""
            <script type="application/ld+json">{"@graph":[{"@type":"WebPage","name":"NYT"},{"@type":"NewsArticle","headline":"Synthetic Ecuador research fixture","description":"Synthetic description, not article text.","datePublished":"2026-01-02T10:00:00Z","author":[{"@type":"Person","name":"Alex Example"},{"@type":"Person","name":"Casey Sample"}],"articleSection":"World","pageStart":"3","pageEnd":"4"}]}</script>
            <link rel="canonical" href="https://www.nytimes.com/2026/01/02/world/ecuador.html">
            <meta name="articleid" content="1000000123456">
            """;
            var r=Parser.Document(h,new("https://www.nytimes.com/2026/01/02/world/ecuador.html?smid=test"));
            Equal("Synthetic Ecuador research fixture",r.Title);Equal(2,r.Authors.Count);Equal("Alex Example",r.Authors[0]);Equal("World",r.Section);Equal("3-4",r.PrintPages);Equal("1000000123456",r.Number);Equal("The New York Times",r.Collection);Equal("Synthetic description, not article text.",r.Body);Equal(0,r.PdfURLs.Count);
        });
        Test("NYT legacy metadata and archive date fallback",()=>{
            var r=Parser.Document("<meta property='og:title' content='Synthetic archive record - The New York Times'><meta name='byl' content='By Alex Example and Casey Sample'><meta name='pdate' content='19200101'><meta name='nyt_print_section' content='A'><meta name='nyt_print_page' content='7'>",new("https://timesmachine.nytimes.com/timesmachine/1920/01/01/12345.html"));
            Equal("Synthetic archive record",r.Title);Equal("1920-01-01",r.Date);Equal("12345",r.Number);Equal("A",r.Section);Equal("7",r.PrintPages);Equal(2,r.Authors.Count);
            var fallback=Parser.Document("<h1>Synthetic record</h1>",new("https://timesmachine.nytimes.com/timesmachine/1921/03/04/12346.html"));Equal("1921-03-04",fallback.Date);
        });
        Test("TimesMachine uses only provided PDF links and preserves referral parameters",()=>{
            var u=new Uri("https://timesmachine.nytimes.com/timesmachine/1920/01/01/12345.html");
            var h="<a href='/svc/tmach/v1/refer?pdf=true&amp;res=ABC123'>PDF</a><a href='/timesmachine/1920/01/01/12345.pdf'>Direct</a><a href='https://example.org/other.pdf'>Unrelated</a>";
            var pdfs=NewYorkTimesParser.Pdfs(h,u);Equal(2,pdfs.Count);Equal("https://timesmachine.nytimes.com/svc/tmach/v1/refer?pdf=true&res=ABC123",pdfs[0]);Equal(0,NewYorkTimesParser.Pdfs("<h1>Record without download link</h1>",u).Count);
        });
        Test("NYT newspaper EndNote mapping and extended TSV",()=>{
            var r=new Record{Source="New York Times",Title="Synthetic citation",Authors=["Alex Example","Casey Sample"],Section="A",PrintPages="3-4",Fields=new(){{"Collection","The New York Times"},{"Publication Date","1920-01-01"},{Parser.Identifier,"12345"}}};
            var e=Exports.Enw([r]);True(e.Contains("%0 Newspaper Article"));Equal(2,e.Split("%A ").Length-1);True(e.Contains("%D 1920"));True(e.Contains("%P 3-4"));True(e.Contains("%J The New York Times"));True(e.Contains("NYT Article ID: 12345"));
            var x=XDocument.Parse(Exports.Xml([r]));Equal("23",x.Descendants("ref-type").Single().Value);Equal(2,x.Descendants("author").Count());Equal("A",x.Descendants("section").Single().Value);Equal("1920",x.Descendants("year").Single().Value);
            var t=Exports.Tsv([r]).Split('\n');Equal(22,t[0].Split('\t').Length);Equal(22,t[1].Split('\t').Length);Equal("Alex Example; Casey Sample",t[1].Split('\t')[16]);
        });
        Test("Offline article HTML, text persistence and safe markup",()=>{
            var folder=Path.Combine(Path.GetDirectoryName(reportPath??Environment.ProcessPath!)!,"test-page-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
            try {
                var r=new Record{Source="New York Times",RecordURL="https://www.nytimes.com/2026/01/01/world/test.html",Title="Synthetic <title>",Authors=["Test Author"]};
                var capture=new ArticleCapture{Url=r.RecordURL,Blocks=[new ArticleBlock{Kind="h2",Text="Heading"},new ArticleBlock{Text="Text <script>alert(1)</script> & punctuation."}]};
                ArticlePages.Save(r,folder,capture,CancellationToken.None).GetAwaiter().GetResult();True(File.Exists(r.LocalPagePath));var h=File.ReadAllText(r.LocalPagePath);True(!h.Contains("<script>"));True(h.Contains("&lt;script&gt;"));True(h.Contains("<h2>Heading</h2>"));True(h.Contains("Content-Security-Policy"));True(r.FullText.Contains("punctuation"));Equal("HTML saved",r.PageStatus);
                var oldPath=r.LocalPagePath;ArticlePages.Save(r,folder,capture,CancellationToken.None).GetAwaiter().GetResult();Equal(oldPath,r.LocalPagePath);Equal(1,Directory.GetFiles(folder).Length);
                True(Exports.Enw([r]).Contains("%> "+r.LocalPagePath));True(XDocument.Parse(Exports.Xml([r])).Descendants("pdf-urls").Single().Value.EndsWith(".html"));
            }finally{Directory.Delete(folder,true);}
        });
        Test("Article capture rejects gates, empty text and different articles",()=>{
            var r=new Record{RecordURL="https://www.nytimes.com/2026/01/01/world/test.html",FullText="Previous saved article"};
            foreach(var capture in new[]{new ArticleCapture{Url=r.RecordURL,AccessBlocked=true},new ArticleCapture{Url=r.RecordURL},new ArticleCapture{Url="https://www.nytimes.com/2026/01/01/world/other.html",Blocks=[new ArticleBlock{Text="Other"}]}}){bool rejected=false;try{ArticlePages.Save(r,"unused",capture,CancellationToken.None).GetAwaiter().GetResult();}catch(IOException){rejected=true;}True(rejected);Equal("Previous saved article",r.FullText);}
        });
        var item=new Record{Title="A & B",RecordURL="https://www.cia.gov/readingroom/document/test",Body="Page one\fPage two\b done\nnext",PdfURLs=["https://www.cia.gov/file.pdf"],LocalPDFPaths=[Path.Combine(Path.GetTempPath(),"sunBEAR file.pdf")]};
        foreach(var label in Parser.Labels)item.Fields[label]=label=="Document Page Count"?"3":label+" value";
        Test("TSV preserves all 16 fields in original order",()=>{var lines=Exports.Tsv([item]).Split('\n');Equal(16,lines[0].Split('\t').Length);Equal(16,lines[1].Split('\t').Length);Equal("3",lines[1].Split('\t')[6]);Equal(item.Date,lines[1].Split('\t')[10]);Equal(item.RecordURL,lines[1].Split('\t')[13]);});
        Test("EndNote tagged fields and attachment",()=>{var e=Exports.Enw([item]);True(e.StartsWith("%0 CIA"));True(e.Contains("%P 3"));True(e.Contains("%Z Document Type:"));True(e.IndexOf("%U https://www.cia.gov/file.pdf")<e.IndexOf("%U "+item.RecordURL));True(e.Contains("%> "+item.LocalPDFPaths[0]));});
        Test("EndNote XML escaping, control removal and attachment URI",()=>{var x=XDocument.Parse(Exports.Xml([item]));Equal("40",x.Descendants("ref-type").Single().Value);Equal("A & B",x.Descendants("title").Single().Value);True(!x.ToString().Contains('\f'));True(!x.ToString().Contains('\b'));True(x.Descendants("pdf-urls").Single().Value.StartsWith("file:///"));});
        Test("Windows filenames",()=>{Equal("_CON",Sources.SafeName("CON"));True(!Sources.SafeName("a:b/c?d.").Contains(':'));True(!Sources.SafeName("name.").EndsWith('.'));});
        Test("Browser PDF response decoding and error reporting",()=>{
            using var good=System.Text.Json.JsonDocument.Parse("{\"ok\":true,\"data\":\"JVBERi0xLjQ=\"}");Equal("%PDF-1.4",System.Text.Encoding.ASCII.GetString(BrowserPane.DecodePdfFetchResult(good.RootElement)));
            using var bad=System.Text.Json.JsonDocument.Parse("{\"ok\":false,\"error\":\"HTML instead of PDF\"}");bool rejected=false;try{BrowserPane.DecodePdfFetchResult(bad.RootElement);}catch(IOException e){rejected=e.Message=="HTML instead of PDF";}True(rejected);
        });
        Test("PDF signature validation, collision handling and cancellation",()=>{
            var folder=Path.Combine(Path.GetDirectoryName(reportPath??Environment.ProcessPath!)!,"test-pdf-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
            try {
                var url=new Uri("https://example.com/document.pdf");
                using(var invalid=new MemoryStream(System.Text.Encoding.UTF8.GetBytes("<html>Sign in</html>"))){bool rejected=false;try{Scraper.SavePdf(invalid,url,folder,CancellationToken.None).GetAwaiter().GetResult();}catch(IOException){rejected=true;}True(rejected);Equal(0,Directory.GetFiles(folder).Length);}
                using(var one=new MemoryStream(System.Text.Encoding.ASCII.GetBytes("%PDF-1.4 test")))Scraper.SavePdf(one,url,folder,CancellationToken.None).GetAwaiter().GetResult();
                using(var two=new MemoryStream(System.Text.Encoding.ASCII.GetBytes("%PDF-1.4 different")))Scraper.SavePdf(two,url,folder,CancellationToken.None).GetAwaiter().GetResult();
                Equal(2,Directory.GetFiles(folder).Length);Equal("%PDF-1.4 test",File.ReadAllText(Path.Combine(folder,"document.pdf")));
                var record=new Record{PdfURLs=[url.AbsoluteUri]};var saved=Path.Combine(folder,"document.pdf");Scraper.RememberDownload(record,url.AbsoluteUri,saved);Scraper.RememberDownload(record,url.AbsoluteUri,saved);Equal(1,record.LocalPDFPaths.Count);True(Scraper.AlreadySaved(record,url.AbsoluteUri));record.DownloadedPDFs[url.AbsoluteUri]=Path.Combine(folder,"missing.pdf");True(!Scraper.AlreadySaved(record,url.AbsoluteUri));
                var legacy=new Record{PdfURLs=[url.AbsoluteUri],LocalPDFPaths=[saved]};True(Scraper.AlreadySaved(legacy,url.AbsoluteUri));
                using var canceled=new CancellationTokenSource();canceled.Cancel();using var three=new MemoryStream(System.Text.Encoding.ASCII.GetBytes("%PDF-1.4 canceled"));bool stopped=false;try{Scraper.SavePdf(three,url,folder,canceled.Token).GetAwaiter().GetResult();}catch(OperationCanceledException){stopped=true;}True(stopped);Equal(2,Directory.GetFiles(folder).Length);
            }finally{Directory.Delete(folder,true);}
        });
        Test("Library persistence, backup and corrupt-file protection",()=>{
            var path=Path.Combine(Path.GetDirectoryName(reportPath??Environment.ProcessPath!)!,"test-library-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(path);
            try{var store=new LibraryStore(path);var lib=new Library{Sessions=[new Session{Name="Test",Records=[item]}],Collections=[new Collection{Name="Research"}]};store.Save(lib);Equal("A & B",store.Load().Sessions[0].Records[0].Title);store.Save(lib);True(File.Exists(Path.Combine(path,"library.json.bak")));File.WriteAllText(Path.Combine(path,"library.json"),"broken");bool rejected=false;try{store.Load();}catch{rejected=true;}True(rejected);Equal("broken",File.ReadAllText(Path.Combine(path,"library.json")));}
            finally{Directory.Delete(path,true);}
        });
        output.Add($"{output.Count-failed} passed; {failed} failed.");
        if(reportPath!=null)File.WriteAllLines(reportPath,output);else Console.WriteLine(string.Join("\n",output));
        return failed==0?0:1;
    }
}

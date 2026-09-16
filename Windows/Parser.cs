using HtmlAgilityPack;
using HtmlDocument = HtmlAgilityPack.HtmlDocument;
using System.Net;
using System.Text.RegularExpressions;

namespace SunBear;

public static class Parser
{
    public const string Identifier = "Document Number (FOIA) /ESDN (CREST)";
    public static readonly string[] Labels = ["Document Type", "Collection", Identifier, "Release Decision", "Original Classification", "Document Page Count", "Document Creation Date", "Document Release Date", "Sequence Number", "Publication Date", "Content Type", "Case Number"];
    public static HtmlDocument Parse(string html) { var d=new HtmlDocument(); d.LoadHtml(html); return d; }
    public static string Text(string html)
    {
        html=WebUtility.HtmlDecode(html);
        html=Regex.Replace(html,@"<script\b.*?</script>|<style\b.*?</style>"," ",RegexOptions.Singleline|RegexOptions.IgnoreCase);
        html=Regex.Replace(html,@"<br\s*/?>|</(?:p|div|h[1-6]|li|tr)>","\n",RegexOptions.IgnoreCase);
        html=Regex.Replace(html,@"<[^>]+>"," ");
        return Regex.Replace(Regex.Replace(html,@"[ \t]+"," "),@"\n\s*\n+","\n").Trim();
    }
    static string Flat(string s) => Regex.Replace(Text(s),@"\s+"," ").Trim();
    static IEnumerable<HtmlNode> Nodes(HtmlDocument d,string xpath) => d.DocumentNode.SelectNodes(xpath)?.AsEnumerable() ?? [];
    static string Meta(HtmlDocument d, params string[] names) => names.Select(name => Nodes(d,"//meta").FirstOrDefault(n => n.GetAttributeValue("name",n.GetAttributeValue("property","" )).Equals(name,StringComparison.OrdinalIgnoreCase))?.GetAttributeValue("content","")).Select(s => WebUtility.HtmlDecode(s ?? "")).FirstOrDefault(s => s.Length>0) ?? "";
    static string First(params string[] values) => values.FirstOrDefault(s=>!string.IsNullOrWhiteSpace(s)) ?? "";
    static string Find(HtmlDocument d,string xpath) => Text(d.DocumentNode.SelectSingleNode(xpath)?.InnerHtml ?? "");
    public static List<Uri> Links(HtmlDocument d,Uri url) => Nodes(d,"//*[@href]").Select(n=>Resolve(url,n.GetAttributeValue("href",""))).OfType<Uri>().Distinct().ToList();
    static Uri? Resolve(Uri url,string value) => Uri.TryCreate(url,WebUtility.HtmlDecode(value),out var u) && Sources.Web(u) ? u : null;
    public static List<Uri> ResultLinks(string html,Uri url)
    {
        if(Sources.Index(url)==5)return NewYorkTimesParser.Results(html,url);
        var source=Sources.Index(url); var links=Links(Parse(html),url);
        return links.Where(u=>Sources.Index(u)==source).Select(u=> {
            var p=u.AbsolutePath;
            return source switch {
                0 when p.Contains("/readingroom/document/") || p.Contains("/readingroom/document-view/") => u,
                1 when p.StartsWith("/stable/") && !p.StartsWith("/stable/pdf/") => new UriBuilder(u){Query="",Fragment=""}.Uri,
                2 when Regex.IsMatch(Sources.Query(u).GetValueOrDefault("id",""),@"^E[JD]\d+$") => new Uri("https://eric.ed.gov/?id="+Sources.Query(u)["id"]),
                3 when Regex.IsMatch(p,@"^/\d+/$") => u,
                4 when Regex.IsMatch(p,@"^/id/\d+$") => new UriBuilder(u){Query="",Fragment=""}.Uri,
                _ => null
            };
        }).OfType<Uri>().Distinct().ToList();
    }
    public static Uri? Next(string html,Uri url)
    {
        var d=Parse(html);
        foreach(var n in Nodes(d,"//*[@href]")) {
            var hint=string.Join(" ",new[]{n.GetAttributeValue("rel",""),n.GetAttributeValue("aria-label",""),n.GetAttributeValue("title",""),n.GetAttributeValue("data-qa",""),n.ParentNode?.GetAttributeValue("class","") ?? "",Flat(n.InnerHtml)});
            if(Regex.IsMatch(hint,@"\bnext\b",RegexOptions.IgnoreCase)) {
                var u=Resolve(url,n.GetAttributeValue("href",""));
                if(u!=null && Sources.Index(u)==Sources.Index(url)) return u;
            }
        }
        int.TryParse(Sources.Query(url).GetValueOrDefault("page","1"),out var page); page=Math.Max(page,1);
        if(Sources.Index(url)==3 && Nodes(d,"//button").Any(n=>n.GetAttributeValue("class","").Contains("next-page-btn") && n.Attributes["disabled"]==null && n.GetAttributeValue("aria-disabled","")!="true")) return Sources.WithPage(url,page+1);
        if(Sources.Index(url)==4 && Nodes(d,"//*[@aria-label]").Any(n=>n.GetAttributeValue("aria-label","").Equals("Go to page "+(page+1),StringComparison.OrdinalIgnoreCase) && n.Attributes["disabled"]==null)) return Sources.WithPage(url,page+1);
        return null;
    }
    public static List<string> Pdfs(string html, Uri url)
    {
        var d=Parse(html);
        return Nodes(d,"//*[@href or @content]").Select(n=>Resolve(url,n.GetAttributeValue("href",n.GetAttributeValue("content","")))).OfType<Uri>().Where(u=>u.AbsolutePath.EndsWith(".pdf",StringComparison.OrdinalIgnoreCase)).Select(u=>u.AbsoluteUri).Distinct().ToList();
    }
    public static Uri? Pmc(string html,Uri url) => Links(Parse(html),url).FirstOrDefault(u=>u.Host=="pmc.ncbi.nlm.nih.gov" && Regex.IsMatch(u.AbsolutePath,@"^/articles/(PMC\d+|pmid/\d+)/?$"));
    public static Record Document(string html,Uri url)
    {
        if(Sources.Index(url)==5)return NewYorkTimesParser.Document(html,url);
        var d=Parse(html); var s=Sources.Index(url);
        var r=new Record {Source=s>=0?Sources.Names[s]:"CIA FOIA",RecordURL=url.AbsoluteUri};
        r.PdfURLs=Pdfs(html,url);
        string Label(string label) => Text(Nodes(d,"//strong").FirstOrDefault(n=>Text(n.InnerHtml).TrimEnd(':')==label)?.NextSibling?.InnerText ?? "");
        string H(string xpath)=>Find(d,xpath);
        r.Title=First(Meta(d,"citation_title","og:title"),H("//h1"),"Untitled");
        r.Fields["Collection"]=First(Meta(d,"citation_journal_title","citation_book_title","citation_publisher"),r.Source);
        r.Fields["Publication Date"]=Meta(d,"citation_publication_date","citation_date");
        r.Fields["Content Type"]=r.Source;
        r.Body=Flat(Meta(d,"citation_abstract","description","og:description"));
        switch(s) {
            case 0:
                var text=Text(html); var labelSet=string.Join("|",Labels.Select(Regex.Escape));
                foreach(var label in Labels) r.Fields[label]=Regex.Match(text,Regex.Escape(label)+@"\s*:\s*(.*?)\s*(?=(?:"+labelSet+@")\s*:|File\s*:|Body\s*:|$)",RegexOptions.Singleline|RegexOptions.IgnoreCase).Groups[1].Value.Trim();
                var start=text.IndexOf("Document Type:",StringComparison.OrdinalIgnoreCase);
                r.Title=start>=0?text[..start].Split('\n').Select(x=>x.Trim()).LastOrDefault(x=>x.Length>0)??"Untitled":First(Nodes(d,"//h1|//h2|//h3|//h4|//h5|//h6").Select(n=>Text(n.InnerHtml)).LastOrDefault(x=>!x.Equals("Library",StringComparison.OrdinalIgnoreCase))??"","Untitled");
                r.Body=Regex.Match(text,@"Body:\s*(.*?)(?:Printer-friendly version|$)",RegexOptions.Singleline|RegexOptions.IgnoreCase).Groups[1].Value.Trim();
                break;
            case 1:
                r.Title=Regex.Replace(r.Title,@"\s*\|\s*JSTOR\s*$","",RegexOptions.IgnoreCase).Trim();
                r.Fields[Identifier]=url.AbsolutePath.Split("/stable/").Last();
                r.Fields["Document Type"]=First(Meta(d,"citation_type"),Nodes(d,"//*[@data-itemtype]").FirstOrDefault()?.GetAttributeValue("data-itemtype","")??"","JSTOR Item");
                r.PdfURLs.Add(new Uri(url,"/stable/pdf/"+r.Number+".pdf").AbsoluteUri);
                break;
            case 2:
                r.Title=First(Meta(d,"citation_title"),H("//div[@class='title']"),r.Title).TrimEnd('.');
                r.Fields[Identifier]=First(Meta(d,"citation_technical_report_number"),Sources.Query(url).GetValueOrDefault("id",""),Label("ERIC Number"));
                r.Fields["Document Type"]=First(Label("Record Type"),"ERIC Record");
                r.Fields["Publication Date"]=First(r.Date,Label("Publication Date"));
                r.Fields["Document Page Count"]=Label("Pages");
                r.PdfURLs=r.PdfURLs.Where(x=>new Uri(x).Host=="files.eric.ed.gov").ToList();
                break;
            case 3:
                r.Fields[Identifier]=First(Meta(d,"citation_pmid"),url.Segments.FirstOrDefault(x=>Regex.IsMatch(x,@"^\d+/?$"))?.Trim('/')??"");
                r.Fields["Document Type"]=First(H("//span[contains(@class,'publication-type')]"),"PubMed Citation");
                r.Body=Flat(H("//div[contains(@class,'abstract-content') and contains(@class,'selected')]"));
                r.PdfURLs=r.PdfURLs.Where(x=>new Uri(x).Host=="pmc.ncbi.nlm.nih.gov").ToList();
                break;
            case 4:
                r.Fields[Identifier]=url.Segments.Last().Trim('/');
                r.Fields["Document Type"]=First(Nodes(d,"//div|//span").Select(n=>Text(n.InnerHtml)).FirstOrDefault(x=>new[]{"Item","File Unit","Series","Collection","Record Group"}.Contains(x))??"","National Archives Record");
                var group=Nodes(d,"//h2|//h3").FirstOrDefault(n=>Regex.IsMatch(Text(n.InnerHtml),@"^(Record Group|Collection)\b"));
                r.Fields["Collection"]=First(Text(group?.SelectSingleNode("following-sibling::*[1]")?.InnerHtml??""),"National Archives Catalog");
                var dates=Nodes(d,"//h2").FirstOrDefault(n=>Text(n.InnerHtml).StartsWith("Dates"));
                r.Fields["Publication Date"]=Text(dates?.SelectSingleNode("following-sibling::*[1]")?.InnerHtml??"");
                var body=Nodes(d,"//h2|//h3").FirstOrDefault(n=>Regex.IsMatch(Text(n.InnerHtml),@"^(Scope and Content|Description)"));
                r.Body=Text(body?.SelectSingleNode("following-sibling::*[1]")?.InnerHtml??"");
                r.PdfURLs=r.PdfURLs.Where(x=>new Uri(x).Host=="catalog.archives.gov").ToList();
                break;
        }
        r.PdfURLs=r.PdfURLs.Distinct().ToList();
        return r;
    }
}

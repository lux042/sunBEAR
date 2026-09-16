using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using HtmlAgilityPack;
using HtmlDocument=HtmlAgilityPack.HtmlDocument;

namespace SunBear;

public static class NewYorkTimesParser
{
    public static bool IsHost(Uri u)=>Sources.Web(u) && (u.Host.Equals("nytimes.com",StringComparison.OrdinalIgnoreCase) || u.Host.EndsWith(".nytimes.com",StringComparison.OrdinalIgnoreCase));
    public static bool IsArticle(Uri u)
    {
        if(!IsHost(u))return false;
        var p=u.AbsolutePath;
        if(u.Host.Equals("timesmachine.nytimes.com",StringComparison.OrdinalIgnoreCase))return Regex.IsMatch(p,@"^/timesmachine/\d{4}/\d{2}/\d{2}/\d+\.html$",RegexOptions.IgnoreCase);
        return Regex.IsMatch(p,@"^/(?:\d{4}/\d{2}/\d{2}/|(?:aponline|reuters)/\d{4}/\d{2}/\d{2}/).+\.html$",RegexOptions.IgnoreCase)
            || p.Equals("/gst/abstract.html",StringComparison.OrdinalIgnoreCase) && Sources.Query(u).ContainsKey("res");
    }
    public static bool IsSearch(Uri u)
    {
        if(!IsHost(u))return false;
        var q=Sources.Query(u);
        if(u.AbsolutePath.StartsWith("/topic/",StringComparison.OrdinalIgnoreCase))return true;
        return (u.AbsolutePath.TrimEnd('/')=="/search" || u.Host=="timesmachine.nytimes.com" && u.AbsolutePath.TrimEnd('/')=="/browser")
            && new[]{"query","q","search"}.Any(k=>q.GetValueOrDefault(k,"").Length>0);
    }
    public static Uri Canonical(Uri u)
    {
        // Legacy abstract URLs identify the article in `res`; do not strip it.
        var query=u.AbsolutePath=="/gst/abstract.html" && Sources.Query(u).TryGetValue("res",out var id)?"res="+Uri.EscapeDataString(id):"";
        return new UriBuilder(u){Fragment="",Query=query}.Uri;
    }
    static IEnumerable<HtmlNode> Nodes(HtmlNode n,string xpath)=>n.SelectNodes(xpath)?.AsEnumerable()??[];
    static string Flat(string html)=>Regex.Replace(Parser.Text(html),@"\s+"," ").Trim();
    static string Meta(HtmlDocument d,params string[] names)=>names.SelectMany(name=>Nodes(d.DocumentNode,"//meta").Where(n=>n.GetAttributeValue("name",n.GetAttributeValue("property","")).Equals(name,StringComparison.OrdinalIgnoreCase)).Select(n=>WebUtility.HtmlDecode(n.GetAttributeValue("content","")))).FirstOrDefault(x=>x.Length>0)??"";
    static string First(params string[] values)=>values.FirstOrDefault(x=>!string.IsNullOrWhiteSpace(x))??"";
    static Uri? Resolve(Uri u,string s)=>Uri.TryCreate(u,WebUtility.HtmlDecode(s),out var result) && Sources.Web(result)?result:null;
    public static List<Uri> Results(string html,Uri u)
    {
        var d=Parser.Parse(html);
        var root=d.DocumentNode.SelectSingleNode("//*[@data-testid='search-results']")??d.DocumentNode.SelectSingleNode("//main")??d.DocumentNode;
        return Nodes(root,".//a[@href]").Select(n=>Resolve(u,n.GetAttributeValue("href",""))).OfType<Uri>().Where(IsArticle).Select(Canonical).Distinct().ToList();
    }
    public static List<string> Pdfs(string html,Uri u)
    {
        var d=Parser.Parse(html);
        // Use publisher-provided download links only; do not invent archive URLs.
        return Nodes(d.DocumentNode,"//*[@href or @content]").Select(n=>Resolve(u,n.GetAttributeValue("href",n.GetAttributeValue("content","")))).OfType<Uri>()
            .Where(v=>IsHost(v) && (v.AbsolutePath.EndsWith(".pdf",StringComparison.OrdinalIgnoreCase)
                || v.Host=="timesmachine.nytimes.com" && v.AbsolutePath=="/svc/tmach/v1/refer" && Sources.Query(v).GetValueOrDefault("pdf","").Equals("true",StringComparison.OrdinalIgnoreCase)))
            .Select(v=>v.AbsoluteUri).Distinct().ToList();
    }
    public static Uri? ArchiveArticle(string html,Uri u)=>Parser.Links(Parser.Parse(html),u).FirstOrDefault(v=>v.Host=="timesmachine.nytimes.com" && IsArticle(v));
    static IEnumerable<JsonElement> JsonNodes(JsonElement element)
    {
        if(element.ValueKind==JsonValueKind.Array){foreach(var e in element.EnumerateArray())foreach(var n in JsonNodes(e))yield return n;}
        else if(element.ValueKind==JsonValueKind.Object){yield return element;if(element.TryGetProperty("@graph",out var graph))foreach(var n in JsonNodes(graph))yield return n;}
    }
    static string Value(JsonElement? element,string key)
    {
        if(element is not JsonElement e || !e.TryGetProperty(key,out var value))return "";
        return value.ValueKind is JsonValueKind.String or JsonValueKind.Number?value.ToString():"";
    }
    static bool ArticleJson(JsonElement e)
    {
        if(!e.TryGetProperty("@type",out var value))return false;
        var types=value.ValueKind==JsonValueKind.Array?value.EnumerateArray().Select(x=>x.ToString()):new[]{value.ToString()};
        return types.Any(t=>t is "NewsArticle" or "Article" or "ReportageNewsArticle" or "OpinionNewsArticle");
    }
    static IEnumerable<string> AuthorNames(JsonElement e)
    {
        if(e.ValueKind==JsonValueKind.Array){foreach(var a in e.EnumerateArray())foreach(var n in AuthorNames(a))yield return n;}
        else if(e.ValueKind==JsonValueKind.String)yield return e.GetString()!;
        else if(e.ValueKind==JsonValueKind.Object && e.TryGetProperty("name",out var n))yield return n.ToString();
    }
    public static Record Document(string html,Uri u)
    {
        var d=Parser.Parse(html);JsonElement? json=null;
        foreach(var script in Nodes(d.DocumentNode,"//script[@type='application/ld+json']")) {
            try {using var parsed=JsonDocument.Parse(script.InnerHtml);var article=JsonNodes(parsed.RootElement).FirstOrDefault(ArticleJson);if(article.ValueKind==JsonValueKind.Object){json=article.Clone();break;}}
            catch(JsonException){ }
        }
        var canonicalNode=d.DocumentNode.SelectSingleNode("//link[@rel='canonical']");
        var canonical=Resolve(u,canonicalNode?.GetAttributeValue("href","")??"");
        var r=new Record{Source="New York Times",RecordURL=Canonical(canonical!=null && IsArticle(canonical)?canonical:u).AbsoluteUri};
        r.Title=Regex.Replace(Flat(First(Value(json,"headline"),Meta(d,"citation_title","og:title","DC.title"),d.DocumentNode.SelectSingleNode("//h1")?.InnerHtml??"","Untitled")),@"\s*[-|–]\s*(?:The )?New York Times\s*$","",RegexOptions.IgnoreCase);
        r.Body=Flat(First(Value(json,"description"),Meta(d,"description","og:description","DC.description")));
        if(json is JsonElement articleJson && articleJson.TryGetProperty("author",out var author))r.Authors=AuthorNames(author).Select(Flat).Where(x=>x.Length>0).Distinct().ToList();
        if(r.Authors.Count==0)r.Authors=Nodes(d.DocumentNode,"//meta").Where(n=>new[]{"author","citation_author","byl","DC.creator"}.Contains(n.GetAttributeValue("name",""),StringComparer.OrdinalIgnoreCase))
            .SelectMany(n=>Regex.Split(Regex.Replace(WebUtility.HtmlDecode(n.GetAttributeValue("content","")),@"^By\s+","",RegexOptions.IgnoreCase),@"\s+and\s+|;\s*",RegexOptions.IgnoreCase)).Select(Flat).Where(x=>x.Length>0).Distinct().ToList();
        r.Fields["Document Type"]="Newspaper Article";r.Fields["Collection"]="The New York Times";
        r.Fields["Publication Date"]=First(Value(json,"datePublished"),Meta(d,"article:published_time","date","pdate","pubdate","citation_publication_date","DC.date"),d.DocumentNode.SelectSingleNode("//time[@datetime]")?.GetAttributeValue("datetime","")??"");
        if(Regex.IsMatch(r.Date,@"^\d{8}$"))r.Fields["Publication Date"]=r.Date[..4]+"-"+r.Date.Substring(4,2)+"-"+r.Date.Substring(6,2);
        if(r.Date.Length==0){var match=Regex.Match(u.AbsolutePath,@"/(\d{4})/(\d{2})/(\d{2})/");if(match.Success)r.Fields["Publication Date"]=$"{match.Groups[1]}-{match.Groups[2]}-{match.Groups[3]}";}
        r.Fields[Parser.Identifier]=First(Meta(d,"articleid","article_id","nyt_uri"),Value(json,"identifier"),Sources.Query(u).GetValueOrDefault("res",""),u.Host=="timesmachine.nytimes.com"?Path.GetFileNameWithoutExtension(u.AbsolutePath):"");
        r.Fields["Content Type"]=u.Host=="timesmachine.nytimes.com"?"TimesMachine archive":"NYT article";
        r.Section=First(Meta(d,"nyt_print_section","print_section"),Value(json,"articleSection"),Meta(d,"article:section","CG"));
        var firstPage=First(Value(json,"pageStart"),Meta(d,"citation_firstpage","nyt_print_page","print_page"));var lastPage=First(Value(json,"pageEnd"),Meta(d,"citation_lastpage"));
        r.PrintPages=firstPage+(lastPage.Length>0 && lastPage!=firstPage?"-"+lastPage:"");
        var print=Regex.Match(Parser.Text(html),@"Section\s+([A-Z0-9]+),?\s+Page\s+(\d+(?:[-–]\d+)?)",RegexOptions.IgnoreCase);
        if(print.Success){if(r.PrintPages.Length==0)r.PrintPages=print.Groups[2].Value;if(r.Section.Length==0)r.Section=print.Groups[1].Value;}
        r.PdfURLs=Pdfs(html,u);
        return r;
    }
}

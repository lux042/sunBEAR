namespace SunBear;
public static class LibraryActions
{
    public static IEnumerable<Session> VisibleSessions(Library library,string filter,int sort)
    {
        var sessions=library.Sessions.Where(s=>s.Name.Contains(filter.Trim(),StringComparison.CurrentCultureIgnoreCase));
        return sort switch {1=>sessions.OrderBy(s=>s.StartedAt),2=>sessions.OrderBy(s=>s.Name,StringComparer.CurrentCultureIgnoreCase),3=>sessions.OrderByDescending(s=>s.Records.Count).ThenByDescending(s=>s.StartedAt),_=>sessions.OrderByDescending(s=>s.StartedAt)};
    }
    public static void Move(IEnumerable<Session> sessions,string? collectionId){foreach(var s in sessions)s.CollectionId=collectionId;}
    public static void DeleteSessions(Library library,IEnumerable<Session> sessions){var ids=sessions.Select(s=>s.Id).ToHashSet();library.Sessions.RemoveAll(s=>ids.Contains(s.Id));}
    public static void DeleteCollection(Library library,Collection collection,bool contents){
        var sessions=library.Sessions.Where(s=>s.CollectionId==collection.Id).ToList();
        if(contents)DeleteSessions(library,sessions);else Move(sessions,null);
        library.Collections.Remove(collection);
    }
}
public sealed record ImportPage(string Html,Uri Url,Uri BrowserUrl);
public static class BrowserImport
{
    public static bool IsNytSearchPage(Uri url)=>NewYorkTimesParser.IsHost(url) && url.AbsolutePath.TrimEnd('/').Equals("/search",StringComparison.OrdinalIgnoreCase);
    public static ImportPage Prepare(string html,Uri url,string query)
    {
        var importUrl=url;
        if(IsNytSearchPage(url) && !NewYorkTimesParser.IsSearch(url)){
            if(string.IsNullOrWhiteSpace(query))throw new IOException("Enter a search term and wait for NYT results before importing.");
            var existing=url.Query.TrimStart('?');
            importUrl=new UriBuilder(url){Query=(existing.Length>0?existing+"&":"")+"query="+Uri.EscapeDataString(query.Trim())}.Uri;
            if(NewYorkTimesParser.Results(html,importUrl).Count==0)throw new IOException("No NYT article results are visible yet. Run the search and wait for results, then import.");
        }
        if(!Sources.CanImport(importUrl))throw new IOException("Open a supported search-results page or NYT article before importing.");
        return new(html,importUrl,url);
    }
    public static Uri? PdfPreparation(string html,Uri url)
    {
        if(Sources.Index(url)==1){
            var links=new[]{url}.Concat(Parser.Links(Parser.Parse(html),url));
            foreach(var link in links.Where(u=>Sources.Index(u)==1)){
                var match=System.Text.RegularExpressions.Regex.Match(link.AbsolutePath,@"^/stable/(?!pdf/)([^/]+)$");
                if(match.Success)return new Uri("https://www.jstor.org/stable/pdf/"+match.Groups[1].Value+".pdf");
            }
        }
        if(url.Host=="pmc.ncbi.nlm.nih.gov")return Parser.Pdfs(html,url).Select(s=>new Uri(s)).FirstOrDefault(u=>u.Host==url.Host);
        if(Sources.Index(url)==3)return Parser.Pmc(html,url);
        return null;
    }
}

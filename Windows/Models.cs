using System.Text.Json;

namespace SunBear;

public sealed class Record
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = "Untitled";
    public string Source { get; set; } = "CIA FOIA";
    public string RecordURL { get; set; } = "";
    public Dictionary<string,string> Fields { get; set; } = new();
    public string Body { get; set; } = "";
    public List<string> Authors { get; set; } = new();
    public string Section { get; set; } = "";
    public string PrintPages { get; set; } = "";
    public string FullText { get; set; } = "";
    public string LocalPagePath { get; set; } = "";
    public DateTimeOffset? PageSavedAt { get; set; }
    public string PageError { get; set; } = "";
    public string PageStatus => PageError.Length>0?"Needs attention":LocalPagePath.Length>0?"HTML saved":"Not saved";
    public List<string> PdfURLs { get; set; } = new();
    public List<string> LocalPDFPaths { get; set; } = new();
    public Dictionary<string,string> DownloadedPDFs { get; set; } = new();
    public string DownloadError { get; set; } = "";
    public string Field(string name) => Fields.GetValueOrDefault(name, "");
    public string Collection => Field("Collection");
    public string Number => Field(Parser.Identifier);
    public string Date => Field("Publication Date");
    public string PdfStatus => DownloadError.Length > 0 ? "Needs attention" : LocalPDFPaths.Count > 0 ? $"{LocalPDFPaths.Count} saved" : PdfURLs.Count > 0 ? "Available" : Source=="New York Times"?"No PDF link":"None found";
}
public sealed class Session
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "";
    public string SearchURL { get; set; } = "";
    public string FolderPath { get; set; } = "";
    public string? CollectionId { get; set; }
    public DateTime StartedAt { get; set; } = DateTime.Now;
    public int PagesScraped { get; set; }
    public bool IsComplete { get; set; }
    public List<Record> Records { get; set; } = new();
}
public sealed class Collection
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "";
}
public sealed class Library
{
    public List<Collection> Collections { get; set; } = new();
    public List<Session> Sessions { get; set; } = new();
    public string DownloadFolder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "sunBEAR Downloads");
}
public sealed class LibraryStore
{
    public string Root { get; }
    public LibraryStore(string root) { Root = root; Directory.CreateDirectory(root); }
    public Library Load()
    {
        var path = Path.Combine(Root, "library.json");
        if (!File.Exists(path)) return new();
        // A malformed library must never silently become an empty, overwritten library.
        return JsonSerializer.Deserialize<Library>(File.ReadAllText(path)) ?? throw new InvalidDataException("The library is empty or damaged. Restore library.json.bak from the data folder.");
    }
    public void Save(Library library)
    {
        var path = Path.Combine(Root, "library.json");
        var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(library, new JsonSerializerOptions { WriteIndented = true }));
        if (File.Exists(path)) File.Copy(path, path + ".bak", true);
        File.Move(temp, path, true);
    }
}
public static class Sources
{
    public static readonly string[] Names = ["CIA FOIA", "JSTOR", "ERIC", "PubMed", "National Archives", "New York Times"];
    public static readonly string[] Hosts = ["cia.gov", "jstor.org", "eric.ed.gov", "pubmed.ncbi.nlm.nih.gov", "catalog.archives.gov", "nytimes.com"];
    public static readonly string[] Homes = ["https://www.cia.gov/readingroom/advanced-search-view", "https://www.jstor.org/", "https://eric.ed.gov/", "https://pubmed.ncbi.nlm.nih.gov/", "https://catalog.archives.gov/", "https://www.nytimes.com/search"];
    public static int Index(Uri url) => Array.FindIndex(Hosts, h => url.Host.Equals(h, StringComparison.OrdinalIgnoreCase) || url.Host.EndsWith("." + h, StringComparison.OrdinalIgnoreCase));
    public static bool Web(Uri u) => u.Scheme is "https" or "http";
    public static bool CanImport(Uri u)
    {
        if (!Web(u)) return false;
        var q = Query(u);
        return Index(u) switch {
            0 => u.AbsolutePath.Contains("search", StringComparison.OrdinalIgnoreCase),
            1 => u.AbsolutePath is "/action/doBasicSearch" or "/action/doAdvancedSearch",
            2 => q.ContainsKey("q") && !q.ContainsKey("id"),
            3 => q.ContainsKey("term"),
            4 => u.AbsolutePath == "/search" && q.GetValueOrDefault("q", "").Length > 0,
            5 => NewYorkTimesParser.IsSearch(u) || NewYorkTimesParser.IsArticle(u),
            _ => false
        };
    }
    public static Dictionary<string,string> Query(Uri url) => url.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries).Select(x => x.Split('=',2)).GroupBy(x => Uri.UnescapeDataString(x[0]), StringComparer.OrdinalIgnoreCase).ToDictionary(g => g.Key,g => System.Net.WebUtility.UrlDecode(g.Last().Length > 1 ? g.Last()[1] : ""),StringComparer.OrdinalIgnoreCase);
    public static Uri WithPage(Uri url, int page)
    {
        var q = Query(url); q["page"] = page.ToString();
        return new UriBuilder(url) { Query = string.Join("&", q.Select(kv => Uri.EscapeDataString(kv.Key) + "=" + Uri.EscapeDataString(kv.Value))) }.Uri;
    }
    public static string SafeName(string s)
    {
        var value = string.Concat(s.Select(c => Path.GetInvalidFileNameChars().Contains(c) || char.IsControl(c) ? '-' : c)).Trim().TrimEnd('.');
        if (value.Length > 120) value = value[..120];
        if (value.Length == 0) value = "document";
        if (System.Text.RegularExpressions.Regex.IsMatch(value.Split('.')[0], @"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) value = "_" + value;
        return value;
    }
    public static string UniquePath(string path)
    {
        var n=2; var p=path;
        while(File.Exists(p) || Directory.Exists(p)) p=Path.Combine(Path.GetDirectoryName(path)!, Path.GetFileNameWithoutExtension(path)+"-"+(n++)+Path.GetExtension(path));
        return p;
    }
}

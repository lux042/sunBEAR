using System.Text;
using System.Xml.Linq;

namespace SunBear;
public static class Exports
{
    public static readonly string[] Headers = ["Title","Notes","Notes","Notes","Notes","Notes","Pages","Notes","Notes","Notes","Date","Notes","Notes","URL","URL","Abstract"];
    public static string Clean(string value) => value.Replace('\t',' ').Replace('\r',' ').Replace('\n',' ').Trim();
    public static string IdentifierLabel(Record r) => r.Source switch {"JSTOR"=>"JSTOR Stable ID","ERIC"=>"ERIC Number","PubMed"=>"PMID","National Archives"=>"National Archives Identifier (NAID)","New York Times"=>"NYT Article ID",_=>"Document Number (FOIA) / ESDN (CREST)"};
    public static string Notes(Record r) => string.Join(" | ",Parser.Labels.Where(l=>l is not "Document Page Count" and not "Publication Date" && r.Field(l).Length>0).Select(l=>(l==Parser.Identifier?IdentifierLabel(r):l)+": "+Clean(r.Field(l))).Concat(r.Section.Length>0?new[]{"Section: "+Clean(r.Section)}:Array.Empty<string>()));
    public static (string Name,int Number) Reference(Record r)
    {
        var type=r.Field("Document Type").ToLowerInvariant();
        return r.Source switch {
            "CIA FOIA" => ("CIA",40),
            "PubMed" => ("Journal Article",17),
            "New York Times" => ("Newspaper Article",23),
            "JSTOR" => type.Contains("book") ? ("Book",6) : type.Contains("report") ? ("Report",27) : ("Journal Article",17),
            "ERIC" => type.Contains("journal") ? ("Journal Article",17) : type.Contains("report") ? ("Report",27) : type.Contains("book") ? ("Book",6) : ("Generic",13),
            _ => ("Generic",13)
        };
    }
    public static string Tsv(IEnumerable<Record> records)
    {
        var rows=records.ToList();bool news=rows.Any(r=>r.Source=="New York Times");
        var headers=news?Headers.Concat(new[]{"Author","Section","Print Pages","Article Text","Saved Page","Page Status"}):Headers.AsEnumerable();
        return string.Join("\n",new[]{string.Join("\t",headers)}.Concat(rows.Select(r=>string.Join("\t",new[]{r.Title}.Concat(Parser.Labels.Select(r.Field)).Concat(new[]{r.RecordURL,string.Join(" ",r.PdfURLs),r.Body}).Concat(news?new[]{string.Join("; ",r.Authors),r.Section,r.PrintPages,r.FullText,r.LocalPagePath,r.PageStatus}:Array.Empty<string>()).Select(Clean)))))+"\n";
    }
    public static string Enw(IEnumerable<Record> records)
    {
        var output=new StringBuilder();
        foreach(var r in records) {
            void Add(string tag,string value) { if(!string.IsNullOrWhiteSpace(value)) output.AppendLine(tag+" "+Clean(value)); }
            Add("%0",Reference(r).Name); Add("%T",r.Title);
            foreach(var author in r.Authors)Add("%A",author);
            if(r.Source!="CIA FOIA") Add("%J",r.Collection);
            Add("%Z",Notes(r)); Add("%P",r.PrintPages.Length>0?r.PrintPages:r.Field("Document Page Count")); Add("%8",r.Date);
            if(r.Source=="New York Times") {var year=System.Text.RegularExpressions.Regex.Match(r.Date,@"\b(?:18|19|20)\d{2}\b").Value;Add("%D",year);}
            foreach(var p in r.PdfURLs) Add("%U",p);
            Add("%U",r.RecordURL); Add("%X",r.Body);
            foreach(var p in r.LocalPDFPaths) Add("%>",p);
            if(r.LocalPagePath.Length>0)Add("%>",r.LocalPagePath);
            output.AppendLine();
        }
        return output.ToString();
    }
    static string XmlText(string s) => string.Concat(s.EnumerateRunes().Where(r=>r.Value is 9 or 10 or 13 || (r.Value>=32 && r.Value<=0xD7FF) || (r.Value>=0xE000 && r.Value<=0xFFFD) || (r.Value>=0x10000 && r.Value<=0x10FFFF)).Select(r=>r.ToString()));
    public static string Xml(IEnumerable<Record> records)
    {
        XElement Style(string s)=>new("style",new XAttribute("face","normal"),new XAttribute("font","default"),new XAttribute("size","100%"),XmlText(s));
        XElement Field(string name,string value)=>new(name,Style(value));
        var result=new XElement("records");
        foreach(var r in records) {
            var reference=Reference(r);
            var titles=new XElement("titles",Field("title",r.Title));
            if(r.Collection.Length>0) titles.Add(Field("secondary-title",r.Collection));
            var record=new XElement("record",new XElement("ref-type",new XAttribute("name",reference.Name),reference.Number),titles);
            if(r.Authors.Count>0)record.Add(new XElement("contributors",new XElement("authors",r.Authors.Select(a=>Field("author",a)))));
            var pages=r.PrintPages.Length>0?r.PrintPages:r.Field("Document Page Count");if(pages.Length>0)record.Add(Field("pages",pages));
            if(r.Section.Length>0)record.Add(Field("section",r.Section));
            if(r.Date.Length>0){var dates=new XElement("dates",new XElement("pub-dates",Field("date",r.Date)));if(r.Source=="New York Times"){var year=System.Text.RegularExpressions.Regex.Match(r.Date,@"\b(?:18|19|20)\d{2}\b").Value;if(year.Length>0)dates.Add(Field("year",year));}record.Add(dates);}
            if(r.Body.Length>0) record.Add(Field("abstract",r.Body));
            if(Notes(r).Length>0) record.Add(Field("notes",Notes(r)));
            record.Add(new XElement("urls",new XElement("related-urls",r.PdfURLs.Append(r.RecordURL).Where(x=>x.Length>0).Select(u=>Field("url",u))),new XElement("pdf-urls",r.LocalPDFPaths.Concat(r.LocalPagePath.Length>0?new[]{r.LocalPagePath}:Array.Empty<string>()).Select(p=>new XElement("url",new Uri(Path.GetFullPath(p)).AbsoluteUri)))));
            result.Add(record);
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"+new XElement("xml",result);
    }
}

using System.Net;
using System.Text;
using System.Text.Json;

namespace SunBear;
public sealed class ArticleBlock
{
    public string Kind { get; set; } = "p";
    public string Text { get; set; } = "";
}
public sealed class ArticleCapture
{
    public string Url { get; set; } = "";
    public bool AccessBlocked { get; set; }
    public string Message { get; set; } = "";
    public List<ArticleBlock> Blocks { get; set; } = new();
}
public static class ArticlePages
{
    public static ArticleCapture Parse(string json)=>JsonSerializer.Deserialize<ArticleCapture>(json,new JsonSerializerOptions{PropertyNameCaseInsensitive=true})??throw new IOException("The article page returned no text.");
    public static async Task Save(Record record,string folder,ArticleCapture capture,CancellationToken token)
    {
        if(capture.AccessBlocked)throw new IOException(capture.Message.Length>0?capture.Message:"The article requires access in the Browser tab. No article page was saved.");
        if(!Uri.TryCreate(capture.Url,UriKind.Absolute,out var current) || !NewYorkTimesParser.IsArticle(current))throw new IOException("The browser is not displaying an NYT article. No article page was saved.");
        if(!Uri.TryCreate(record.RecordURL,UriKind.Absolute,out var expected) || NewYorkTimesParser.Canonical(current)!=NewYorkTimesParser.Canonical(expected))throw new IOException("The browser moved to a different article. No article page was saved.");
        var blocks=capture.Blocks.Where(b=>!string.IsNullOrWhiteSpace(b.Text)).ToList();
        if(blocks.Count==0)throw new IOException("No readable article body was found. Open the article in sunBEAR and check access. A scanned TimesMachine page may provide a PDF instead of text.");
        token.ThrowIfCancellationRequested();Directory.CreateDirectory(folder);
        var name=Sources.SafeName(record.Title)+"-"+record.Id[..8]+".html";
        var target=Path.Combine(folder,name);var temp=target+".partial";
        var captured=DateTimeOffset.Now;
        try {
            await File.WriteAllTextAsync(temp,Html(record,blocks,captured),new UTF8Encoding(false),token);
            token.ThrowIfCancellationRequested();File.Move(temp,target,true);
        }catch{if(File.Exists(temp))File.Delete(temp);throw;}
        record.FullText=string.Join("\n\n",blocks.Select(b=>b.Text.Trim()));record.LocalPagePath=target;record.PageSavedAt=captured;record.PageError="";
    }
    public static string Html(Record record,IEnumerable<ArticleBlock> blocks,DateTimeOffset captured)
    {
        static string E(string s)=>WebUtility.HtmlEncode(s);
        var output=new StringBuilder("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\"><title>");
        output.Append(E(record.Title)).Append("</title><style>body{max-width:760px;margin:48px auto;padding:0 24px;color:#222;background:#fffdf7;font:20px/1.7 Georgia,serif}h1{font-size:38px;line-height:1.2}h2,h3{line-height:1.3}header,footer{border-bottom:1px solid #ccc;padding-bottom:20px}header p,footer{font:14px/1.6 system-ui,sans-serif;color:#555}blockquote{border-left:3px solid #aaa;padding-left:20px}a{color:#245c40}.note{padding:12px;background:#f0eee4}</style></head><body><header><h1>").Append(E(record.Title)).Append("</h1><p>");
        output.Append(E(string.Join("; ",record.Authors))).Append("<br>").Append(E(record.Collection)).Append(" · ").Append(E(record.Date)).Append("</p><p><a href=\"").Append(E(record.RecordURL)).Append("\">Original article</a></p></header><main>");
        foreach(var block in blocks){var tag=block.Kind is "h2" or "h3" or "blockquote"?block.Kind:"p";output.Append('<').Append(tag).Append('>').Append(E(block.Text)).Append("</").Append(tag).Append('>');}
        output.Append("</main><footer><p>Saved by sunBEAR on ").Append(E(captured.ToString("yyyy-MM-dd HH:mm zzz"))).Append(".</p><p>Readable text from the article displayed in your browser session. Original images, interactive elements, and site layout are not included. Completeness depends on what the site made available at capture time.</p></footer></body></html>");
        return output.ToString();
    }
    // Read only rendered article elements. Never inspect hidden JSON/articleBody
    // data, remove a gateway, or change page styles to reveal inaccessible text.
    internal const string CaptureScript = """
    (() => {
      const visible = element => {
        for(let node=element;node && node.nodeType===1;node=node.parentElement){
          const style=getComputedStyle(node);
          if(node.hidden || node.getAttribute('aria-hidden')==='true' || style.display==='none' || style.visibility==='hidden' || style.visibility==='collapse' || Number(style.opacity)===0)return false;
          if((style.overflowY==='hidden' || style.overflowY==='clip') && node.scrollHeight>node.clientHeight+1)return false;
        }
        return element.getClientRects().length>0;
      };
      const gates=Array.from(document.querySelectorAll('#gateway-content,[data-testid="gateway-content"],[data-testid="paywall"],[data-testid="inline-message"],[role="dialog"]'));
      const blocked=gates.some(g=>visible(g) && /subscribe|subscription|log in|sign in|continue reading|verify|captcha/i.test(g.innerText||''));
      if(blocked)return {url:location.href,accessBlocked:true,message:'An access or sign-in prompt is visible. Finish that step in the Browser tab, then download the page again.',blocks:[]};
      const roots=Array.from(document.querySelectorAll('section[name="articleBody"],[data-testid="article-body"],[itemprop="articleBody"]'));
      const nodes=new Set();const blocks=[];
      for(const root of roots){
        if(!visible(root))continue;
        for(const node of root.querySelectorAll('p,h2,h3,blockquote,li')){
          if(nodes.has(node) || !visible(node) || node.closest('aside,nav,figure,footer,[data-testid="recirculation"],[data-testid="newsletter-signup"]'))continue;
          if(node.tagName==='BLOCKQUOTE' && node.querySelector('p'))continue;
          nodes.add(node);
          const text=(node.innerText||'').trim();
          if(text)blocks.push({kind:node.tagName.toLowerCase(),text});
        }
      }
      if(blocks.length===0){
        for(const node of document.querySelectorAll('[data-testid="paragraph"],[data-testid="story-body"],[data-testid="article-body"]')){
          if(!/^(P|H2|H3|BLOCKQUOTE)$/.test(node.tagName) || !visible(node) || node.closest('aside,nav,figure,footer,[data-testid="recirculation"],[data-testid="newsletter-signup"]'))continue;
          const text=(node.innerText||'').trim();
          if(text && !/subscribe to the times|already a subscriber|thanks for reading the times/i.test(text))blocks.push({kind:node.tagName.toLowerCase(),text});
        }
      }
      return {url:location.href,accessBlocked:false,message:'',blocks};
    })()
    """;
}

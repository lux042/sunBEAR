// Run with Node 18+ from the source folder. No network calls or browser profile.
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('./BrowserPane.cs',import.meta.url),'utf8');
const template=source.match(/internal const string PdfFetchScript = """\r?\n([\s\S]*?)\r?\n\s*""";/)[1];
const script=template.replace('__KEY_JSON__',JSON.stringify('testFetch')).replace('__URL_JSON__',JSON.stringify('https://www.cia.gov/test.pdf'));
async function invoke(fetch,abort=false) {
  const window={};
  runInNewContext(script,{window,fetch,AbortController,Uint8Array,String,Error,btoa});
  if(abort)window.testFetch.controller.abort();
  for(let n=0;n<1000 && window.testFetch.result===null;n++)await new Promise(resolve=>setTimeout(resolve,2));
  assert.notEqual(window.testFetch.result,null,'Fetch must finish');
  return window.testFetch.result;
}
const pdf=Buffer.concat([Buffer.from('%PDF-1.4\n'),Buffer.alloc(100001,131)]);
const good=await invoke(async(url,options)=>{
  assert.equal(url,'https://www.cia.gov/test.pdf');
  assert.equal(options.credentials,'include');
  assert.equal(options.cache,'no-store');
  return new Response(pdf,{headers:{'content-type':'application/pdf'}});
});
assert.equal(good.ok,true);assert.deepEqual(Buffer.from(good.data,'base64'),pdf);
console.log('PASS Browser session fetch, binary transfer and base64 chunk boundaries');
const html=await invoke(async()=>new Response('<html>Verification page</html>',{headers:{'content-type':'text/html'}}));
assert.equal(html.ok,false);assert.match(html.error,/instead of a PDF/);
console.log('PASS HTML response rejected with actionable message');
const denied=await invoke(async()=>new Response('Denied',{status:403}));
assert.equal(denied.ok,false);assert.match(denied.error,/HTTP 403/);
console.log('PASS HTTP access failure preserved');
const canceled=await invoke((url,options)=>new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(new Error('Download canceled')))),true);
assert.equal(canceled.ok,false);assert.match(canceled.error,/canceled/);
console.log('PASS Abort cancels browser fetch');
console.log('4 passed; 0 failed. Browser runtime integration still requires WebView2.');

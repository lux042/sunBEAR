import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('./ArticlePages.cs',import.meta.url),'utf8');
const script=source.match(/internal const string CaptureScript = """\r?\n([\s\S]*?)\r?\n\s*""";/)[1];
function element(text,tag='P',style={}){return {innerText:text,tagName:tag,nodeType:1,parentElement:null,hidden:false,style:{display:'block',visibility:'visible',opacity:'1',overflowY:'visible',...style},scrollHeight:30,clientHeight:30,getAttribute:()=>null,getClientRects:()=>[{}],closest:()=>null,querySelector:()=>null};}
function capture(paragraphs,gates=[]){const root=element('','SECTION');root.querySelectorAll=()=>paragraphs;for(const p of paragraphs)if(!p.parentElement)p.parentElement=root;const document={querySelectorAll:s=>s.startsWith('#gateway')?gates:[root]};return runInNewContext(script,{document,location:{href:'https://www.nytimes.com/2026/01/01/world/test.html'},getComputedStyle:n=>n.style,Array,Set,Number});}
const normal=capture([element('Synthetic heading','H2'),element('A visible synthetic paragraph.'),element('Hidden full text','P',{display:'none'})]);
assert.equal(normal.blocks.length,2);assert.equal(normal.blocks[0].kind,'h2');assert.equal(normal.blocks[1].text,'A visible synthetic paragraph.');
console.log('PASS Rendered article headings/text collected; hidden text excluded');
const gate=element('Subscribe to continue reading');const blocked=capture([element('Text behind the gateway')],[gate]);assert.equal(blocked.accessBlocked,true);assert.equal(blocked.blocks.length,0);
console.log('PASS Visible access prompt prevents article capture');
gate.style.display='none';const noGate=capture([element('Accessible text')],[gate]);assert.equal(noGate.accessBlocked,false);assert.equal(noGate.blocks.length,1);
console.log('PASS Hidden inactive gateway does not block available text');
const clipped=element('Clipped text','P',{overflowY:'hidden'});clipped.scrollHeight=200;clipped.clientHeight=20;
const nav=element('Newsletter prompt');nav.closest=()=>({});const filtered=capture([clipped,nav,element('Actual paragraph')]);assert.equal(filtered.blocks.length,1);
console.log('PASS Clipped text and non-article panels excluded');
console.log('4 passed; 0 failed. Live NYT body extraction still requires verification.');

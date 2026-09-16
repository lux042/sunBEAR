import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('./BrowserPane.cs',import.meta.url),'utf8');
const script=source.match(/internal const string ExpandNytScript = """\r?\n([\s\S]*?)\r?\n\s*""";/)[1];
function run(buttons){let scrolled=false;const root={querySelectorAll:()=>buttons};const document={querySelector:()=>root,documentElement:{scrollHeight:1000}};const window={scrollTo:()=>scrolled=true};const result=runInNewContext(script,{document,window,Array});return {result,scrolled};}
function button(text,disabled=false){return {innerText:text,disabled,clicked:false,getAttribute:()=>null,getClientRects:()=>[{}],click(){this.clicked=true;}};}
const more=button('Show More');const subscribe=button('Subscribe now');let r=run([subscribe,more]);assert.equal(r.result,'clicked');assert.equal(more.clicked,true);assert.equal(subscribe.clicked,false);
console.log('PASS Activates explicit result expansion, not subscription controls');
const disabled=button('Load more',true);r=run([disabled]);assert.equal(disabled.clicked,false);assert.equal(r.scrolled,true);
console.log('PASS Disabled controls skipped; topic-list scroll fallback');
const hidden=button('Show More');hidden.getClientRects=()=>[];const live=button('Load More Articles');r=run([hidden,live]);assert.equal(hidden.clicked,false);assert.equal(live.clicked,true);
console.log('PASS Hidden controls skipped and alternate article-list label supported');
console.log('3 passed; 0 failed. Live NYT layout has not been verified.');

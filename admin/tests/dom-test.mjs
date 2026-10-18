import {Window} from 'happy-dom';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const w=new Window({url:'https://sovera-control.soverixnet.chatgpt.site',width:390,height:844});
w.document.body.innerHTML='<div id="app"></div><div id="toast"></div><dialog id="confirm"><div id="confirmation"></div></dialog>';
let requests=0;
w.fetch=async()=>{requests++;return {ok:true,json:async()=>({ready:false})};};
w.eval('(function(){'+readFileSync(new URL('../web/app.js',import.meta.url),'utf8')+'\nwindow.testAPI={state,render,can,login,e,safeURL,api};})();');
await new Promise(r=>setTimeout(r,20));
assert.equal(w.document.querySelector('#login-submit').disabled,true);
assert.match(w.document.body.textContent,/awaiting approval/);
w.document.querySelector('#preview').click();await new Promise(r=>setTimeout(r,20));
assert.equal(w.document.querySelectorAll('[data-nav]').length,9);
for(const view of ['users','recharge','staff','rooms','content','support','history','audit','dashboard']){
 w.document.querySelector(`[data-nav="${view}"]`).click();await new Promise(r=>setTimeout(r,10));
 assert.ok(w.document.querySelector('#panel'),view+' rendered');assert.ok(!w.document.querySelector('#retry'),view+' has no render error');
}
assert.equal(requests,1,'Preview never calls account or admin APIs');
assert.equal(w.testAPI.safeURL('javascript:alert(1)'),'');assert.equal(w.testAPI.e('<img onerror="bad">'),'&lt;img onerror=&quot;bad&quot;&gt;');
w.testAPI.state.preview=false;w.testAPI.state.identity={role:'agent',permissions:['users.read','recharge.create','history.read']};
assert.equal(w.testAPI.can('owner'),false);assert.equal(w.testAPI.can('vip.manage'),false);assert.equal(w.testAPI.can('recharge.create'),true);
console.log('DOM tests passed: login gate, 9 sections, no preview API writes, escaping, role visibility');
await w.happyDOM.close();

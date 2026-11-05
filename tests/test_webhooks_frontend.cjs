const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup}=require('./test_frontend.cjs');
(async()=>{
 const t=setup(),source=fs.readFileSync('dist/webhooks.js','utf8');
 const mutate=source.slice(source.indexOf('async function whMutate('),source.indexOf("$('#whForm').onsubmit="));
 vm.runInContext("let webhookBusy=false,webhookGeneration=0;let seenSecret=null,successCount=0,loadCount=0;function whShowSecret(s){seenSecret=s;}async function loadWebhooks(){loadCount++;}",t.ctx);
 vm.runInContext(mutate,t.ctx);let finish;t.ctx.deferWebhook=()=>new Promise(r=>{finish=r});t.ctx.button={disabled:false};
 let p=vm.runInContext("whMutate(button,deferWebhook,()=>successCount++)",t.ctx);assert.equal(t.ctx.button.disabled,true);
 vm.runInContext('authEpoch++',t.ctx);finish({secret:'synthetic-secret'});await p;
 assert.equal(vm.runInContext('seenSecret',t.ctx),null,'Response after logout must not reveal signing secret');assert.equal(vm.runInContext('successCount',t.ctx),0);assert.equal(t.ctx.button.disabled,false);
 p=vm.runInContext("whMutate(button,deferWebhook,()=>successCount++)",t.ctx);finish({secret:'synthetic-secret'});await p;
 assert.equal(vm.runInContext('seenSecret',t.ctx),'synthetic-secret');assert.equal(vm.runInContext('successCount',t.ctx),1);assert.equal(vm.runInContext('loadCount',t.ctx),1);
 const render=source.slice(source.indexOf('function whRenderList(){'),source.indexOf('function whRenderHistory('));
 vm.runInContext("let webhookRows=[{id:'hook',name:'<img src=x onerror=alert(1)>',url:'https://example.com/?a=<script>',active:true,scope:'all',service:null,events:['consulta.finalizada']}];function whOrigin(){return 'All';}",t.ctx);
 vm.runInContext(render+';whRenderList()',t.ctx);assert(!t.get('#whList').innerHTML.includes('<img'));assert(t.get('#whList').innerHTML.includes('&lt;img'));assert(!t.get('#whHistoryHook').innerHTML.includes('<img'));
 console.log('PASS: webhook signing-secret race after logout, success handling and escaped integration names/URLs');
})().catch(e=>{console.error(e);process.exitCode=1});

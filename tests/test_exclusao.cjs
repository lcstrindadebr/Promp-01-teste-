const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();vm.runInContext(fs.readFileSync('dist/exclusao.js','utf8'),t.ctx);
 vm.runInContext("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600,user:{id:'u'}};records=[{id:'j',nome:'TESTE',lote_id:'c'}];campaigns=[{id:'c',nome:'TESTE'}];activeCampaign='c'",t.ctx);
 t.ctx.window.confirm=()=>false;await vm.runInContext("deleteConsultation('j')",t.ctx);assert.equal(t.calls.length,0);
 t.ctx.window.confirm=()=>true;t.handler(async(u,o)=>response(o.method==='DELETE'?[{id:'j'}]:[]));
 await vm.runInContext("deleteConsultation('j')",t.ctx);assert(t.calls.some(([u,o])=>u.includes('consulta_jobs?id=eq.j')&&o.method==='DELETE'));
 vm.runInContext("records=[{id:'j',nome:'TESTE',lote_id:'c'}];campaigns=[{id:'c',nome:'TESTE'}];activeCampaign='c'",t.ctx);
 await t.get('#deleteCampaign').onclick();assert(t.calls.some(([u,o])=>u.includes('consulta_lotes?id=eq.c&tipo=eq.campanha')&&o.method==='DELETE'));assert.equal(vm.runInContext('activeCampaign',t.ctx),null);
 console.log('PASS: cancellation makes no request; scoped consultation and campaign delete; clears selected campaign');
})().catch(e=>{console.error(e);process.exitCode=1});

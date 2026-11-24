const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup}=require('./test_frontend.cjs');
const json=(data,status=200)=>({ok:status<400,status,json:async()=>data,text:async()=>JSON.stringify(data)});
const tick=async(n=4)=>{for(let i=0;i<n;i++)await new Promise(setImmediate);};
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/dashboard.js','utf8'));
 run(fs.readFileSync('dist/painel-resumo.js','utf8'));
 run(`currentAccess={role:'partner',active:true,daily_limit:null,remaining:null,services:[]};campaigns=[];records=[];
 authenticated=true;session={access_token:'fixture',expires_at:Date.now()/1000+3600};`);
 let calls=0;
 t.handler(async url=>{
  if(String(url).endsWith('/rpc/painel_crm_totais')){calls++;return json({clientes:82927,oportunidades:{abertas:17668,ganhas:1,perdidas:3,total:17672}});}
  return json({});
 });
 run("navigate('dashboard')");await tick();
 assert.equal(calls,1);
 assert.equal(t.get('#dashClients').textContent,'82.927');
 assert.equal(t.get('#dashOpportunities').textContent,'17.668');
 assert.equal(t.get('#dashOpportunitiesSub').textContent,'1 ganha · 17.672 no total');
 // Counting the whole base is heavier: renders inside the minute do not ask again; other pages never ask.
 run('render()');await tick();assert.equal(calls,1);
 run("navigate('home')");await tick();assert.equal(calls,1);
 // Tiles open the CRM pages.
 run("navigate('dashboard')");await tick();
 t.get('[data-dashboard-tile="opportunities"]').click();assert.equal(run('currentPage'),'opportunities');
 run("navigate('dashboard')");t.get('[data-dashboard-tile="clients"]').click();assert.equal(run('currentPage'),'clients');
 // After logout the previous account's numbers are not shown.
 run('authEpoch++');run("navigate('dashboard')");run('renderCrmTotais()');
 assert.equal(t.get('#dashClients').textContent,'—');
 // Before the migration: the tiles hide and the panel stops asking.
 const t2=setup();const run2=code=>vm.runInContext(code,t2.ctx);
 run2(fs.readFileSync('dist/dashboard.js','utf8'));run2(fs.readFileSync('dist/painel-resumo.js','utf8'));
 run2(`currentAccess={role:'partner',active:true,services:[]};campaigns=[];records=[];authenticated=true;session={access_token:'f',expires_at:Date.now()/1000+3600};`);
 let missing=0;
 t2.handler(async url=>{if(String(url).endsWith('/rpc/painel_crm_totais')){missing++;return json({message:'not found'},404);}return json({});});
 run2("navigate('dashboard')");await tick();assert.equal(t2.get('[data-dashboard-tile="clients"]').hidden,true,'Hidden right after the 404');
 run2("navigate('home');navigate('dashboard')");await tick();
 assert.equal(missing,1);assert.equal(t2.get('[data-dashboard-tile="clients"]').hidden,true);
 console.log('crm totais frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

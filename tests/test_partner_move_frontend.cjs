const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
const json=(data,status=200)=>({ok:status<400,status,json:async()=>data,text:async()=>JSON.stringify(data)});
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run('function loadAmigozTables(){};function tickMonitoring(){};function loadApiTokens(){};function loadApiDocs(){};');
 run(fs.readFileSync('dist/settings.js','utf8'));
 // setup() already ran the first part of partners.js (limits and guards); this is the rest.
 run('const quotaBox='+fs.readFileSync('dist/partners.js','utf8').split('const quotaBox=')[1]);
 run("authenticated=true;session={access_token:'fixture',expires_at:Date.now()/1000+3600};currentAccess={role:'admin',active:true,services:[]};");
 const access={services:[{id:'digimais_saldo_parcela',enabled:true,allow_individual:true,allow_campaign:true},{id:'tjba_margem',enabled:false}],shared_quota:true,daily_limit:null};
 const companies=[{user_id:'p1',name:'Empresa Um',email:'um@x.invalid',active:true,shared_quota:true,members:3,access},
  {user_id:'p2',name:'Empresa Dois',email:'dois@x.invalid',active:true,shared_quota:true,members:1,access},
  {user_id:'p3',name:'Suspensa',email:'tres@x.invalid',active:false,shared_quota:true,members:1,access}];
 let moved=null;
 t.handler(async(url,options)=>{
  if(String(url)==='/api/admin/parceiros')return json({data:companies});
  if(String(url).includes('admin_move_member')){moved=JSON.parse(options.body);return response({tenant_id:'t1',registros:42});}
  return response([]);
 });
 await run('loadPartners()');
 assert.match(t.get('#partnerList').textContent,/Usuários ativos: 3/);
 assert.equal(t.get('#partnerList').querySelectorAll('[data-move-partner]').length,3);
 run("movePartner('p2')");
 const targets=[...t.get('#partnerMoveTarget').options].map(o=>o.value);
 assert.deepEqual(targets,['p1'],'Only other active companies are offered');
 t.get('#partnerMoveRole').value='operador';
 t.window.confirm=()=>true;
 await t.get('#partnerMoveForm').onsubmit({preventDefault(){},target:t.get('#partnerMoveForm')});
 assert.deepEqual(moved,{p_user:'p2',p_target_user:'p1',p_role:'operador'});
 console.log('partner move frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

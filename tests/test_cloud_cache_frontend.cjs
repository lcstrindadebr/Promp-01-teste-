const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/cloud-cache.js','utf8'));
 // In-memory store instead of IndexedDB (same interface).
 run(`const memory=new Map();cloudCacheStore.get=async k=>memory.get(k);cloudCacheStore.set=async(k,v)=>{memory.clear();memory.set(k,JSON.parse(JSON.stringify(v)));};cloudCacheStore.clear=async()=>memory.clear();globalThis.cacheMemory=memory;`);
 run(`authenticated=true;session={access_token:'t',refresh_token:'r',expires_at:Date.now()/1000+3600,user:{id:'u1',email:'a@x'}};
  currentAccess={role:'partner',active:true,services:[],tenant:{tenant_id:'t1',permissions:['dados.ver_empresa']}};`);
 const job=(id,status)=>({chave:'consulta_jobs:'+id,origem:'consulta_jobs',id,excluido:false,dados:{id,lote_id:'L',nome:'Cliente '+id,cpf:'00000000191',status,servico:'digimais_saldo_parcela',created_at:'2026-11-17T10:00:00Z'}});
 const calls=[];let reply=()=>({snapshot:'S1',rows:[job('a','concluida'),job('b','aguardando')],next:null});
 t.handler(async(url,options)=>{if(String(url).includes('painel_consultas_sync')){const body=JSON.parse(options.body);calls.push(body);return response(reply(body));}return response([]);});

 // First opening: full download, then the copy is saved with the sync point.
 await run('loadCloud()');
 assert.equal(calls[0].p_since,null);assert.equal(run('records.length'),2);
 assert.equal(run('[...cacheMemory.values()][0].snapshot'),'S1');
 assert.equal(run('[...cacheMemory.keys()][0]'),'v2:u1:t1:empresa:avulsas');

 // Reopening (same account): the copy shows at once and only changes are requested.
 run(`cloudSnapshot=null;cloudRows.clear();records=[];cloudCacheTried=null;`);
 let seenBeforeNetwork=null;
 reply=body=>{seenBeforeNetwork=run('records.length');return {snapshot:'S2',rows:[job('b','concluida'),{chave:'consulta_jobs:a',origem:'consulta_jobs',id:'a',excluido:true,dados:null}],next:null};};
 calls.length=0;await run('loadCloud()');
 assert.equal(calls[0].p_since,'S1','Only changes since the saved point');
 assert.equal(seenBeforeNetwork,2,'Cached rows shown before the database answers');
 assert.deepEqual(run('records.map(r=>r.id+":"+r.status)'),['b:Concluída'],'Changes and deletions applied on top of the copy');

 // Another scope (Operador) does not reuse a company-wide copy.
 run(`cloudSnapshot=null;cloudRows.clear();records=[];cloudCacheTried=null;currentAccess={...currentAccess,tenant:{tenant_id:'t1',permissions:[]}};`);
 reply=()=>({snapshot:'S3',rows:[job('z','concluida')],next:null});
 calls.length=0;await run('loadCloud()');
 assert.equal(calls[0].p_since,null,'Different scope downloads everything');

 // Signing out erases the local copy.
 await run('signOut()');
 assert.equal(run('cacheMemory.size'),0);
 console.log('cloud cache frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

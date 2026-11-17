// Fase 2b: cópia local das consultas e campanhas já baixadas.
// Ao abrir o painel de novo, mostra a cópia na hora e busca no banco só o que mudou desde então
// (a sincronização já é incremental: o banco devolve alterações e exclusões depois do ponto salvo).
// A cópia é por conta, empresa e escopo de visão; vence em 7 dias; "Sair da conta" apaga tudo.
const cloudCacheVersion=1,cloudCacheMaxAge=7*24*3600*1000,cloudCacheSaveEvery=60000;
const cloudCacheStore={
 db:null,
 open(){
  if(this.db)return this.db;
  this.db=new Promise((resolve,reject)=>{
   if(typeof indexedDB==='undefined')return reject(Error('Sem IndexedDB'));
   const request=indexedDB.open('apoiarcred-painel',1);
   request.onupgradeneeded=()=>request.result.createObjectStore('sync');
   request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);
  }).catch(error=>{this.db=null;throw error;});
  return this.db;
 },
 async run(mode,action){
  const db=await this.open();
  return new Promise((resolve,reject)=>{
   const tx=db.transaction('sync',mode),store=tx.objectStore('sync'),request=action(store);
   tx.oncomplete=()=>resolve(request?.result);tx.onerror=tx.onabort=()=>reject(tx.error);
  });
 },
 get(key){return this.run('readonly',store=>store.get(key));},
 set(key,value){return this.run('readwrite',store=>{store.clear();return store.put(value,key);});},
 clear(){return this.run('readwrite',store=>store.clear());}
};
let cloudCacheKey=null,cloudCacheTried=null,cloudCacheSavedAt=0,cloudCacheDirty=false,cloudCacheTimer=0;
function cloudCacheIdentity(){
 const user=session?.user?.id,tenant=currentAccess?.tenant;
 if(!user)return null;
 const scope=currentAccess?.role==='admin'||tenant?.permissions?.includes('dados.ver_empresa')?'empresa':'proprios';
 return ['v'+cloudCacheVersion,user,tenant?.tenant_id||'-',scope].join(':');
}
async function cloudCacheRestore(epoch){
 const key=cloudCacheIdentity();if(!key)return;
 try{
  const saved=await cloudCacheStore.get(key);
  if(epoch!==authEpoch||cloudSnapshot!==null||!saved)return;
  if(Date.now()-saved.saved_at>cloudCacheMaxAge||!Array.isArray(saved.entries)||!saved.snapshot)return;
  cloudRows.clear();for(const [chave,value] of saved.entries)cloudRows.set(chave,value);
  cloudSnapshot=saved.snapshot;cloudCacheKey=key;cloudCacheSavedAt=Date.now();
  publishCloudRows();
 }catch{/* Sem cópia local: segue o carregamento completo. */}
}
async function cloudCacheSave(force=false){
 clearTimeout(cloudCacheTimer);cloudCacheTimer=0;
 const key=cloudCacheIdentity();
 if(!key||!cloudSnapshot||!authenticated||!cloudCacheDirty&&!force)return;
 // O acesso mudou nesta sessão (empresa ou escopo): a cópia em memória pode ter o que não se vê mais.
 if(cloudCacheKey&&key!==cloudCacheKey){cloudCacheDirty=false;try{await cloudCacheStore.clear();}catch{}return;}
 cloudCacheDirty=false;cloudCacheSavedAt=Date.now();cloudCacheKey=key;
 try{await cloudCacheStore.set(key,{snapshot:cloudSnapshot,saved_at:Date.now(),entries:[...cloudRows.entries()]});}
 catch{/* Cota do navegador cheia ou modo privado: o painel funciona sem a cópia. */}
}
function cloudCacheSchedule(){
 cloudCacheDirty=true;if(cloudCacheTimer)return;
 cloudCacheTimer=setTimeout(()=>cloudCacheSave(),Math.max(0,cloudCacheSaveEvery-(Date.now()-cloudCacheSavedAt)));
}
const cloudCacheBaseSync=syncCloudPages;
syncCloudPages=async function(epoch){
 const key=cloudCacheIdentity();
 if(cloudSnapshot===null&&key&&cloudCacheTried!==key){cloudCacheTried=key;await cloudCacheRestore(epoch);}
 const before=cloudSnapshot,firstLoad=before===null;
 await cloudCacheBaseSync(epoch);
 if(epoch!==authEpoch||!cloudSnapshot||cloudSnapshot===before)return;
 if(firstLoad)await cloudCacheSave(true);else cloudCacheSchedule();
};
// Salva ao sair da aba, para a próxima abertura começar do ponto mais recente.
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden'&&cloudCacheDirty)cloudCacheSave();});
// Trocar de conta não reaproveita a tentativa anterior; sair da conta apaga a cópia.
const cloudCacheBaseShowLogin=showLogin;
showLogin=function(...args){cloudCacheTried=null;cloudCacheKey=null;cloudCacheDirty=false;clearTimeout(cloudCacheTimer);cloudCacheTimer=0;return cloudCacheBaseShowLogin(...args);};
const cloudCacheBaseSignOut=signOut;
signOut=async function(...args){try{await cloudCacheStore.clear();}catch{}return cloudCacheBaseSignOut(...args);};
$('#logout').onclick=()=>signOut();$('#topLogout').onclick=()=>signOut();

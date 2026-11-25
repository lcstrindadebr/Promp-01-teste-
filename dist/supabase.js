// All data uses Supabase. The browser receives only a publishable/anon key.
const sb=window.SUPABASE_CONFIG;
const storageKey='apoiarcred-auth:'+sb.url;
let currentAccess=null,accessRefreshing=false,accessCheckedAt=0;
let session=null,authenticated=false,refreshing=null,loadingCloud=false,authEpoch=0;
const statusNames={aguardando:'Aguardando',processando:'Processando',concluida:'Concluída',nao_localizado:'Não é cliente',nao_cliente:'Não é cliente',ja_vendeu:'Já vendeu',inadimplencia_administrativa:'Inadimplência administrativa',inadimplencia_juridica:'Inadimplência jurídica',nao_encontrado:'Não encontrado',erro:'Erro',revisao:'Revisão',interrompida:'Consulta interrompida'};
function showLogin(message=''){
 $('#password').required=true;$('#loginSubmit').textContent='Entrar';$('#loginSwitchAccount').hidden=true;
 digimaisCampaignUpload=null;authenticated=false;session=null;currentAccess=null;accessRefreshing=false;accessCheckedAt=0;authEpoch++;if(typeof resetPartnerSettings==='function')resetPartnerSettings();if(typeof resetApiSettings==='function')resetApiSettings();if(typeof resetWebhooks==='function')resetWebhooks();if(typeof resetTjbaSettings==='function')resetTjbaSettings();importGeneration++;readingImport=false;importError='';if(typeof resetAmigoz==='function')resetAmigoz();if(typeof resetMonitoring==='function')resetMonitoring();cloudSnapshot=null;cloudRows.clear();setCloudLoading(null);cloudLoadAgain=false;cloudSyncErrorAt=0;cloudSyncRetryAt=0;cloudSyncFailures=0;records=[];pending=[];campaigns=[];activeCampaign=null;retryingCampaign=false;$('#campaignName').value='';navigate(typeof renderDashboard==='function'?"dashboard":"home");
 $('#consultationLogPanel').open=false;$('#consultationLogRobot').value='';authStore.clear();$('#appShell').hidden=true;$('#loginPage').hidden=false;
 $('#loginStatus').textContent='';$('#loginError').textContent=message;$('#preview').classList.add('hide');$('#file').value='';$('#import').disabled=true;renderLogs();render(); // renderLogs clears the previous account's log text.
}
const authStore={
 get(){try{return localStorage.getItem(storageKey)||sessionStorage.getItem(storageKey)}catch{return null}},
 set(value){try{localStorage.setItem(storageKey,value);sessionStorage.removeItem(storageKey)}catch{try{sessionStorage.setItem(storageKey,value)}catch{}}},
 clear(){try{localStorage.removeItem(storageKey)}catch{}try{sessionStorage.removeItem(storageKey)}catch{}}
};
function saveSession(data){session={...data,expires_at:data.expires_at||Math.floor(Date.now()/1000)+data.expires_in};authStore.set(JSON.stringify(session))}
// Requests go straight to Supabase (Auth and PostgREST), as in a standard Supabase app.
// The VPS session gateway is no longer on the login path.
const AUTH_TIMEOUT_MS=30000,DATA_TIMEOUT_MS=30000;
async function raw(path,options={},timeoutMs=path.startsWith('/auth/')?AUTH_TIMEOUT_MS:DATA_TIMEOUT_MS){
 const controller=new AbortController();
 const timer=setTimeout(()=>controller.abort(),timeoutMs);
 let res,text;
 try{
  res=await fetch(sb.url+path,{...options,headers:{apikey:sb.key,'Content-Type':'application/json',...options.headers},signal:controller.signal,cache:'no-store'});
  text=await res.text();
 }catch(error){
  if(controller.signal.aborted)throw Object.assign(Error('Tempo de espera esgotado.'),{name:'TimeoutError'});
  throw error;
 }finally{clearTimeout(timer);}
 let data;
 try{data=text?JSON.parse(text):null}catch{
  if(res.ok)throw Error('Resposta inválida do Supabase.');
 }
 if(!res.ok){
  const error=Error(data?.message||data?.msg||data?.error_description||'Falha na conexão com Supabase');
  error.status=res.status;
  error.code=data?.error_code||data?.code||data?.error?.code;
  throw error;
 }
 return data;
}
async function refreshSession(){
 if(!session)throw Error('Entre na sua conta.');if(Date.now()/1000<session.expires_at-60)return;
 if(!refreshing)refreshing=(async()=>{const epoch=authEpoch;try{const data=await raw('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:JSON.stringify({refresh_token:session.refresh_token})});if(epoch!==authEpoch)throw Error('Sessão encerrada.');saveSession(data)}catch(e){if(epoch===authEpoch&&[400,401,403].includes(e.status))showLogin('Sessão expirada. Entre novamente.');throw e}finally{refreshing=null}})();
 await refreshing;
}
async function sbRequest(path,options={}){
 if(!authenticated)throw Error('Entre na sua conta.');await refreshSession();
 try{return await raw(path,{...options,headers:{...options.headers,Authorization:'Bearer '+session.access_token}})}catch(e){if(e.status===401)showLogin('Sessão expirada. Entre novamente.');throw e}
}
async function fetchAll(path){
 const rows=[];for(let offset=0;;offset+=1000){const page=await sbRequest(path+'&limit=1000&offset='+offset);rows.push(...page);if(page.length<1000)break;}
 return [...new Map(rows.map(row=>[row.id,row])).values()];
}
let digimaisCampaignUpload=null;
async function createCampaign(name,items){
 if(!authenticated)throw Error('Entre na sua conta.');
 if(!name.trim()||name.trim().length>160||!items.length)throw Error('Informe o nome e selecione clientes válidos.');
 const service=selectedService();
 const payload={p_nome:name.trim(),p_items:items.map(r=>({nome:r.nome,cpf:r.cpf,telefone:r.telefone}))};
 // Campanhas grandes vão em partes (cada parte bem abaixo do limite de tempo do banco) e podem ser retomadas.
 // ConsigX: até 250 CPFs por parte, no convênio escolhido; Digi+: até 100 leads.
 const consigx=service==='tjba_margem',convenio=consigx&&typeof selectedConvenio==='function'?selectedConvenio():null;
 const batchSize=consigx?250:100;
 const retry=['digimais_saldo_parcela','tjba_margem'].includes(service)&&digimaisCampaignUpload?.epoch===authEpoch&&
  digimaisCampaignUpload.service===service&&digimaisCampaignUpload.convenio===convenio&&
  digimaisCampaignUpload.name===payload.p_nome&&digimaisCampaignUpload.items===items;
 if(!retry){
  const quotaError=typeof campaignImportError==='function'?campaignImportError(items.length):'';
  if(quotaError)throw Error(quotaError);
  if(typeof assertCanSubmit==='function')assertCanSubmit(service,'campaign');
 }
 let id;
 if(['digimais_saldo_parcela','tjba_margem'].includes(service)&&items.length>batchSize){
  if(consigx&&new Set(payload.p_items.map(r=>r.cpf)).size!==payload.p_items.length)throw Error('Há CPFs duplicados.');
  if(!retry)digimaisCampaignUpload={id:crypto.randomUUID(),epoch:authEpoch,service,convenio,name:payload.p_nome,items,offset:0};
  const upload=digimaisCampaignUpload;
  const submitBatch=(rows)=>consigx
   ?sbRequest('/rest/v1/rpc/save_consigx_campaign_batch',{method:'POST',
     body:JSON.stringify({p_id:upload.id,p_nome:payload.p_nome,p_convenio:convenio,p_total:items.length,p_items:rows})})
   :sbRequest('/rest/v1/rpc/save_digimais_campaign_batch',{method:'POST',
     body:JSON.stringify({p_id:upload.id,p_nome:payload.p_nome,p_total:items.length,p_items:rows})});
  try{
   while(upload.offset<items.length){
    if(upload.epoch!==authEpoch)throw Error('Sessão encerrada.');
    const rows=payload.p_items.slice(upload.offset,upload.offset+batchSize);
    await submitBatch(rows);
    upload.offset+=rows.length;
    if(upload.offset%1000===0||upload.offset===items.length)toast(upload.offset.toLocaleString('pt-BR')+' de '+items.length.toLocaleString('pt-BR')+(consigx?' clientes enviados.':' leads enviados.'));
   }
   if(upload.epoch!==authEpoch)throw Error('Sessão encerrada.');
   await submitBatch([]);
  }catch(error){
   throw Error('Envio interrompido após '+upload.offset.toLocaleString('pt-BR')+(consigx?' clientes':' leads')+' confirmados. Mantenha a planilha selecionada e clique novamente para retomar. '+error.message);
  }
  id=upload.id;digimaisCampaignUpload=null;
 }else{
  const route=service==='tjba_margem'?'create_consigx_campaign':'create_consulta_campaign';
  if(service==='tjba_margem')payload.p_convenio=selectedConvenio();else payload.p_servico=service;
  id=await sbRequest('/rest/v1/rpc/'+route,{method:'POST',body:JSON.stringify(payload)});
 }
 await loadCloud();await refreshMyAccess(true).catch(()=>{});return id;
}
async function retryCampaign(id){
 if(!authenticated)throw Error('Entre na sua conta.');
 return await sbRequest('/rest/v1/rpc/'+(campaigns.find(c=>c.id===id)?.servico==='tjba_margem'?'retry_tjba_campaign':'retry_consulta_campaign'),{method:'POST',body:JSON.stringify({p_campaign_id:id})});
}
let cloudSnapshot=null;
const cloudRows=new Map();
const consultationLogDetails=new WeakMap();
let cloudLoadPromise=null,cloudLoadAgain=false,cloudSyncErrorAt=0;
let cloudSyncRetryAt=0,cloudSyncFailures=0;

async function loadConsultationLogDetail(row){
 if(consultationLogDetails.has(row))return consultationLogDetails.get(row);
 const source=row.servico==='tjba_margem'?'tjba_jobs':'consulta_jobs';
 const columns=source==='tjba_jobs'?'message,resultado_tjba':'message,resultado_saldo,resultado_parcela,api_handoff';
 const request=sbRequest('/rest/v1/'+source+'?select='+columns+'&id=eq.'+encodeURIComponent(row.id))
  .then(rows=>({...row,...rows[0]})).catch(error=>{consultationLogDetails.delete(row);throw error;});
 consultationLogDetails.set(row,request);
 return request;
}
function cloudSyncVisible(){
 return authenticated&&document.visibilityState!=='hidden'&&(
  ['home','campaigns'].includes(currentPage)||
  (currentPage==='settings'&&(!$('#settings-digimais-api')?.hidden||$('#consultationLogPanel')?.open))
 );
}
function normalizeCloudRow(r){
 return {...r,cpf:formatCpf(r.cpf),nome:r.nome==='CPF '+r.cpf?'CPF '+formatCpf(r.cpf):r.nome,
  date:r.consultado_em||r.created_at,status:statusNames[r.status]||r.status,
  saldo:r.saldo_liquidacao==null?null:Number(r.saldo_liquidacao),parcelas:r.total_parcelas,
  valorParcela:r.valor_parcela==null?null:Number(r.valor_parcela)};
}
function applyCloudEntries(entries){
 for(const entry of entries){
  if(entry.excluido||(!entry.origem.endsWith('_jobs')&&entry.dados.tipo!=='campanha')){
   cloudRows.delete(entry.chave);
   continue;
  }
  cloudRows.set(entry.chave,{kind:entry.origem.endsWith('_jobs')?'job':'campaign',
   row:entry.origem.endsWith('_jobs')?normalizeCloudRow(entry.dados):entry.dados});
 }
}
function publishCloudRows(){
 const newest=(a,b)=>b.created_at.localeCompare(a.created_at)||b.id.localeCompare(a.id);
 const entries=[...cloudRows.values()];
 const nextCampaigns=entries.filter(e=>e.kind==='campaign').map(e=>e.row).sort(newest);
 if(!campaigns.length&&nextCampaigns.length&&!$('#campaignName').value&&!pending.length)$('#newCampaignPanel').open=false;
 campaigns=nextCampaigns;
 records=entries.filter(e=>e.kind==='job').map(e=>e.row).sort(newest);
 render();
}
let cloudInitialLoad=null;
function setCloudLoading(state){
 cloudInitialLoad=state;
 document.body?.classList?.toggle('cloud-loading',!!state);
 const label=state?'Carregando suas consultas'+(state.count?' · '+state.count.toLocaleString('pt-BR')+' registros':'')+'…':'';
 for(const id of ['cloudLoadStatus','campaignLoadStatus']){const el=document.getElementById?.(id);if(el){el.textContent=label;el.hidden=!state;}}
}
// Fase 2c, etapa 3: as consultas de campanha chegam página a página (campaign-server.js), então a
// sincronização traz só as campanhas e as consultas avulsas. Volta a trazer tudo quando o banco ainda não
// tem o escopo (PGRST202) ou as funções de campanha não existem.
let cloudScopeOff=false,cloudSyncedScope=null;
function cloudScope(){return cloudScopeOff||(typeof serverCampaignsOff!=='undefined'&&serverCampaignsOff)?'tudo':'avulsas';}
async function syncCloudPages(epoch){
 const scope=cloudScope();
 // Mudou o escopo (ex.: as funções de campanha faltaram): começa do zero com o novo.
 if(cloudSnapshot!==null&&cloudSyncedScope!==scope)cloudSnapshot=null;
 const since=cloudSnapshot,buffer=[],initial=since===null;
 let until=null,after=null,lastPublish=0,count=0;
 // A retried first load starts clean so rows removed meanwhile do not linger.
 if(initial){cloudRows.clear();setCloudLoading({count:0});}
 try{
  do{
   if(epoch!==authEpoch||!authenticated||document.visibilityState==='hidden')return;
   let page;
   try{
    page=await sbRequest('/rest/v1/rpc/painel_consultas_sync',{
     method:'POST',body:JSON.stringify(scope==='avulsas'?{p_since:since,p_until:until,p_after:after,p_escopo:scope}:{p_since:since,p_until:until,p_after:after})
    });
   }catch(error){
    if(scope==='avulsas'&&error?.code==='PGRST202'&&!after){cloudScopeOff=true;return syncCloudPages(epoch);}
    throw error;
   }
   if(epoch!==authEpoch||!authenticated||document.visibilityState==='hidden')return;
   until=page.snapshot;
   if(page.next&&after&&page.next<=after)throw Error('A paginação da sincronização não avançou.');
   after=page.next;
   if(initial){
    // First load: show rows as pages arrive instead of waiting for the whole history.
    applyCloudEntries(page.rows);count+=page.rows.length;setCloudLoading({count});
    if(!after||Date.now()-lastPublish>800){publishCloudRows();lastPublish=Date.now();}
   }else buffer.push(...page.rows);
  }while(after);
  cloudSnapshot=until;cloudSyncedScope=scope;
  if(initial)return;
  if(!buffer.length)return;
  applyCloudEntries(buffer);
  publishCloudRows();
 }finally{
  if(initial&&epoch===authEpoch)setCloudLoading(null);
 }
}
function loadCloud(){
 if(!authenticated||document.visibilityState==='hidden'||Date.now()<cloudSyncRetryAt)return Promise.resolve();
 if(cloudLoadPromise){cloudLoadAgain=true;return cloudLoadPromise;}
 const epoch=authEpoch;
 loadingCloud=true;
 cloudLoadPromise=(async()=>{
  do{
   cloudLoadAgain=false;
   await syncCloudPages(epoch);
   if(epoch===authEpoch){cloudSyncRetryAt=0;cloudSyncFailures=0;}
  }while(cloudLoadAgain&&epoch===authEpoch&&authenticated&&document.visibilityState!=='hidden');
 })().catch(error=>{
  if(epoch!==authEpoch||!authenticated)return;
  cloudSyncFailures++;
  const now=Date.now();
  cloudSyncRetryAt=now+Math.min(60000,5000*2**Math.min(cloudSyncFailures,4));
  if(now-cloudSyncErrorAt>30000){
   cloudSyncErrorAt=now;
   toast('Não foi possível atualizar as consultas. O painel tentará novamente em instantes.');
  }
 }).finally(()=>{
  cloudLoadPromise=null;loadingCloud=false;
  if(epoch!==authEpoch&&authenticated&&document.visibilityState!=='hidden')loadCloud();
 });
 return cloudLoadPromise;
}
async function add(items,service=selectedService(),convenio=null){
 if(!authenticated)throw Error('Entre na sua conta.');if(items.length!==1)throw Error('Use Campanhas para importar consultas em lote.');convenio=convenio||(typeof selectedConvenio==='function'?selectedConvenio():'tjba');
 if(typeof assertCanSubmit==='function')assertCanSubmit(service,'individual');
 await sbRequest('/rest/v1/rpc/create_individual_consulta',{method:'POST',body:JSON.stringify({p_item:items[0],p_servico:service,p_convenio:convenio})});
 toast('Consulta salva na fila.');await loadCloud();await refreshMyAccess(true);

}
async function refreshMyAccess(force=false){
 if(!authenticated||accessRefreshing||(!force&&Date.now()-accessCheckedAt<15000))return;
 const epoch=authEpoch;accessRefreshing=true;
 try{const data=await sbRequest('/rest/v1/rpc/my_access',{method:'POST',body:'{}'});if(epoch!==authEpoch)return;
 if(!data||!['admin','partner'].includes(data.role)||!Array.isArray(data.services))throw Error('Não foi possível validar as permissões da conta.');
 currentAccess=data;accessCheckedAt=Date.now();if(typeof applyAccessUi==='function')applyAccessUi();
 }finally{if(epoch===authEpoch)accessRefreshing=false;}
}
function isConnectionFailure(error){
 return error.name==='TimeoutError'||(error.name==='TypeError'&&!error.status);
}
function loginFailureMessage(error){
 if(error.code==='invalid_credentials')return 'E-mail ou senha inválidos.';
 if(error.code==='email_not_confirmed')return 'Confirme seu e-mail antes de entrar.';
 if(error.status===429)return 'Muitas tentativas de login. Aguarde alguns instantes e tente novamente.';
 if(error.name==='TimeoutError')return 'O serviço de login demorou para responder. Tente novamente.';
 if(isConnectionFailure(error))return 'Não foi possível conectar ao serviço de login. Verifique sua conexão e tente novamente.';
 if(error.status>=500)return 'O serviço de login está indisponível no momento. Tente novamente em instantes.';
 return 'Não foi possível entrar. Se o problema persistir, informe o horário da tentativa ao administrador.';
}
function keepSessionForRetry(message){
 authenticated=false;
 currentAccess=null;
 $('#appShell').hidden=true;
 $('#loginPage').hidden=false;
 $('#loginError').textContent=message;
 $('#loginSubmit').textContent='Tentar acessar novamente';
 $('#password').required=false;
 $('#loginSwitchAccount').hidden=false;
}
async function openPanel(){
 authenticated=true;
 const epoch=authEpoch;
 setLoginStage('Validando seu acesso');
 try{
  try{await refreshMyAccess(true);}
  catch(error){
   if([400,401,403].includes(error.status)||epoch!==authEpoch)throw error;
   setLoginStage('Confirmando suas permissões');
   await new Promise(resolve=>setTimeout(resolve,1500));
   if(epoch!==authEpoch)return;
   await refreshMyAccess(true);
  }
  if(epoch!==authEpoch)return;
  if(!currentAccess?.active){
   showLogin('Conta sem acesso ativo. Solicite liberação ao administrador.');
   return;
  }
 }catch(error){
  if(epoch!==authEpoch)return;
  if([400,401,403].includes(error.status)){showLogin('Sessão encerrada. Entre novamente.');return;}
  keepSessionForRetry('Você entrou, mas não conseguimos confirmar suas permissões agora. Tente novamente em instantes.');
  return;
 }
 $('#loginPage').hidden=true;
 $('#appShell').hidden=false;
 $('#accountEmail').textContent=session.user.email;
 $('#authState').textContent='Conectado como '+session.user.email;
 $('#password').value='';
 setPasswordVisible(false);
 $('#loginError').textContent='';
 loadCloud();
 if(typeof applyAccessUi==='function')applyAccessUi();
 if(typeof loadAmigozSettings==='function')loadAmigozSettings();
 if(typeof loadTjbaSettings==='function')loadTjbaSettings();
}
let loginClock=null,loginStage='',loginStarted=0;
function setLoginStage(label){
 loginStage=label;
 loginStarted=Date.now();
 const update=()=>{
  const elapsed=Math.floor((Date.now()-loginStarted)/1000);
  $('#loginStatus').textContent=elapsed<3?loginStage+'…':loginStage+'… '+elapsed+' s';
 };
 clearInterval(loginClock);
 $('#loginProgress').hidden=false;
 $('#loginSubmit').classList?.add('is-loading');
 update();
 loginClock=setInterval(update,1000);
}
function finishLoginWait(){
 clearInterval(loginClock);loginClock=null;
 $('#loginStatus').textContent='';
 $('#loginProgress').hidden=true;
 $('#loginSubmit').classList?.remove('is-loading');
 $('#loginSubmit').disabled=false;
 $('#email').readOnly=false;
 $('#password').readOnly=false;
 $('#login').setAttribute('aria-busy','false');
}

function setPasswordVisible(visible){
 const password=$('#password');
 const toggle=$('#togglePassword');
 password.type=visible?'text':'password';
 toggle.textContent=visible?'Ocultar':'Mostrar';
 toggle.setAttribute('aria-label',visible?'Ocultar senha':'Mostrar senha');
}

$('#togglePassword').onclick=()=>setPasswordVisible($('#password').type==='password');
const passwordInput=$('#password');
if(typeof passwordInput.addEventListener==='function'){
for(const type of ['keydown','keyup'])passwordInput.addEventListener(type,event=>{
 if(event.getModifierState)$('#capsLockHint').hidden=!event.getModifierState('CapsLock');
});
passwordInput.addEventListener('blur',()=>{$('#capsLockHint').hidden=true;});
}
function loginInputError(){
 const email=$('#email').value.trim();
 if(!email)return ['#email','Informe seu e-mail.'];
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return ['#email','Confira o e-mail digitado.'];
 if(!$('#password').value)return ['#password','Informe sua senha.'];
 return null;
}

$('#login').onsubmit=async event=>{
 event.preventDefault();
 const button=$('#loginSubmit');
 if(button.disabled)return;
 const invalid=!session&&loginInputError();
 if(invalid){$('#loginError').textContent=invalid[1];$(invalid[0]).focus();return;}
 button.disabled=true;
 $('#email').readOnly=true;
 $('#password').readOnly=true;
 $('#login').setAttribute('aria-busy','true');
 $('#loginError').textContent='';
 try{
  if(!session){
   setLoginStage('Entrando');
   const data=await raw('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email:$('#email').value.trim(),password:$('#password').value})});
   if(!data?.access_token||!data?.user)throw Error('Resposta de autenticação inválida.');
   authEpoch++;
   saveSession(data);
   $('#password').value='';
   $('#password').required=false;
  }else{
   setLoginStage('Verificando sua sessão');
   await refreshSession();
  }
  await openPanel();
 }catch(error){
  if(session&&!(error.status>=400&&error.status<500)){
   keepSessionForRetry('Não foi possível verificar sua sessão agora. Tente acessar novamente.');
  }else showLogin(loginFailureMessage(error));
 }finally{finishLoginWait();}
};
$('#loginSwitchAccount').onclick=()=>{showLogin();$('#password').value='';$('#email').focus();};

async function signOut(){
 const token=session?.access_token;
 showLogin();
 $('#password').value='';
 setPasswordVisible(false);
 $('#email').focus();
 if(token)try{await raw('/auth/v1/logout',{method:'POST',headers:{Authorization:'Bearer '+token}})}catch{/* The local session is already cleared. */}
}

$('#logout').onclick=signOut;
$('#topLogout').onclick=signOut;

async function restoreSession(){
 const stored=authStore.get();
 if(!stored)return;
 const button=$('#loginSubmit');
 button.disabled=true;
 setLoginStage('Verificando sua sessão');
 try{session=JSON.parse(stored);await refreshSession();
 const user=await raw('/auth/v1/user',{headers:{Authorization:'Bearer '+session.access_token}});session.user=user;saveSession(session);await openPanel();
 }catch(error){
  if(session&&isConnectionFailure(error)||session&&error.status>=500)keepSessionForRetry('Sua sessão está salva. Tente acessar novamente quando o serviço responder.');
  else showLogin('Entre novamente para acessar o sistema.');
 }finally{finishLoginWait();}
}
if(typeof window.addEventListener==='function')window.addEventListener('storage',event=>{
 if(event.key!==storageKey)return;
 if(!event.newValue&&authenticated)showLogin('Você saiu da conta em outra aba.');
 else if(event.newValue&&authenticated){try{session=JSON.parse(event.newValue)}catch{}}
});
// Discard credentials from versions that did not distinguish Supabase projects.
sessionStorage.removeItem('sb-session');
restoreSession();
setInterval(()=>{if(cloudSyncVisible()&&!loadingCloud)loadCloud();},5000);
document.addEventListener('visibilitychange',()=>{if(cloudSyncVisible())loadCloud();});

setInterval(()=>{if(authenticated&&document.visibilityState!=='hidden')refreshMyAccess().catch(()=>{});},15000);

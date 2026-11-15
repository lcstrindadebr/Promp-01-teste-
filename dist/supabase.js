// All data uses Supabase. The browser receives only a publishable/anon key.
const sb=window.SUPABASE_CONFIG;
const storageKey='apoiarcred-auth:'+sb.url;
let currentAccess=null,accessRefreshing=false,accessCheckedAt=0;
let session=null,authenticated=false,refreshing=null,loadingCloud=false,authEpoch=0;
const statusNames={aguardando:'Aguardando',processando:'Processando',concluida:'Concluída',nao_localizado:'Não é cliente',nao_cliente:'Não é cliente',ja_vendeu:'Já vendeu',nao_encontrado:'Não encontrado',erro:'Erro',revisao:'Revisão',interrompida:'Consulta interrompida'};
function showLogin(message=''){
 $('#password').required=true;$('#loginSubmit').textContent='Entrar';$('#loginSwitchAccount').hidden=true;
 digimaisCampaignUpload=null;authenticated=false;session=null;currentAccess=null;accessRefreshing=false;accessCheckedAt=0;authEpoch++;if(typeof resetPartnerSettings==='function')resetPartnerSettings();if(typeof resetApiSettings==='function')resetApiSettings();if(typeof resetWebhooks==='function')resetWebhooks();if(typeof resetTjbaSettings==='function')resetTjbaSettings();importGeneration++;readingImport=false;importError='';if(typeof resetAmigoz==='function')resetAmigoz();if(typeof resetMonitoring==='function')resetMonitoring();cloudSnapshot=null;cloudRows.clear();cloudLoadAgain=false;cloudSyncErrorAt=0;cloudSyncRetryAt=0;cloudSyncFailures=0;records=[];pending=[];campaigns=[];activeCampaign=null;retryingCampaign=false;$('#campaignName').value='';navigate("home");
 $('#consultationLogPanel').open=false;$('#consultationLogRobot').value='';sessionStorage.removeItem(storageKey);$('#appShell').hidden=true;$('#loginPage').hidden=false;
 $('#loginStatus').textContent='';$('#loginError').textContent=message;$('#preview').classList.add('hide');$('#file').value='';$('#import').disabled=true;render();
}
function saveSession(data){session={...data,expires_at:data.expires_at||Math.floor(Date.now()/1000)+data.expires_in};sessionStorage.setItem(storageKey,JSON.stringify(session))}
async function raw(path,options={},timeoutMs=20000){
 const sessionRoutes={
  '/auth/v1/token?grant_type=password':'/api/session/login',
  '/auth/v1/token?grant_type=refresh_token':'/api/session/refresh',
  '/auth/v1/user':'/api/session/user',
  '/auth/v1/logout':'/api/session/logout',
  '/rest/v1/rpc/my_access':'/api/session/access'
 };
 const localRoute=sessionRoutes[path];
 const controller=new AbortController();
 const timer=setTimeout(()=>controller.abort(),localRoute?60000:timeoutMs);
 let res,text;
 try{
  res=await fetch(localRoute||sb.url+path,{...options,headers:{...(localRoute?{}:{apikey:sb.key}),'Content-Type':'application/json',...options.headers},signal:controller.signal,cache:'no-store'});
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
 const retry=service==='digimais_saldo_parcela'&&digimaisCampaignUpload?.epoch===authEpoch&&
  digimaisCampaignUpload.name===payload.p_nome&&digimaisCampaignUpload.items===items;
 if(!retry){
  const quotaError=typeof campaignImportError==='function'?campaignImportError(items.length):'';
  if(quotaError)throw Error(quotaError);
  if(typeof assertCanSubmit==='function')assertCanSubmit(service,'campaign');
 }
 let id;
 if(service==='digimais_saldo_parcela'&&items.length>100){
  if(!retry)digimaisCampaignUpload={id:crypto.randomUUID(),epoch:authEpoch,name:payload.p_nome,items,offset:0};
  const upload=digimaisCampaignUpload;
  const submitBatch=(rows)=>sbRequest('/rest/v1/rpc/save_digimais_campaign_batch',{method:'POST',
   body:JSON.stringify({p_id:upload.id,p_nome:payload.p_nome,p_total:items.length,p_items:rows})});
  try{
   while(upload.offset<items.length){
    if(upload.epoch!==authEpoch)throw Error('Sessão encerrada.');
    const rows=payload.p_items.slice(upload.offset,upload.offset+100);
    await submitBatch(rows);
    upload.offset+=rows.length;
    if(upload.offset%1000===0||upload.offset===items.length)toast(upload.offset.toLocaleString('pt-BR')+' de '+items.length.toLocaleString('pt-BR')+' leads enviados.');
   }
   if(upload.epoch!==authEpoch)throw Error('Sessão encerrada.');
   await submitBatch([]);
  }catch(error){
   throw Error('Envio interrompido após '+upload.offset.toLocaleString('pt-BR')+' leads confirmados. Mantenha a planilha selecionada e clique novamente para retomar. '+error.message);
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
async function syncCloudPages(epoch){
 const since=cloudSnapshot,buffer=[];
 let until=null,after=null;
 do{
  if(epoch!==authEpoch||!authenticated||document.visibilityState==='hidden')return;
  const page=await sbRequest('/rest/v1/rpc/painel_consultas_sync',{
   method:'POST',body:JSON.stringify({p_since:since,p_until:until,p_after:after})
  });
  if(epoch!==authEpoch||!authenticated||document.visibilityState==='hidden')return;
  until=page.snapshot;
  buffer.push(...page.rows);
  if(page.next&&after&&page.next<=after)throw Error('A paginação da sincronização não avançou.');
  after=page.next;
 }while(after);
 cloudSnapshot=until;
 if(!buffer.length&&since!==null)return;
 for(const entry of buffer){
  if(entry.excluido||(!entry.origem.endsWith('_jobs')&&entry.dados.tipo!=='campanha')){
   cloudRows.delete(entry.chave);
   continue;
  }
  cloudRows.set(entry.chave,{kind:entry.origem.endsWith('_jobs')?'job':'campaign',
   row:entry.origem.endsWith('_jobs')?normalizeCloudRow(entry.dados):entry.dados});
 }
 const newest=(a,b)=>b.created_at.localeCompare(a.created_at)||b.id.localeCompare(a.id);
 const entries=[...cloudRows.values()];
 const nextCampaigns=entries.filter(e=>e.kind==='campaign').map(e=>e.row).sort(newest);
 if(!campaigns.length&&nextCampaigns.length&&!$('#campaignName').value&&!pending.length)$('#newCampaignPanel').open=false;
 campaigns=nextCampaigns;
 records=entries.filter(e=>e.kind==='job').map(e=>e.row).sort(newest);
 render();
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
  await refreshMyAccess(true);
  if(epoch!==authEpoch)return;
  if(!currentAccess?.active){
   showLogin('Conta sem acesso ativo. Solicite liberação ao administrador.');
   return;
  }
 }catch(error){
  if(epoch!==authEpoch)return;
  if([400,401,403].includes(error.status)){showLogin('Sessão encerrada. Entre novamente.');return;}
  keepSessionForRetry('Sua conta foi autenticada. A validação do acesso demorou ou está indisponível. Tente acessar novamente.');
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
  const elapsed=Math.min(60,Math.floor((Date.now()-loginStarted)/1000));
  $('#loginStatus').textContent=loginStage+' · '+elapsed+' de até 60 segundos';
  $('#loginProgress').value=elapsed;
 };
 clearInterval(loginClock);
 $('#loginProgress').hidden=false;
 update();
 loginClock=setInterval(update,1000);
}
function finishLoginWait(){
 clearInterval(loginClock);loginClock=null;
 $('#loginStatus').textContent='';
 $('#loginProgress').hidden=true;
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

$('#login').onsubmit=async event=>{
 event.preventDefault();
 const button=$('#loginSubmit');
 if(button.disabled)return;
 button.disabled=true;
 $('#email').readOnly=true;
 $('#password').readOnly=true;
 $('#login').setAttribute('aria-busy','true');
 $('#loginError').textContent='';
 try{
  if(!session){
   setLoginStage('Conectando à sua conta');
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
 const stored=sessionStorage.getItem(storageKey);
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
// Discard credentials from versions that did not distinguish Supabase projects.
sessionStorage.removeItem('sb-session');
restoreSession();
setInterval(()=>{if(cloudSyncVisible()&&!loadingCloud)loadCloud();},5000);
document.addEventListener('visibilitychange',()=>{if(cloudSyncVisible())loadCloud();});

setInterval(()=>{if(authenticated&&document.visibilityState!=='hidden')refreshMyAccess().catch(()=>{});},15000);

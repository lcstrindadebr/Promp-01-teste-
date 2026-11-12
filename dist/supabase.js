// All data uses Supabase. The browser receives only a publishable/anon key.
const sb=window.SUPABASE_CONFIG;
const storageKey='apoiarcred-auth:'+sb.url;
let currentAccess=null,accessRefreshing=false,accessCheckedAt=0;
let session=null,authenticated=false,refreshing=null,loadingCloud=false,authEpoch=0;
const statusNames={aguardando:'Aguardando',processando:'Processando',concluida:'Concluída',nao_localizado:'Não é cliente',nao_cliente:'Não é cliente',ja_vendeu:'Já vendeu',nao_encontrado:'Não encontrado',erro:'Erro',revisao:'Revisão',interrompida:'Consulta interrompida'};
function showLogin(message=''){
 authenticated=false;session=null;currentAccess=null;accessRefreshing=false;accessCheckedAt=0;authEpoch++;if(typeof resetPartnerSettings==='function')resetPartnerSettings();if(typeof resetApiSettings==='function')resetApiSettings();if(typeof resetWebhooks==='function')resetWebhooks();if(typeof resetTjbaSettings==='function')resetTjbaSettings();importGeneration++;readingImport=false;importError='';if(typeof resetAmigoz==='function')resetAmigoz();if(typeof resetMonitoring==='function')resetMonitoring();cloudSnapshot=null;cloudRows.clear();cloudLoadAgain=false;cloudSyncErrorAt=0;records=[];pending=[];campaigns=[];activeCampaign=null;retryingCampaign=false;$('#campaignName').value='';navigate("home");
 $('#consultationLogPanel').open=false;$('#consultationLogRobot').value='';sessionStorage.removeItem(storageKey);$('#appShell').hidden=true;$('#loginPage').hidden=false;
 $('#loginStatus').textContent='';$('#loginError').textContent=message;$('#preview').classList.add('hide');$('#file').value='';$('#import').disabled=true;render();
}
function saveSession(data){session={...data,expires_at:data.expires_at||Math.floor(Date.now()/1000)+data.expires_in};sessionStorage.setItem(storageKey,JSON.stringify(session))}
async function raw(path,options={}){
 const res=await fetch(sb.url+path,{...options,headers:{apikey:sb.key,'Content-Type':'application/json',...options.headers},signal:AbortSignal.timeout(20000)});
 const text=await res.text();let data;try{data=text?JSON.parse(text):null}catch{throw Error('Resposta inválida do Supabase.')}
 if(!res.ok){const error=Error(data?.message||data?.msg||data?.error_description||'Falha na conexão com Supabase');error.status=res.status;throw error}return data;
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
async function createCampaign(name,items){
 if(!authenticated)throw Error('Entre na sua conta.');
 if(!name.trim()||name.trim().length>160||!items.length)throw Error('Informe o nome e selecione clientes válidos.');
 const quotaError=typeof campaignImportError==='function'?campaignImportError(items.length):'';if(quotaError)throw Error(quotaError);
 const service=selectedService();if(typeof assertCanSubmit==='function')assertCanSubmit(service,'campaign');const body={p_nome:name.trim(),p_items:items.map(r=>({nome:r.nome,cpf:r.cpf,telefone:r.telefone}))};if(service!=='tjba_margem')body.p_servico=service;else body.p_convenio=selectedConvenio();
 const id=await sbRequest('/rest/v1/rpc/'+(service==='tjba_margem'?'create_consigx_campaign':'create_consulta_campaign'),{method:'POST',body:JSON.stringify(body)});
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
 if(!authenticated||document.visibilityState==='hidden')return Promise.resolve();
 if(cloudLoadPromise){cloudLoadAgain=true;return cloudLoadPromise;}
 const epoch=authEpoch;
 loadingCloud=true;
 cloudLoadPromise=(async()=>{
  do{
   cloudLoadAgain=false;
   await syncCloudPages(epoch);
  }while(cloudLoadAgain&&epoch===authEpoch&&authenticated&&document.visibilityState!=='hidden');
 })().catch(error=>{
  if(epoch===authEpoch&&authenticated&&Date.now()-cloudSyncErrorAt>30000){
   cloudSyncErrorAt=Date.now();toast(error.message);
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
async function openPanel(){
 authenticated=true;const epoch=authEpoch;
 try{await refreshMyAccess(true);if(epoch!==authEpoch)return;if(!currentAccess?.active)throw Error('Conta sem acesso ativo. Solicite liberação ao administrador.');}
 catch(e){if(epoch===authEpoch)showLogin(e.message);return;}
 $('#loginPage').hidden=true;$('#appShell').hidden=false;$('#accountEmail').textContent=session.user.email;
 $('#authState').textContent='Conectado como '+session.user.email;$('#password').value='';setPasswordVisible(false);$('#loginStatus').textContent='';$('#loginError').textContent='';loadCloud();
 if(typeof applyAccessUi==='function')applyAccessUi();
 if(typeof loadAmigozSettings==='function')loadAmigozSettings();if(typeof loadTjbaSettings==='function')loadTjbaSettings();
}

function setPasswordVisible(visible){
 const password=$('#password');
 const toggle=$('#togglePassword');
 password.type=visible?'text':'password';
 toggle.textContent=visible?'Ocultar':'Mostrar';
 toggle.setAttribute('aria-label',visible?'Ocultar senha':'Mostrar senha');
}

$('#togglePassword').onclick=()=>setPasswordVisible($('#password').type==='password');

$('#login').onsubmit=async e=>{
 e.preventDefault();
 const button=$('#loginSubmit');
 if(button.disabled)return;
 button.disabled=true;
 $('#loginError').textContent='';
 $('#loginStatus').textContent='Entrando…';
 try{
  const data=await raw('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email:$('#email').value.trim(),password:$('#password').value})});
  authEpoch++;
  saveSession(data);
  await openPanel();
 }catch(e){
  showLogin(e.status===400?'E-mail ou senha inválidos. Confira também a confirmação da conta.':e.message);
 }finally{
  $('#loginStatus').textContent='';
  button.disabled=false;
 }
};

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
 $('#loginStatus').textContent='Verificando sessão…';
 try{session=JSON.parse(stored);await refreshSession();
 const user=await raw('/auth/v1/user',{headers:{Authorization:'Bearer '+session.access_token}});session.user=user;saveSession(session);await openPanel();
 }catch{showLogin('Entre novamente para acessar o sistema.')}finally{button.disabled=false;$('#loginStatus').textContent='';}
}
// Discard credentials from versions that did not distinguish Supabase projects.
sessionStorage.removeItem('sb-session');
restoreSession();
setInterval(()=>{if(cloudSyncVisible()&&!loadingCloud)loadCloud();},5000);
document.addEventListener('visibilitychange',()=>{if(cloudSyncVisible())loadCloud();});

setInterval(()=>{if(authenticated&&document.visibilityState!=='hidden')refreshMyAccess().catch(()=>{});},15000);

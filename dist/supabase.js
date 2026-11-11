// All data uses Supabase. The browser receives only a publishable/anon key.
const sb=window.SUPABASE_CONFIG;
const storageKey='apoiarcred-auth:'+sb.url;
let currentAccess=null,accessRefreshing=false,accessCheckedAt=0;
let session=null,authenticated=false,refreshing=null,loadingCloud=false,authEpoch=0;
const statusNames={aguardando:'Aguardando',processando:'Processando',concluida:'Concluída',nao_localizado:'Não é cliente',nao_cliente:'Não é cliente',ja_vendeu:'Já vendeu',nao_encontrado:'Não encontrado',erro:'Erro',revisao:'Revisão',interrompida:'Consulta interrompida'};
function showLogin(message=''){
 authenticated=false;session=null;currentAccess=null;accessRefreshing=false;accessCheckedAt=0;authEpoch++;if(typeof resetPartnerSettings==='function')resetPartnerSettings();if(typeof resetApiSettings==='function')resetApiSettings();if(typeof resetWebhooks==='function')resetWebhooks();if(typeof resetTjbaSettings==='function')resetTjbaSettings();importGeneration++;readingImport=false;importError='';if(typeof resetAmigoz==='function')resetAmigoz();if(typeof resetMonitoring==='function')resetMonitoring();records=[];pending=[];campaigns=[];activeCampaign=null;retryingCampaign=false;$('#campaignName').value='';navigate("home");
 $('#consultationLogPanel').open=false;$('#consultationLogRobot').value='';sessionStorage.removeItem(storageKey);$('#appShell').hidden=true;$('#loginPage').hidden=false;
 $('#loginError').textContent=message;$('#preview').classList.add('hide');$('#file').value='';$('#import').disabled=true;render();
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
async function loadCloud(){
 if(!authenticated||loadingCloud)return;loadingCloud=true;const epoch=authEpoch;
 try{const [digiData,digiLots,tjbaData,tjbaLots]=await Promise.all([fetchAll('/rest/v1/consulta_jobs?select=*&order=created_at.desc,id.desc'),fetchAll('/rest/v1/consulta_lotes?select=id,nome,tipo,servico,paused,auto_paused,created_at&tipo=eq.campanha&order=created_at.desc,id.desc'),fetchAll('/rest/v1/tjba_jobs?select=*&order=created_at.desc,id.desc'),fetchAll('/rest/v1/tjba_lotes?select=id,nome,tipo,servico,convenio,paused,auto_paused,created_at&tipo=eq.campanha&order=created_at.desc,id.desc')]);const data=[...digiData,...tjbaData].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at)),lots=[...digiLots,...tjbaLots].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at));if(epoch!==authEpoch)return;if(!campaigns.length&&lots.length&&!$('#campaignName').value&&!pending.length)$('#newCampaignPanel').open=false;campaigns=lots;records=data.map(r=>({...r,cpf:formatCpf(r.cpf),nome:r.nome==='CPF '+r.cpf?'CPF '+formatCpf(r.cpf):r.nome,date:r.consultado_em||r.created_at,status:statusNames[r.status]||r.status,saldo:r.saldo_liquidacao==null?null:Number(r.saldo_liquidacao),parcelas:r.total_parcelas,valorParcela:r.valor_parcela==null?null:Number(r.valor_parcela)}));render()}catch(e){if(authenticated)toast(e.message)}finally{loadingCloud=false}
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
 $('#authState').textContent='Conectado como '+session.user.email;$('#password').value='';$('#loginError').textContent='';loadCloud();
 if(typeof applyAccessUi==='function')applyAccessUi();
 if(typeof loadAmigozSettings==='function')loadAmigozSettings();if(typeof loadTjbaSettings==='function')loadTjbaSettings();
}

$('#login').onsubmit=async e=>{
 e.preventDefault();const button=$('#loginSubmit');button.disabled=true;$('#loginError').textContent='Entrando…';
 try{const data=await raw('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email:$('#email').value.trim(),password:$('#password').value})});authEpoch++;saveSession(data);await openPanel()}catch(e){showLogin(e.status===400?'E-mail ou senha inválidos. Confira também a confirmação da conta.':e.message)}finally{button.disabled=false}
};
$('#logout').onclick=async()=>{
 const token=session?.access_token;showLogin();$('#password').value='';
 if(token)try{await raw('/auth/v1/logout',{method:'POST',headers:{Authorization:'Bearer '+token}})}catch{/* The local session is already cleared. */}
};
async function restoreSession(){
 try{const stored=sessionStorage.getItem(storageKey);if(!stored)return;session=JSON.parse(stored);$('#loginError').textContent='Verificando sessão…';await refreshSession();
 const user=await raw('/auth/v1/user',{headers:{Authorization:'Bearer '+session.access_token}});session.user=user;saveSession(session);await openPanel();
 }catch{showLogin('Entre novamente para acessar o sistema.')}
}
// Discard credentials from versions that did not distinguish Supabase projects.
sessionStorage.removeItem('sb-session');
restoreSession();setInterval(loadCloud,2000);

setInterval(()=>{if(authenticated&&document.visibilityState!=='hidden')refreshMyAccess().catch(()=>{});},15000);

const partnerServices=[['digimais_saldo_parcela','Digi+ · Saldo e parcela'],['tjba_margem','ConsigX · Margem']];
let partnersList=[],partnerSaving=false,applyingAccess=false;
function hasIntegrationAccess(){return !!(currentAccess?.active&&(currentAccess.role==='admin'||currentAccess.allow_integrations===true));}
function accessRule(service){return currentAccess?.services?.find(r=>r.id===service);}
const campaignFileLimit=11000;
const quotaNumber=new Intl.NumberFormat('pt-BR');
function sharedQuotaText(access){
 if(!access.shared_quota)return '';
 return access.daily_limit==null?'Consultas ilimitadas':`${quotaNumber.format(access.remaining)} de ${quotaNumber.format(access.daily_limit)} consultas disponíveis hoje`;
}
function campaignImportLimit(){
 if(currentAccess?.trial_expired)return 0;
 return Math.min(campaignFileLimit,currentAccess?.shared_quota?(currentAccess.remaining??campaignFileLimit):campaignFileLimit);
}
function campaignImportError(count){
 if(!count)return '';
 if(currentAccess?.trial_expired)return 'Seu período de teste terminou.';
 const max=campaignImportLimit();
 return count>max?`A planilha tem ${quotaNumber.format(count)} leads válidos. Você pode enviar até ${quotaNumber.format(max)} agora.`:'';
}
function assertCanSubmit(service,mode){
 if(!currentAccess?.active)throw Error('Não foi possível confirmar seu acesso. Entre novamente.');
 if(currentAccess.role==='admin')return;
 if(currentAccess.trial_expired)throw Error('Seu período de teste terminou. Solicite a renovação ao administrador.');
 if(currentAccess.shared_quota&&currentAccess.remaining===0)throw Error('Limite diário atingido. Renova à meia-noite no horário de Brasília.');
 const r=accessRule(service);if(!r?.enabled)throw Error('Este tipo de higienização não está liberado para sua conta.');
 if(mode==='campaign'&&!r.allow_campaign)throw Error('Campanhas não estão habilitadas para este tipo de higienização.');
 if(mode==='individual'&&(!r.allow_individual||(!currentAccess.shared_quota&&r.daily_limit===0)))throw Error('Consultas individuais não estão habilitadas para este tipo.');
 if(mode==='individual'&&!currentAccess.shared_quota&&r.remaining<=0)throw Error('Limite diário atingido. Renova à meia-noite no horário de Brasília.');
}
const quotaBox=document.createElement('div');quotaBox.id='partnerQuota';quotaBox.className='partner-quota';$('#single').before(quotaBox);
const quotaBanner=document.createElement('div');
quotaBanner.className='partner-quota partner-quota-banner';quotaBanner.hidden=true;quotaBanner.setAttribute('aria-label','Aviso de acesso');
quotaBanner.innerHTML='<div role="status"></div><button type="button" aria-label="Fechar aviso">×</button>';
document.querySelector('#appShell main').prepend(quotaBanner);
const quotaNoticeKey=access=>'apoiarcred-quota-dismissed:'+access.user_id;
quotaBanner.querySelector('button').onclick=()=>{
 if(currentAccess?.day)sessionStorage.setItem(quotaNoticeKey(currentAccess),currentAccess.day);
 quotaBanner.hidden=true;
};
const importQuota=document.createElement('p');
importQuota.className='muted';$('#file').before(importQuota);
function updateQuotaNotice(){
 const a=currentAccess,trial=a.trial_until?(a.trial_expired?'Seu período de teste terminou':a.trial_days_left===1?'Hoje é o último dia do seu teste':`Você tem mais ${a.trial_days_left} dias de teste`):'';
 const quota=a.trial_expired?'':sharedQuotaText(a);
 quotaBanner.firstElementChild.textContent=[trial,(a.daily_limit!=null||trial)?quota:''].filter(Boolean).join(' · ');
 quotaBanner.hidden=!quotaBanner.firstElementChild.textContent||sessionStorage.getItem(quotaNoticeKey(a))===a.day;
 importQuota.textContent=a.trial_expired?'Seu período de teste terminou.':campaignImportLimit()===0?'Você usou todas as consultas de hoje. A cota renova à meia-noite, no horário de Brasília.':`Até ${quotaNumber.format(campaignImportLimit())} leads por planilha${a.shared_quota&&a.daily_limit!=null?' · '+quota:''}.`;
 syncImportButton();
}
function applyAccessUi(){
 if(typeof syncCrmResetAccess==='function')syncCrmResetAccess();
 if(applyingAccess||!currentAccess)return;applyingAccess=true;
 try{
 const admin=currentAccess.role==='admin'&&currentAccess.active,rules=currentAccess.services||[];
 const canCampaign=admin||currentAccess.active&&rules.some(r=>r.enabled&&r.allow_campaign);
 document.querySelector('[data-consultation="campaigns"]').hidden=!canCampaign;
 for(const id of ['robots','partners','minio']){$('#settings-tab-'+id).hidden=!admin;if(!admin&&!$('#settings-'+id).hidden)switchSettings('account');}
 const integrationsAllowed=hasIntegrationAccess();
 $('#settings-tab-integrations').hidden=!integrationsAllowed;
 $('#settings-account .technical-settings').hidden=!admin;
 if(!admin)$('#settings-account .technical-settings').open=false;
 if(!integrationsAllowed){if(!$('#settings-integrations').hidden)switchSettings('account');if(typeof clearNewApiToken==='function')clearNewApiToken();if(typeof whClearSecret==='function')whClearSecret();}
 $('#settings-tab-operation').hidden=!admin&&!accessRule('tjba_margem')?.enabled;
 if($('#settings-tab-operation').hidden&&!$('#settings-operation').hidden)switchSettings('account');
 const selector=$('#serviceSelect');let first=null;
 for(const option of selector.options){const r=accessRule(option.value);option.disabled=!currentAccess.active||!admin&&(!r?.enabled||(currentPage==='campaigns'&&!r.allow_campaign));option.hidden=option.disabled;if(!option.disabled&&!first)first=option.value;}
 if(first&&selector.selectedOptions[0]?.disabled){selector.value=first;selector.onchange?.();}
 const r=accessRule(selector.value),available=currentAccess.active&&(admin||r?.enabled);
 const individualAllowed=admin||(available&&r.allow_individual&&!currentAccess.trial_expired&&(currentAccess.shared_quota?currentAccess.remaining!==0:r.remaining>0));
 $('#single').querySelector('button[type="submit"]').disabled=!individualAllowed;
 $('#newCampaignPanel').hidden=!canCampaign;
 updateQuotaNotice();
 quotaBox.hidden=admin;
 quotaBox.innerHTML=admin?'':!available?'<strong>Nenhuma higienização liberada</strong><p>Solicite liberação ao administrador.</p>':`<div><strong>${escapeHTML(r.remaining)} de ${escapeHTML(r.daily_limit)} consultas individuais disponíveis hoje</strong><small>${escapeHTML(r.used)} utilizadas · ${escapeHTML(r.id==='tjba_margem'?'Cota compartilhada entre os convênios ConsigX':'Digi+')} · renova à meia-noite, horário de Brasília</small></div>${!r.allow_individual?'<p>Consultas individuais desabilitadas para este tipo.</p>':r.remaining<=0?'<p>Limite diário atingido.</p>':''}`;
 if(!admin&&(currentAccess.shared_quota||currentAccess.trial_expired)){
  quotaBox.textContent=currentAccess.trial_expired?'Seu período de teste terminou. O histórico continua disponível.':sharedQuotaText(currentAccess)+' · Campanhas e consultas individuais';
 }
 if(!canCampaign&&currentPage==='campaigns')navigate('home');
 }finally{applyingAccess=false;}
}
const partnerNavigate=navigate;navigate=function(page){if(page==='campaigns'&&currentAccess?.role==='partner'&&!currentAccess.services.some(r=>r.enabled&&r.allow_campaign)){toast('Campanhas não estão habilitadas para sua conta.');page='home';}partnerNavigate(page);applyAccessUi();};
const partnerServiceChange=$('#serviceSelect').onchange;$('#serviceSelect').onchange=()=>{partnerServiceChange?.();applyAccessUi();};
$('#settings-tab-partners').hidden=true;
$('#settings-partners').innerHTML=`<section class="card partner-admin"><div class="heading"><div><span class="section-kicker">ADMINISTRAÇÃO</span><h2>Acessos de parceiros</h2><p>Defina os tipos de higienização e os limites de cada parceiro.</p></div><button id="newPartner" type="button" class="primary">Novo parceiro</button></div><div class="partner-layout"><div><h3 id="partnerFormTitle">Criar parceiro</h3><form id="partnerForm"><input id="partnerEditId" type="hidden"><label class="field" for="partnerName">Nome</label><input id="partnerName" required maxlength="160" autocomplete="off"><label class="field" for="partnerEmail">E-mail de acesso</label><input id="partnerEmail" type="email" required maxlength="254" autocomplete="off"><div id="partnerPasswordField"><label class="field" for="partnerPassword">Senha inicial</label><input id="partnerPassword" type="password" minlength="8" maxlength="256" autocomplete="new-password" required><small>Definida por você. A senha não será exibida nem guardada no cadastro do parceiro.</small></div><label class="partner-check"><input id="partnerActive" type="checkbox" checked> Acesso ativo para novas solicitações</label><h3>Integrações</h3><label class="partner-check"><input id="partnerIntegrations" type="checkbox"> Liberar integrações (API e webhooks)</label><p class="muted">Desativar bloqueia tokens e novos envios de webhook, incluindo os pendentes. Um envio já em andamento pode terminar. As consultas do painel continuam conforme as permissões abaixo.</p><h3>Validade e cota</h3><label class="field" for="partnerAccessType">Tipo de acesso</label><select id="partnerAccessType"><option value="regular">Regular</option><option value="trial">Teste</option></select><div id="partnerTrialField" hidden><label class="field" for="partnerTrialUntil">Último dia do teste</label><input id="partnerTrialUntil" type="date"><small>O acesso a novas consultas termina à meia-noite após essa data, no horário de Brasília.</small><small id="partnerTrialDays"></small></div><label class="field" for="partnerQuotaMode">Consultas por dia</label><select id="partnerQuotaMode"><option value="limited">Cota diária compartilhada</option><option value="unlimited">Ilimitadas</option><option value="legacy" hidden>Cotas anteriores por serviço</option></select><div id="partnerSharedField"><label class="field" for="partnerSharedLimit">Limite diário do usuário</label><input id="partnerSharedLimit" type="number" min="1" max="100000" step="1" value="100"><small>Campanhas e consultas individuais usam o mesmo saldo.</small></div><h3>Permissões por higienização</h3><label class="partner-check"><input id="partnerAmigoz" type="checkbox"> Permitir consultas individuais Amigoz</label><p class="muted">Saque complementar e margem usam a cota diária compartilhada deste parceiro.</p>${partnerServices.map(([id,label])=>`<fieldset class="partner-rule" data-partner-service="${id}"><legend>${label}</legend><label class="partner-check"><input id="partnerEnabled-${id}" type="checkbox"> Liberar este tipo</label><label class="partner-check"><input id="partnerIndividual-${id}" type="checkbox"> Permitir consultas individuais</label><label class="field legacy-quota" for="partnerLimit-${id}">Consultas individuais por dia</label><input class="legacy-quota" id="partnerLimit-${id}" type="number" min="0" max="100000" step="1" value="0" required><label class="partner-check"><input id="partnerCampaign-${id}" type="checkbox"> Permitir campanhas</label></fieldset>`).join('')}<p class="muted">Alterações valem para novos envios e retomadas. Consultas já aceitas continuam na fila. Excluir registros não devolve cota.</p><div class="actions"><button id="savePartner" class="primary">Criar acesso</button><button id="cancelPartnerEdit" type="button">Limpar</button></div></form><p id="partnerAdminStatus" role="status"></p></div><div><div class="heading"><h3>Parceiros cadastrados</h3><button id="reloadPartners" type="button">Atualizar</button></div><div id="partnerList"></div></div></div></section>`;
async function partnerRequest(path,body){
 if(currentAccess?.role!=='admin')throw Error('Apenas administradores podem gerenciar parceiros.');await refreshSession();
 const response=await fetch('/api/admin/parceiros'+path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(45000)});
 let data;try{data=await response.json();}catch{throw Error('A API administrativa ainda não está disponível. Atualize a VPS pelo instalador.');}
 if(!response.ok)throw Error(data.error?.message||'Não foi possível gerenciar o parceiro.');return data;
}
function syncPartnerQuotaFields(){
 const trial=$('#partnerAccessType').value==='trial',mode=$('#partnerQuotaMode').value;
 $('#partnerTrialField').hidden=!trial;$('#partnerTrialUntil').required=trial;
 const until=$('#partnerTrialUntil').value,today=currentAccess?.day;
 const days=until&&today?Math.max(0,Math.round((Date.parse(until)-Date.parse(today))/86400000)+1):null;
 $('#partnerTrialDays').textContent=days==null?'':days===0?'Esta data já passou.':`${days} ${days===1?'dia':'dias'} contando a partir de hoje.`;
 $('#partnerSharedField').hidden=mode!=='limited';$('#partnerSharedLimit').required=mode==='limited';$('#partnerSharedLimit').disabled=mode!=='limited';
 document.querySelectorAll('.legacy-quota').forEach(el=>{el.hidden=mode!=='legacy';if(el.tagName==='INPUT')el.disabled=mode!=='legacy';});
}
$('#partnerAccessType').onchange=()=>{
 if($('#partnerAccessType').value==='trial'&&$('#partnerQuotaMode').value==='legacy')$('#partnerQuotaMode').value='limited';
 syncPartnerQuotaFields();
};$('#partnerTrialUntil').oninput=syncPartnerQuotaFields;$('#partnerQuotaMode').onchange=syncPartnerQuotaFields;
function resetPartnerSettings(){if(typeof resetMinioSettings==='function')resetMinioSettings();quotaBanner.hidden=true;partnersList=[];$('#partnerList').innerHTML='';$('#partnerAdminStatus').textContent='';clearPartnerForm();$('#settings-tab-partners').hidden=true;quotaBox.hidden=true;}
function clearPartnerForm(){
 $('#partnerEditId').value='';$('#partnerName').value='';$('#partnerEmail').value='';$('#partnerEmail').disabled=false;$('#partnerPassword').value='';$('#partnerPassword').required=true;$('#partnerPasswordField').hidden=false;$('#partnerActive').checked=true;$('#partnerIntegrations').checked=false;$('#partnerAmigoz').checked=false;
 for(const [id] of partnerServices){for(const name of ['Enabled','Individual','Campaign'])$('#partner'+name+'-'+id).checked=false;$('#partnerLimit-'+id).value=0;}
 $('#partnerAccessType').value='regular';$('#partnerTrialUntil').value='';$('#partnerQuotaMode').value='limited';$('#partnerSharedLimit').value=100;syncPartnerQuotaFields();
 $('#partnerFormTitle').textContent='Criar parceiro';$('#savePartner').textContent='Criar acesso';
}
async function loadPartners(){
 if(currentAccess?.role!=='admin')return;const epoch=authEpoch;$('#partnerAdminStatus').textContent='Carregando parceiros…';
 try{const result=await partnerRequest('');if(epoch!==authEpoch)return;partnersList=result.data;
 $('#partnerList').innerHTML=partnersList.length?partnersList.map(p=>`<article class="partner-list-item"><div class="heading"><strong>${escapeHTML(p.name)}</strong><span class="pill ${p.active?'ok':''}">${p.active?'Ativo':'Inativo'}</span></div><p>${escapeHTML(p.email)}</p><small>Integrações: ${p.allow_integrations?'liberadas':'não liberadas'}</small><small>Amigoz: ${p.allow_amigoz?'liberado':'não liberado'}</small>${p.trial_until?'<small>Teste até '+escapeHTML(p.trial_until.split('-').reverse().join('/'))+'</small>':''}${p.shared_quota?'<small>'+escapeHTML(sharedQuotaText(p.access))+'</small>':''}${p.access.services.map(r=>`<small>${escapeHTML(partnerServices.find(s=>s[0]===r.id)?.[1]||r.id)}: ${!r.enabled?'não liberado':`${r.allow_individual?(p.shared_quota?'individuais liberadas':r.used+' / '+r.daily_limit+' individuais hoje'):'sem individuais'} · ${r.allow_campaign?'campanhas liberadas':'sem campanhas'}`}</small>`).join('')}${p.members!=null?'<small>Usuários ativos: '+escapeHTML(p.members)+'</small>':''}<div class="actions"><button type="button" data-edit-partner="${escapeHTML(p.user_id)}">Editar permissões</button>${partnersList.length>1?`<button type="button" data-move-partner="${escapeHTML(p.user_id)}">Juntar a outra empresa</button>`:''}<button type="button" class="danger" data-delete-partner="${escapeHTML(p.user_id)}">Excluir parceiro</button></div></article>`).join(''):'<p class="muted">Nenhum parceiro cadastrado. Crie o primeiro acesso ao lado.</p>';
 $('#partnerAdminStatus').textContent='';
 }catch(e){if(epoch===authEpoch)$('#partnerAdminStatus').textContent=e.message;}
}
const partnerSwitchSettings=switchSettings;switchSettings=function(id){if(id==='minio'&&!minioAdmin()||id==='partners'&&currentAccess?.role!=='admin'||id==='integrations'&&!hasIntegrationAccess())return;partnerSwitchSettings(id);if(id==='partners')loadPartners();if(id==='minio')requestMinio('load');};
$('#newPartner').onclick=clearPartnerForm;$('#cancelPartnerEdit').onclick=clearPartnerForm;$('#reloadPartners').onclick=loadPartners;
$('#partnerList').onclick=e=>{if(e.target.dataset.movePartner)return movePartner(e.target.dataset.movePartner);if(e.target.dataset.deletePartner)return deletePartner(e.target.dataset.deletePartner);const id=e.target.dataset.editPartner,p=partnersList.find(p=>p.user_id===id);if(!p)return;clearPartnerForm();$('#partnerEditId').value=id;$('#partnerName').value=p.name;$('#partnerEmail').value=p.email;$('#partnerEmail').disabled=true;$('#partnerPassword').required=false;$('#partnerPasswordField').hidden=true;$('#partnerActive').checked=p.active;$('#partnerIntegrations').checked=p.allow_integrations===true;$('#partnerAmigoz').checked=p.allow_amigoz===true;
 for(const r of p.access.services){$('#partnerEnabled-'+r.id).checked=r.enabled;$('#partnerIndividual-'+r.id).checked=r.allow_individual;$('#partnerCampaign-'+r.id).checked=r.allow_campaign;$('#partnerLimit-'+r.id).value=r.daily_limit;}
 $('#partnerAccessType').value=p.trial_until?'trial':'regular';$('#partnerTrialUntil').value=p.trial_until||'';$('#partnerQuotaMode').value=p.shared_quota?(p.shared_daily_limit==null?'unlimited':'limited'):'legacy';$('#partnerSharedLimit').value=p.shared_daily_limit??100;syncPartnerQuotaFields();
 $('#partnerFormTitle').textContent='Editar parceiro';$('#savePartner').textContent='Salvar permissões';$('#partnerName').focus();};
$('#partnerForm').onsubmit=async e=>{
 e.preventDefault();if(partnerSaving)return;const id=$('#partnerEditId').value,permissions=[];
 for(const [service] of partnerServices){const daily_limit=Number($('#partnerLimit-'+service).value);if(!Number.isInteger(daily_limit)||daily_limit<0||daily_limit>100000){$('#partnerAdminStatus').textContent='Use limites inteiros entre 0 e 100.000.';return;}permissions.push({service,enabled:$('#partnerEnabled-'+service).checked,allow_individual:$('#partnerIndividual-'+service).checked,allow_campaign:$('#partnerCampaign-'+service).checked,daily_limit});}
 const mode=$('#partnerQuotaMode').value,trial=$('#partnerAccessType').value==='trial';
 const allowAmigoz=$('#partnerAmigoz').checked;
 if(allowAmigoz&&mode==='legacy'){$('#partnerAdminStatus').textContent='Selecione uma cota compartilhada ou consultas ilimitadas para liberar Amigoz.';return;}
 const payload={allow_amigoz:allowAmigoz,trial_until:trial?$('#partnerTrialUntil').value:null,...(mode==='legacy'?{}:{shared_daily_limit:mode==='limited'?Number($('#partnerSharedLimit').value):null}),name:$('#partnerName').value.trim(),active:$('#partnerActive').checked,allow_integrations:$('#partnerIntegrations').checked,permissions,...(!id?{email:$('#partnerEmail').value.trim(),password:$('#partnerPassword').value}:{})};
 const epoch=authEpoch;partnerSaving=true;$('#savePartner').disabled=true;$('#partnerAdminStatus').textContent=id?'Salvando permissões…':'Criando acesso…';
 try{await partnerRequest(id?'/'+id:'',payload);if(epoch!==authEpoch)return;clearPartnerForm();await loadPartners();$('#partnerAdminStatus').textContent=id?'Permissões atualizadas.':'Parceiro criado. O acesso já pode ser feito com o e-mail e a senha definidos.';}
 catch(error){if(epoch===authEpoch)$('#partnerAdminStatus').textContent=error.message;}
 finally{$('#partnerPassword').value='';partnerSaving=false;$('#savePartner').disabled=false;}
};
applyAccessUi();

// Juntar parceiros: o responsável (e os dados dele) passa a fazer parte de outra empresa.
const partnerMoveDialog=document.createElement('dialog');partnerMoveDialog.setAttribute('aria-labelledby','partnerMoveTitle');
partnerMoveDialog.innerHTML=`<form id="partnerMoveForm"><h2 id="partnerMoveTitle">Juntar a outra empresa</h2><p id="partnerMoveText" class="muted"></p>
<label class="field" for="partnerMoveTarget">Empresa de destino</label><select id="partnerMoveTarget" required></select>
<label class="field" for="partnerMoveRole">Papel na empresa de destino</label><select id="partnerMoveRole"><option value="gestor">Gestor</option><option value="operador">Operador</option><option value="leitura">Leitura</option><option value="administrador">Administrador</option></select>
<p class="muted">Consultas, campanhas, clientes e cartões do CRM vão junto. Acessos ConsigX, Digi+ e webhooks ficam na empresa antiga, que é desativada se ficar sem usuários. Cartões em etapas que só existem na empresa antiga vão para a etapa inicial.</p>
<p id="partnerMoveStatus" role="status"></p><div class="actions"><button id="partnerMoveSave" class="primary">Juntar</button><button type="button" id="partnerMoveCancel">Cancelar</button></div></form>`;
document.body.append(partnerMoveDialog);
$('#partnerMoveCancel').onclick=()=>partnerMoveDialog.close();
function movePartner(id){
 const partner=partnersList.find(p=>p.user_id===id);if(!partner)return;
 $('#partnerMoveText').textContent=`${partner.name} (${partner.email}) passa a ser usuário da empresa escolhida.`;
 const select=$('#partnerMoveTarget');select.replaceChildren();
 for(const p of partnersList)if(p.user_id!==id&&p.active)select.add(new Option(p.name,p.user_id));
 $('#partnerMoveStatus').textContent=select.options.length?'':'Nenhuma empresa ativa para receber o parceiro.';
 $('#partnerMoveSave').disabled=!select.options.length;$('#partnerMoveForm').dataset.user=id;
 partnerMoveDialog.showModal();
}
$('#partnerMoveForm').onsubmit=async e=>{
 e.preventDefault();const epoch=authEpoch,user=e.target.dataset.user,target=$('#partnerMoveTarget');
 if(!await askConfirm(`Os usuários e os dados deste parceiro passam para a empresa ${target.selectedOptions[0]?.text}. Esta ação não tem botão de desfazer.`,{title:'Juntar à empresa?',confirmLabel:'Juntar',danger:true}))return;
 $('#partnerMoveSave').disabled=true;$('#partnerMoveStatus').textContent='Movendo dados…';
 try{
  const r=await sbRequest('/rest/v1/rpc/admin_move_member',{method:'POST',body:JSON.stringify({p_user:user,p_target_user:target.value,p_role:$('#partnerMoveRole').value})});
  if(epoch!==authEpoch)return;partnerMoveDialog.close();toast(`Parceiro movido com ${r.registros} registros.`);await loadPartners();
 }catch(error){if(epoch===authEpoch)$('#partnerMoveStatus').textContent=error.message||'Não foi possível juntar.';}
 finally{$('#partnerMoveSave').disabled=false;}
};

// Excluir parceiro: a empresa inteira, com todos os usuários e dados. Confirmação pelo nome.
const partnerDeleteDialog=document.createElement('dialog');partnerDeleteDialog.setAttribute('aria-labelledby','partnerDeleteTitle');
partnerDeleteDialog.innerHTML=`<form id="partnerDeleteForm"><h2 id="partnerDeleteTitle">Excluir parceiro</h2><p id="partnerDeleteText"></p>
<p class="muted">Apaga a empresa, todos os usuários dela e todas as consultas, campanhas, clientes, cartões, acessos e integrações. Não há como recuperar.</p>
<label class="field" for="partnerDeleteConfirm">Digite o nome da empresa para confirmar</label><input id="partnerDeleteConfirm" autocomplete="off" required>
<p id="partnerDeleteStatus" role="status"></p><div class="actions"><button id="partnerDeleteSave" class="danger">Excluir parceiro</button><button type="button" id="partnerDeleteCancel">Cancelar</button></div></form>`;
document.body.append(partnerDeleteDialog);
$('#partnerDeleteCancel').onclick=()=>partnerDeleteDialog.close();
function deletePartner(id){
 const partner=partnersList.find(p=>p.user_id===id);if(!partner)return;
 $('#partnerDeleteForm').reset();$('#partnerDeleteForm').dataset.user=id;$('#partnerDeleteForm').dataset.name=partner.name;
 $('#partnerDeleteText').textContent=`${partner.name} · ${partner.members??1} usuário(s) ativo(s).`;$('#partnerDeleteStatus').textContent='';
 partnerDeleteDialog.showModal();
}
$('#partnerDeleteForm').onsubmit=async e=>{
 e.preventDefault();const epoch=authEpoch,form=e.target,typed=$('#partnerDeleteConfirm').value.trim();
 if(typed!==form.dataset.name.trim()){$('#partnerDeleteStatus').textContent='O nome digitado não confere com o da empresa.';return;}
 $('#partnerDeleteSave').disabled=true;$('#partnerDeleteStatus').textContent='Excluindo…';
 try{
  const r=await partnerRequest('/'+form.dataset.user+'/excluir',{confirmacao:typed});if(epoch!==authEpoch)return;
  partnerDeleteDialog.close();if($('#partnerEditId').value===form.dataset.user)clearPartnerForm();
  await loadPartners();if(epoch===authEpoch)$('#partnerAdminStatus').textContent=`Parceiro ${r.data.empresa} excluído: ${r.data.usuarios.length} usuário(s) e ${r.data.registros} registros.`;
 }catch(error){if(epoch===authEpoch)$('#partnerDeleteStatus').textContent=error.message;}
 finally{$('#partnerDeleteSave').disabled=false;}
};

const partnerDigiCard=document.createElement('section');
partnerDigiCard.className='card';
partnerDigiCard.innerHTML=`<h2>Consulta Digi+ pela API</h2><form id="partnerDigiForm"><label class="field" for="partnerDigiUser">Parceiro</label><select id="partnerDigiUser" required></select><label class="portal-enable"><input id="partnerDigiEnabled" type="checkbox"> Liberar consultas pela API Digi+</label><label class="field" for="partnerDigiMax">Consultas simultâneas permitidas</label><input id="partnerDigiMax" type="number" min="1" max="100" step="1" value="1" required><p>Usuários atuais e novos começam sem liberação. A configuração vale para consultas individuais e campanhas, respeitando as permissões do serviço. Ao revogar, as consultas em andamento terminam e as próximas usam o robô. O limite total da VPS é compartilhado entre as contas.</p><button id="partnerDigiSave" class="primary" disabled>Salvar liberação</button></form><p id="partnerDigiStatus" role="status"></p>`;
$('#settings-partners').append(partnerDigiCard);
let partnerDigiUsers=[],partnerDigiBusy=false;
function renderPartnerDigiSelection(){
 const user=partnerDigiUsers.find(row=>row.user_id===$('#partnerDigiUser').value);
 $('#partnerDigiEnabled').checked=user?.enabled===true;
 $('#partnerDigiMax').value=user?.max_concurrency||1;
 $('#partnerDigiSave').disabled=!user||partnerDigiBusy;
}
async function loadPartnerDigiAccess(){
 if(!authenticated||!currentAccess?.active||currentAccess.role!=='admin')return;
 const epoch=authEpoch;
 $('#partnerDigiSave').disabled=true;
 try{
  const rows=await sbRequest('/rest/v1/rpc/admin_digimais_access',{method:'POST',body:'{}'});
  if(epoch!==authEpoch)return;
  partnerDigiUsers=rows;
  const selected=$('#partnerDigiUser').value;
  $('#partnerDigiUser').innerHTML=rows.map(row=>'<option value="'+escapeHTML(row.user_id)+'">'+escapeHTML(row.name+' · '+row.email+(row.enabled?' · API liberada':' · API desativada'))+'</option>').join('');
  if(rows.some(row=>row.user_id===selected))$('#partnerDigiUser').value=selected;
  renderPartnerDigiSelection();
 }catch(error){if(epoch===authEpoch)$('#partnerDigiStatus').textContent=error.message||'Não foi possível carregar as liberações.';}
}
$('#partnerDigiUser').onchange=renderPartnerDigiSelection;
$('#partnerDigiForm').onsubmit=async event=>{
 event.preventDefault();
 if(partnerDigiBusy||currentAccess?.role!=='admin')return;
 const user=$('#partnerDigiUser').value,max=Number($('#partnerDigiMax').value);
 if(!user||!Number.isInteger(max)||max<1||max>100)return;
 const epoch=authEpoch;
 partnerDigiBusy=true;$('#partnerDigiSave').disabled=true;
 try{
  await sbRequest('/rest/v1/rpc/admin_digimais_access',{method:'POST',body:JSON.stringify({p_user:user,p_enabled:$('#partnerDigiEnabled').checked,p_max:max})});
  if(epoch!==authEpoch)return;
  $('#partnerDigiStatus').textContent='Liberação salva.';
  await loadPartnerDigiAccess();
 }catch(error){if(epoch===authEpoch)$('#partnerDigiStatus').textContent=error.message||'Não foi possível salvar.';}
 finally{partnerDigiBusy=false;if(epoch===authEpoch)renderPartnerDigiSelection();}
};
const partnerDigiLoadPartners=loadPartners;
loadPartners=async function(){await partnerDigiLoadPartners();await loadPartnerDigiAccess();};

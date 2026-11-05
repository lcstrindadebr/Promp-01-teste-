const partnerServices=[['digimais_saldo_parcela','Digi+ · Saldo e parcela'],['tjba_margem','ConsigX · Margem']];
let partnersList=[],partnerSaving=false,applyingAccess=false;
function hasIntegrationAccess(){return !!(currentAccess?.active&&(currentAccess.role==='admin'||currentAccess.allow_integrations===true));}
function accessRule(service){return currentAccess?.services?.find(r=>r.id===service);}
function assertCanSubmit(service,mode){
 if(!currentAccess?.active)throw Error('Não foi possível confirmar seu acesso. Entre novamente.');
 if(currentAccess.role==='admin')return;
 const r=accessRule(service);if(!r?.enabled)throw Error('Este tipo de higienização não está liberado para sua conta.');
 if(mode==='campaign'&&!r.allow_campaign)throw Error('Campanhas não estão habilitadas para este tipo de higienização.');
 if(mode==='individual'&&(!r.allow_individual||r.daily_limit===0))throw Error('Consultas individuais não estão habilitadas para este tipo.');
 if(mode==='individual'&&r.remaining<=0)throw Error('Limite diário atingido. Renova à meia-noite no horário de Brasília.');
}
const quotaBox=document.createElement('div');quotaBox.id='partnerQuota';quotaBox.className='partner-quota';$('#single').before(quotaBox);
function applyAccessUi(){
 if(applyingAccess||!currentAccess)return;applyingAccess=true;
 try{
 const admin=currentAccess.role==='admin'&&currentAccess.active,rules=currentAccess.services||[];
 const canCampaign=admin||currentAccess.active&&rules.some(r=>r.enabled&&r.allow_campaign);
 document.querySelector('nav [data-page="campaigns"]').hidden=!canCampaign;
 for(const id of ['robots','partners']){$('#settings-tab-'+id).hidden=!admin;if(!admin&&!$('#settings-'+id).hidden)switchSettings('account');}
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
 const individualAllowed=admin||(available&&r.allow_individual&&r.remaining>0);
 $('#single').querySelector('button[type="submit"]').disabled=!individualAllowed;
 $('#newCampaignPanel').hidden=!canCampaign;
 quotaBox.hidden=admin;
 quotaBox.innerHTML=admin?'':!available?'<strong>Nenhuma higienização liberada</strong><p>Solicite liberação ao administrador.</p>':`<div><strong>${escapeHTML(r.remaining)} de ${escapeHTML(r.daily_limit)} consultas individuais disponíveis hoje</strong><small>${escapeHTML(r.used)} utilizadas · ${escapeHTML(r.id==='tjba_margem'?'Cota compartilhada entre os convênios ConsigX':'Digi+')} · renova à meia-noite, horário de Brasília</small></div>${!r.allow_individual?'<p>Consultas individuais desabilitadas para este tipo.</p>':r.remaining<=0?'<p>Limite diário atingido.</p>':''}`;
 if(!canCampaign&&currentPage==='campaigns')navigate('home');
 }finally{applyingAccess=false;}
}
const partnerNavigate=navigate;navigate=function(page){if(page==='campaigns'&&currentAccess?.role==='partner'&&!currentAccess.services.some(r=>r.enabled&&r.allow_campaign)){toast('Campanhas não estão habilitadas para sua conta.');page='home';}partnerNavigate(page);applyAccessUi();};
const partnerServiceChange=$('#serviceSelect').onchange;$('#serviceSelect').onchange=()=>{partnerServiceChange?.();applyAccessUi();};
$('#settings-tab-partners').hidden=true;
$('#settings-partners').innerHTML=`<section class="card partner-admin"><div class="heading"><div><span class="section-kicker">ADMINISTRAÇÃO</span><h2>Acessos de parceiros</h2><p>Defina os tipos de higienização e os limites de cada parceiro.</p></div><button id="newPartner" type="button" class="primary">Novo parceiro</button></div><div class="partner-layout"><div><h3 id="partnerFormTitle">Criar parceiro</h3><form id="partnerForm"><input id="partnerEditId" type="hidden"><label class="field" for="partnerName">Nome</label><input id="partnerName" required maxlength="160" autocomplete="off"><label class="field" for="partnerEmail">E-mail de acesso</label><input id="partnerEmail" type="email" required maxlength="254" autocomplete="off"><div id="partnerPasswordField"><label class="field" for="partnerPassword">Senha inicial</label><input id="partnerPassword" type="password" minlength="8" maxlength="256" autocomplete="new-password" required><small>Definida por você. A senha não será exibida nem guardada no cadastro do parceiro.</small></div><label class="partner-check"><input id="partnerActive" type="checkbox" checked> Acesso ativo para novas solicitações</label><h3>Integrações</h3><label class="partner-check"><input id="partnerIntegrations" type="checkbox"> Liberar integrações (API e webhooks)</label><p class="muted">Desativar bloqueia tokens e novos envios de webhook, incluindo os pendentes. Um envio já em andamento pode terminar. As consultas do painel continuam conforme as permissões abaixo.</p><h3>Permissões por higienização</h3>${partnerServices.map(([id,label])=>`<fieldset class="partner-rule" data-partner-service="${id}"><legend>${label}</legend><label class="partner-check"><input id="partnerEnabled-${id}" type="checkbox"> Liberar este tipo</label><label class="partner-check"><input id="partnerIndividual-${id}" type="checkbox"> Permitir consultas individuais</label><label class="field" for="partnerLimit-${id}">Consultas individuais por dia</label><input id="partnerLimit-${id}" type="number" min="0" max="100000" step="1" value="0" required><label class="partner-check"><input id="partnerCampaign-${id}" type="checkbox"> Permitir campanhas</label></fieldset>`).join('')}<p class="muted">ConsigX usa uma cota conjunta para todos os seus convênios. Campanhas, quando liberadas, não consomem a cota individual. Cada nova tentativa individual consome uma consulta.</p><p class="muted">Alterações valem para novos envios e retomadas. Consultas já aceitas continuam na fila. Excluir registros não devolve cota.</p><div class="actions"><button id="savePartner" class="primary">Criar acesso</button><button id="cancelPartnerEdit" type="button">Limpar</button></div></form><p id="partnerAdminStatus" role="status"></p></div><div><div class="heading"><h3>Parceiros cadastrados</h3><button id="reloadPartners" type="button">Atualizar</button></div><div id="partnerList"></div></div></div></section>`;
async function partnerRequest(path,body){
 if(currentAccess?.role!=='admin')throw Error('Apenas administradores podem gerenciar parceiros.');await refreshSession();
 const response=await fetch('/api/admin/parceiros'+path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(45000)});
 let data;try{data=await response.json();}catch{throw Error('A API administrativa ainda não está disponível. Atualize a VPS pelo instalador.');}
 if(!response.ok)throw Error(data.error?.message||'Não foi possível gerenciar o parceiro.');return data;
}
function resetPartnerSettings(){partnersList=[];$('#partnerList').innerHTML='';$('#partnerAdminStatus').textContent='';clearPartnerForm();$('#settings-tab-partners').hidden=true;quotaBox.hidden=true;}
function clearPartnerForm(){
 $('#partnerEditId').value='';$('#partnerName').value='';$('#partnerEmail').value='';$('#partnerEmail').disabled=false;$('#partnerPassword').value='';$('#partnerPassword').required=true;$('#partnerPasswordField').hidden=false;$('#partnerActive').checked=true;$('#partnerIntegrations').checked=false;
 for(const [id] of partnerServices){for(const name of ['Enabled','Individual','Campaign'])$('#partner'+name+'-'+id).checked=false;$('#partnerLimit-'+id).value=0;}
 $('#partnerFormTitle').textContent='Criar parceiro';$('#savePartner').textContent='Criar acesso';
}
async function loadPartners(){
 if(currentAccess?.role!=='admin')return;const epoch=authEpoch;$('#partnerAdminStatus').textContent='Carregando parceiros…';
 try{const result=await partnerRequest('');if(epoch!==authEpoch)return;partnersList=result.data;
 $('#partnerList').innerHTML=partnersList.length?partnersList.map(p=>`<article class="partner-list-item"><div class="heading"><strong>${escapeHTML(p.name)}</strong><span class="pill ${p.active?'ok':''}">${p.active?'Ativo':'Inativo'}</span></div><p>${escapeHTML(p.email)}</p><small>Integrações: ${p.allow_integrations?'liberadas':'não liberadas'}</small>${p.access.services.map(r=>`<small>${escapeHTML(partnerServices.find(s=>s[0]===r.id)?.[1]||r.id)}: ${!r.enabled?'não liberado':`${r.allow_individual?r.used+' / '+r.daily_limit+' individuais hoje':'sem individuais'} · ${r.allow_campaign?'campanhas liberadas':'sem campanhas'}`}</small>`).join('')}<button type="button" data-edit-partner="${escapeHTML(p.user_id)}">Editar permissões</button></article>`).join(''):'<p class="muted">Nenhum parceiro cadastrado. Crie o primeiro acesso ao lado.</p>';
 $('#partnerAdminStatus').textContent='';
 }catch(e){if(epoch===authEpoch)$('#partnerAdminStatus').textContent=e.message;}
}
const partnerSwitchSettings=switchSettings;switchSettings=function(id){if(id==='partners'&&currentAccess?.role!=='admin'||id==='integrations'&&!hasIntegrationAccess())return;partnerSwitchSettings(id);if(id==='partners')loadPartners();};
$('#newPartner').onclick=clearPartnerForm;$('#cancelPartnerEdit').onclick=clearPartnerForm;$('#reloadPartners').onclick=loadPartners;
$('#partnerList').onclick=e=>{const id=e.target.dataset.editPartner,p=partnersList.find(p=>p.user_id===id);if(!p)return;clearPartnerForm();$('#partnerEditId').value=id;$('#partnerName').value=p.name;$('#partnerEmail').value=p.email;$('#partnerEmail').disabled=true;$('#partnerPassword').required=false;$('#partnerPasswordField').hidden=true;$('#partnerActive').checked=p.active;$('#partnerIntegrations').checked=p.allow_integrations===true;
 for(const r of p.access.services){$('#partnerEnabled-'+r.id).checked=r.enabled;$('#partnerIndividual-'+r.id).checked=r.allow_individual;$('#partnerCampaign-'+r.id).checked=r.allow_campaign;$('#partnerLimit-'+r.id).value=r.daily_limit;}
 $('#partnerFormTitle').textContent='Editar parceiro';$('#savePartner').textContent='Salvar permissões';$('#partnerName').focus();};
$('#partnerForm').onsubmit=async e=>{
 e.preventDefault();if(partnerSaving)return;const id=$('#partnerEditId').value,permissions=[];
 for(const [service] of partnerServices){const daily_limit=Number($('#partnerLimit-'+service).value);if(!Number.isInteger(daily_limit)||daily_limit<0||daily_limit>100000){$('#partnerAdminStatus').textContent='Use limites inteiros entre 0 e 100.000.';return;}permissions.push({service,enabled:$('#partnerEnabled-'+service).checked,allow_individual:$('#partnerIndividual-'+service).checked,allow_campaign:$('#partnerCampaign-'+service).checked,daily_limit});}
 const payload={name:$('#partnerName').value.trim(),active:$('#partnerActive').checked,allow_integrations:$('#partnerIntegrations').checked,permissions,...(!id?{email:$('#partnerEmail').value.trim(),password:$('#partnerPassword').value}:{})};
 const epoch=authEpoch;partnerSaving=true;$('#savePartner').disabled=true;$('#partnerAdminStatus').textContent=id?'Salvando permissões…':'Criando acesso…';
 try{await partnerRequest(id?'/'+id:'',payload);if(epoch!==authEpoch)return;clearPartnerForm();await loadPartners();$('#partnerAdminStatus').textContent=id?'Permissões atualizadas.':'Parceiro criado. O acesso já pode ser feito com o e-mail e a senha definidos.';}
 catch(error){if(epoch===authEpoch)$('#partnerAdminStatus').textContent=error.message;}
 finally{$('#partnerPassword').value='';partnerSaving=false;$('#savePartner').disabled=false;}
};
applyAccessUi();

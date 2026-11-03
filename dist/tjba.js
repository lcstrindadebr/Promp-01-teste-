const convenioLabels={tjba:'TJBA',dpeba:'DPEBA',embasa:'EMBASA',saeb:'Governo BA · SAEB',suprev:'SUPREV'};
function selectedConvenio(){return $('#convenioSelect')?.value||'tjba';}
function convenioLabel(value){return convenioLabels[value||'tjba']||'Convênio desconhecido';}
// Browser reads only credential metadata; administrative inspection stays in SQL.
let tjbaConfigured=false;
const tjbaStatusLabels={consultado:'Consultado',nao_encontrado:'Não encontrado',revisao_matricula:'Revisão de matrícula',revisao_margens:'Revisão de margens',sessao_expirada:'Acesso ao portal',erro:'Erro'};
function resetTjbaSettings(){tjbaConfigured=false;$('#tjbaUsername').value='';$('#tjbaPassword').value='';$('#tjbaEnabled').checked=false;$('#tjbaCredentialStatus').textContent='';$('#tjbaHistoryPanel').hidden=true;$('#tjbaHistoryRows').innerHTML='';}
async function loadTjbaSettings(){
 const epoch=authEpoch;try{const info=await sbRequest('/rest/v1/rpc/tjba_credentials_status',{method:'POST',body:'{}'});if(epoch!==authEpoch)return;
 tjbaConfigured=Boolean(info.configured);$('#tjbaUsername').value=info.username||'';$('#tjbaEnabled').checked=Boolean(info.enabled);$('#tjbaCredentialStatus').textContent=info.configured?(info.enabled?'Acesso salvo · consultas habilitadas':'Acesso salvo · aguardando homologação'):'Cadastre seu acesso ao portal.';
 if(info.configured)$('#tjbaCredentialStatus').textContent+=' · Versão da senha: '+(info.password_version??0)+(info.password_changed_at?' · Alterada em '+new Date(info.password_changed_at).toLocaleString('pt-BR'):' · Data de alteração anterior não registrada');
 }catch{if(epoch===authEpoch)$('#tjbaCredentialStatus').textContent='Não foi possível carregar o acesso TJBA. Verifique a atualização do banco.';}
}
$('#tjbaCredentials').onsubmit=async e=>{
 e.preventDefault();const epoch=authEpoch;let password=$('#tjbaPassword').value;const username=$('#tjbaUsername').value.trim(),enabled=$('#tjbaEnabled').checked;$('#tjbaPassword').value='';$('#saveTjba').disabled=true;
 try{
 if(!username||(!tjbaConfigured&&!password))throw Error('missing');
 await sbRequest('/rest/v1/rpc/save_tjba_credentials',{method:'POST',body:JSON.stringify({p_username:username,p_password:password,p_enabled:enabled})});password='';
 if(epoch!==authEpoch)return;tjbaConfigured=true;await loadTjbaSettings();
 }catch{if(epoch===authEpoch)$('#tjbaCredentialStatus').textContent='Não foi possível salvar. Confira usuário e senha; ao trocar o usuário, informe a senha novamente.';}
 finally{password='';if(epoch===authEpoch)$('#saveTjba').disabled=false;}
};
function setTableHead(service,id){
 const labels=service==='tjba_margem'?['Cliente / CPF','Matrícula','Tipo de servidor','Situação','Empréstimo disponível','Cartão disponível','Status','Data','Observações','Ações']:['Cliente / CPF','Status','Saldo devedor','Total de parcelas','Valor da parcela','Higienização / Data','Ações'];
 $('#'+id).innerHTML='<tr>'+labels.map(l=>'<th>'+l+'</th>').join('')+'</tr>';
}
const moneyTjba=v=>v==null?'—':Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const originalRowsHTML=rowsHTML;
rowsHTML=function(rows){
 const service=rows[0]?.servico||selectedService();if(service!=='tjba_margem')return originalRowsHTML(rows);
 return rows.map(r=>{const running=['Aguardando','Processando'].includes(r.status),label=running?statusLabel(r.status):tjbaStatusLabels[r.tjba_status]||r.status;return `<tr><td><b>${escapeHTML(r.nome)}</b><br><span class="muted">${escapeHTML(r.cpf)}</span><br><small>${escapeHTML(convenioLabel(r.convenio))}</small></td><td>${escapeHTML(r.matricula)||'—'}</td><td>${escapeHTML(r.tipo_servidor)||'—'}</td><td>${escapeHTML(r.situacao_atual)||'—'}</td><td>${moneyTjba(r.emprestimo_disponivel)}</td><td>${moneyTjba(r.cartao_disponivel)}</td><td><span class="pill ${r.status==='Concluída'?'ok':['Erro','Revisão'].includes(r.status)?'err':''}">${escapeHTML(label)}</span><div class="progress-line"><progress max="100" value="${Math.max(0,Math.min(100,Number(r.progress)||0))}" aria-label="Progresso da consulta"></progress><small>${Math.max(0,Math.min(100,Number(r.progress)||0))}%</small></div></td><td>${new Date(r.date).toLocaleString('pt-BR')}</td><td>${r.status==='Não encontrado'?'CPF não encontrado no convênio.':['Revisão','Erro'].includes(r.status)?'Consulte o log em Configurações.':escapeHTML(r.resultado_tjba?.motivo_situacao)||'—'}</td><td>${['Erro','Revisão'].includes(r.status)?`<button data-retry="${escapeHTML(r.id)}">Tentar novamente</button>`:''}<button data-tjba-history="${escapeHTML(r.id)}">Histórico</button><button class="danger" data-delete-job="${escapeHTML(r.id)}">Excluir</button></td></tr>`;}).join('')||'<tr><td colspan="10" class="empty">Nenhuma consulta TJBA encontrada.</td></tr>';
};
const originalExportResults=exportResults;
exportResults=function(items,filename='consultas.csv'){
 if((items[0]?.servico||selectedService())!=='tjba_margem')return originalExportResults(items,filename);
 const safe=v=>'"'+String(v??'').replace(/^[=+@\-]/,"'$&").replaceAll('"','""')+'"';
 const rows=[['nome','cpf','telefone','provedor','convenio','matricula','tipo_servidor','situacao_atual','emprestimo_disponivel','cartao_disponivel','status','data','observacoes'],...items.map(r=>[r.nome,r.cpf,r.telefone,'ConsigX',convenioLabel(r.convenio),r.matricula,r.tipo_servidor,r.situacao_atual,r.emprestimo_disponivel,r.cartao_disponivel,tjbaStatusLabels[r.tjba_status]||statusLabel(r.status),r.date,r.status==='Não encontrado'?'CPF não encontrado.':['Erro','Revisão'].includes(r.status)?'Solicita revisão.':r.resultado_tjba?.motivo_situacao||''])];
 download(filename,rows.map(r=>r.map(safe).join(';')).join('\r\n'));
};
const originalRenderLogs=renderLogs;
renderLogs=function(){originalRenderLogs();const reviews=records.filter(r=>r.servico==='tjba_margem'&&r.resultado_tjba?.vinculos?.length);if(reviews.length)$('#consultationLogs').textContent+='\n\nVínculos TJBA para conferência:\n'+reviews.map(r=>r.cpf+'\n'+JSON.stringify(r.resultado_tjba.vinculos,null,2)).join('\n');};
function updateServiceCopy(){
 const tjba=selectedService()==='tjba_margem';
 $('#serviceAvailability').textContent=tjba?'Homologação':'Disponível';
 $('#singleDescription').textContent=tjba?'CPF obrigatório. Nome e telefone são opcionais.':'Nome, CPF e telefone com DDD.';
 $('#resultsDescription').textContent=tjba?'Confira as margens de empréstimo e cartão, o vínculo e o histórico.':'Acompanhe o andamento, confira valores e simule a recompra.';
 $('#resultsFootnote').textContent=tjba?'Ausência de resultado aparece como —. Margens zero e negativas são preservadas.':'Saldo e parcelas são exibidos somente quando informados pelo atendimento.';
 document.querySelectorAll('#filter option').forEach(option=>{const val=option.value||option.textContent;option.hidden=tjba?['Não é cliente','Aguardando retorno'].includes(val):val==='Não encontrado'||val.startsWith('tjba:');});
}
function selectHygieneService(){
 const tjba=selectedService()==='tjba_margem';$('#convenioPicker').hidden=!tjba;updateServiceCopy();activeCampaign=null;pending=[];importGeneration++;readingImport=false;importError='';$('#file').value='';$('#preview').classList.add('hide');$('#search').value='';$('#filter').value='';
 $('#nome').required=!tjba;$('#telefone').required=!tjba;$('#nameLabel').textContent=tjba?'Nome (opcional)':'Nome completo';$('#phoneLabel').textContent=tjba?'Telefone (opcional)':'Telefone com DDD';
 $('#serviceDescription').textContent=tjba?'Retorna margens de empréstimo e cartão, matrícula e situação do vínculo':'Retorna saldo devedor e valor da parcela';
 $('#singleServiceLabel').textContent=serviceLabel(selectedService());$('#importColumns').textContent=tjba?'Excel, CSV ou TSV. Para consultar margem, a planilha precisa apenas da coluna cpf.':'Aceitamos Excel (.xlsx e .xls), CSV e TSV, com as colunas nome, cpf e telefone.';
 $('#downloadModel').href=tjba?'modelo-tjba.csv':'modelo-importacao.csv';syncImportButton();render();
}
$('#serviceSelect').onchange=selectHygieneService;
$('#tjbaHistoryClose').onclick=()=>{$('#tjbaHistoryPanel').hidden=true;};
for(const selector of ['#rows','#campaignRows']){
 const previous=$(selector).onclick;$(selector).onclick=async e=>{
 const id=e.target.dataset.tjbaHistory;if(!id){if(previous)return previous(e);return;}
 const epoch=authEpoch;$('#tjbaHistoryPanel').hidden=false;$('#tjbaHistoryRows').textContent='Carregando histórico…';
 try{const rows=await fetchAll('/rest/v1/consulta_tjba_historico?job_id=eq.'+encodeURIComponent(id)+'&select=id,created_at,resultado&order=created_at.desc,id.desc');if(epoch!==authEpoch)return;
 $('#tjbaHistoryRows').innerHTML=rows.map(h=>`<article class="card"><b>${new Date(h.created_at).toLocaleString('pt-BR')}</b><p>${escapeHTML(tjbaStatusLabels[h.resultado.status]||h.resultado.status)}</p><p>Matrícula: ${escapeHTML(h.resultado.matricula)||'—'} · Empréstimo: ${moneyTjba(h.resultado.emprestimo_disponivel)} · Cartão: ${moneyTjba(h.resultado.cartao_disponivel)}</p></article>`).join('')||'Nenhum resultado anterior registrado.';
 }catch{if(epoch===authEpoch)$('#tjbaHistoryRows').textContent='Não foi possível carregar o histórico.';}
 };
}
updateServiceCopy();render();

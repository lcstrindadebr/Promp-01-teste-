const $=s=>document.querySelector(s);
const escapeHTML=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const serviceCatalog={digimais_saldo_parcela:{label:'Saldo e parcela — Digi+',available:true,categoria:'saldo_devedor',provedor:'digimais'},margem:{label:'Consulta de margem',available:false},tjba_margem:{label:'Margem — ConsigX',available:true,categoria:'margem',provedor:'tjba'}};
function selectedService(){const id=$('#serviceSelect').value||'digimais_saldo_parcela';if(!serviceCatalog[id]?.available)throw Error('Este tipo de higienização ainda não está disponível.');return id;}
function serviceLabel(id){return serviceCatalog[id||'digimais_saldo_parcela']?.label||'Serviço não identificado';}
let records=[],pending=[],campaigns=[],activeCampaign=null,currentPage="home",retryingCampaign=false;
function toast(message){$('#toast').textContent=message;$('#toast').style.display='block';setTimeout(()=>$('#toast').style.display='none',4500)}
function statusLabel(status){return status==='Processando'?'Consultando...':status}
function resultMessage(r){
 if(['Aguardando','Processando'].includes(r.status))return '';
 if(r.status==='Revisão')return r.saldo!=null||r.valorParcela!=null?'Resultado parcial. Consulte o log em Configurações.':'Consulte o log em Configurações.';
 if(r.status==='Consulta interrompida'&&r.saldo!=null)return 'Saldo obtido. Consulta da parcela interrompida.';
 if(r.status==='Erro')return 'Não foi possível concluir. Consulte o log em Configurações.';
 return '';
}
function consultationWasPerformed(row){
 return ['Concluída','Não é cliente','Já vendeu','Não encontrado','Erro','Revisão','Consulta interrompida'].includes(row.status);
}
function consultationLogRecords(){
 const selection=$('#consultationLogRobot').value;
 const rows=records.filter(row=>row.execution_mode!=='api'&&consultationWasPerformed(row));
 if(!selection)return rows;
 return rows.filter(row=>selection==='unassigned'?row.robot_slot==null:String(row.robot_slot)===selection);
}
function createConsultationLog(id, filename, emptyMessage) {
 const output = document.getElementById(id);
 const count = document.getElementById(id + 'Count');
 const copy = document.getElementById(id + 'Copy');
 const download = document.getElementById(id + 'Download');

 copy.onclick = async () => {
  if (copy.disabled) return;
  try {
   await navigator.clipboard.writeText(output.textContent);
   toast('Log copiado.');
  } catch {
   toast('Não foi possível copiar. Use Baixar TXT ou selecione o texto.');
  }
 };

 download.onclick = () => {
  if (download.disabled) return;
  const blob = new Blob([output.textContent, '\n'], {type: 'text/plain;charset=utf-8'});
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename + '.txt';
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
 };

 return (entries, visible = true) => {
  const total = entries.length;
  count.textContent = visible ? `${total} ${total === 1 ? 'registro' : 'registros'}` : '';
  copy.disabled = download.disabled = !visible || !total;
  output.textContent = visible ? entries.join('\n\n────────────────────\n\n') || emptyMessage : '';
 };
}
const showRobotLog = createConsultationLog('consultationLogs', 'log-consultas-robos', 'Nenhuma consulta encerrada para este filtro.');
function renderLogs(){
 // Only the signed-in user's loaded records are available here; cleared on logout.
 showRobotLog(consultationLogRecords().map(r=>{
  const lines=[`${new Date(r.date).toLocaleString('pt-BR')} | ${r.robot_slot?'Robô '+r.robot_slot:'Sem robô identificado'} | ${serviceLabel(r.servico)} | CPF: ${r.cpf} | ${statusLabel(r.status)} | ${Number(r.progress)||0}%`,r.stage,r.message];
  for(const [key,label] of [['resultado_saldo','Saldo'],['resultado_parcela','Parcela']]){
   const result=r[key];if(result)lines.push(`${label}: ${result.stage||result.status||''}${result.message?' | '+result.message:''}`);
  }
  return lines.filter(Boolean).join('\n');
 }));
}
$('#consultationLogRobot').onchange=()=>renderLogs();
function campaignRecords(id){return records.filter(r=>r.lote_id===id)}
function individualRecords(){const ids=new Set(campaigns.map(c=>c.id));return records.filter(r=>!ids.has(r.lote_id)&&(r.servico||'digimais_saldo_parcela')===selectedService())}
function campaignStats(rows){
 return {total:rows.length,clients:rows.filter(r=>r.saldo!=null||r.valorParcela!=null||r.emprestimo_disponivel!=null||r.cartao_disponivel!=null||r.matricula!=null||r.status==='Concluída').length,nonclients:rows.filter(r=>['Não é cliente','Não encontrado'].includes(r.status)).length,errors:rows.filter(r=>r.status==='Erro').length,sold:rows.filter(r=>r.status==='Já vendeu').length,review:rows.filter(r=>r.status==='Revisão').length,interrupted:rows.filter(r=>r.status==='Consulta interrompida').length,waiting:rows.filter(r=>['Aguardando','Processando'].includes(r.status)).length};
}
function rowsHTML(rows){return rows.map(r=>`<tr><td><b>${escapeHTML(r.nome)}</b><br><span class="muted">${escapeHTML(r.cpf)}</span></td><td><span class="pill ${r.status==='Concluída'?'ok':['Erro','Revisão','Consulta interrompida'].includes(r.status)?'err':r.status==='Processando'?'run':''}">${escapeHTML(statusLabel(r.status))}</span><div class="progress-line"><progress max="100" value="${Math.max(0,Math.min(100,Number(r.progress)||(['Concluída','Não é cliente'].includes(r.status)?100:0)))}" aria-label="Progresso da consulta"></progress><small>${Math.max(0,Math.min(100,Number(r.progress)||(['Concluída','Não é cliente'].includes(r.status)?100:0)))}%</small></div>${resultMessage(r)?`<small class="muted">${escapeHTML(resultMessage(r))}</small>`:''}</td><td>${r.saldo==null?'—':r.saldo.toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}</td><td>${r.parcelas??'—'}</td><td>${r.valorParcela==null?'—':r.valorParcela.toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}</td><td><span class="service-tag">${escapeHTML(serviceLabel(r.servico))}</span><br><span class="muted">${new Date(r.date).toLocaleString('pt-BR')}</span></td><td>${['Erro','Revisão','Consulta interrompida'].includes(r.status)?`<button data-retry="${r.id}">Tentar novamente</button>`:'—'}<br>${typeof amigozAction==='function'?amigozAction(r):''}<button class="danger" data-delete-job="${escapeHTML(r.id)}">Excluir</button></td></tr>`).join('')||'<tr><td colspan="7" class="empty">Nenhuma consulta encontrada.</td></tr>'}
function renderCampaigns(renderRows=true){
 if(!campaigns.length)$('#newCampaignPanel').open=true;
 if(renderRows)$('#campaignList').innerHTML=campaigns.filter(c=>(c.servico||'digimais_saldo_parcela')===selectedService()).map(c=>{const n=campaignStats(campaignRecords(c.id));return `<button class="campaign-item ${activeCampaign===c.id?'selected':''}" data-campaign="${escapeHTML(c.id)}"><b>${escapeHTML(c.nome)}</b><span class="campaign-service">${escapeHTML(serviceLabel(c.servico)+(c.servico==='tjba_margem'?' · '+convenioLabel(c.convenio):''))}</span><small>${n.total} consultas · ${n.waiting?'Consultando...':'Finalizada'} · ${new Date(c.created_at).toLocaleDateString('pt-BR')}</small></button>`}).join('')||'<p class="muted">Crie sua primeira campanha usando a planilha padrão.</p>';
 const c=campaigns.find(c=>c.id===activeCampaign);if(typeof setTableHead==='function'&&c)setTableHead(c.servico,'campaignHead');$('#campaignDetail').classList.toggle('hide',!c);if(!c)return;
 const rows=campaignRecords(c.id),n=campaignStats(rows);
 $('#campaignTitle').textContent=c.nome;$('#campaignState').textContent=serviceLabel(c.servico)+(c.servico==='tjba_margem'?' · '+convenioLabel(c.convenio):'')+' · '+(n.waiting?'Consultando...':'Campanha finalizada');
 $('#campaignReport').innerHTML=[['Consultas solicitadas',n.total],[c.servico==='tjba_margem'?'CPFs localizados':'Clientes identificados',n.clients],[c.servico==='tjba_margem'?'Não encontrados':'Não são clientes',n.nonclients],['Erros',n.errors],['Solicitam revisão',n.review],...c.servico==='tjba_margem'?[]:[['Já vendeu',n.sold],['Interrompidas',n.interrupted]],['Na fila / consultando',n.waiting]].map(([label,value])=>`<div class="stat"><label>${label}</label><strong>${value}</strong></div>`).join('');
 $('#retryCampaign').disabled=retryingCampaign||!(n.errors+n.review+n.interrupted);$('#retryCampaign').textContent=`Nova tentativa: consultas com falha (${n.errors+n.review+n.interrupted})`;
 if(renderRows)$('#campaignRows').innerHTML=rowsHTML(rows).replace(/<button data-retry="[^"]+">Tentar novamente<\/button>/g,'Use o botão da campanha');
}
function render(){
 if(typeof refreshAmigoz==='function')refreshAmigoz();
 if(typeof setTableHead==='function')setTableHead(selectedService(),'individualHead');
 renderLogs();renderCampaigns();
 const rows=individualRecords(),q=$('#search').value.toLowerCase(),filter=$('#filter').value;
 $('#total').textContent=rows.length;
 $('#waiting').textContent=rows.filter(r=>['Aguardando','Processando'].includes(r.status)).length;
 $('#done').textContent=rows.filter(r=>r.status==='Concluída').length;
 $('#errors').textContent=rows.filter(r=>['Erro','Revisão','Consulta interrompida'].includes(r.status)).length;
 $('.modeNotice').textContent='Preencha os dados para consultar uma pessoa. Para uma lista de clientes, use Campanhas.';
 $('#rows').innerHTML=rowsHTML(rows.filter(r=>(!filter||r.status===filter||(filter.startsWith('tjba:')&&r.tjba_status===filter.slice(5)))&&matchesLeadSearch(r,q)));
}

const digits=s=>String(s).replace(/\D/g,'');
function formatCpf(value){return String(value??'').replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/,'$1.$2.$3-$4')}
function matchesLeadSearch(row,query){
 const cpfQuery=/^[\d.\-\s]+$/.test(query)?digits(query):'';
 return !query||`${row.nome} ${row.cpf}`.toLowerCase().includes(query)||Boolean(cpfQuery&&digits(row.cpf).includes(cpfQuery));
}
$('#cpf').onblur=e=>{const cpf=digits(e.target.value);if(cpf.length===11)e.target.value=formatCpf(cpf);};
function validate(r,service=selectedService()){
 const tjba=service==='tjba_margem';r.nome=(r.nome||'').trim();r.cpf=digits(r.cpf);r.telefone=digits(r.telefone||'');
 if(tjba&&r.cpf.length>0&&r.cpf.length<11)r.cpf=r.cpf.padStart(11,'0');
 if(tjba&&!r.nome)r.nome='CPF '+formatCpf(r.cpf);
 if(!r.nome||r.nome.length>160||r.cpf.length!==11||(!tjba&&!/^\d{10,13}$/.test(r.telefone))||(tjba&&r.telefone&&!/^\d{10,13}$/.test(r.telefone)))throw Error(tjba?'Informe CPF com até 11 dígitos; nome e telefone são opcionais.':'Informe nome, CPF com 11 dígitos e telefone com DDD.');return r;
}
function csvParse(text){
 const first=text.split(/\r?\n/)[0],sep=first.includes('\t')?'\t':first.includes(';')?';':',';let rows=[],row=[],value='',quoted=false;
 for(let i=0;i<text.length;i++){const c=text[i];if(c==='"'){if(quoted&&text[i+1]==='"'){value+='"';i++}else quoted=!quoted}else if(c===sep&&!quoted){row.push(value);value=''}else if(c==='\n'&&!quoted){row.push(value.replace(/\r$/,''));rows.push(row);row=[];value=''}else value+=c}
 if(quoted)throw Error('CSV com aspas não fechadas.');if(value||row.length){row.push(value.replace(/\r$/,''));rows.push(row)}return rows.filter(r=>r.some(v=>v.trim()));
}
$('#single').onsubmit=async e=>{e.preventDefault();const button=e.target.querySelector('button');button.disabled=true;try{await add([validate(Object.fromEntries(new FormData(e.target)))]);e.target.reset()}catch(e){toast(e.message)}finally{button.disabled=false;if(typeof applyAccessUi==='function')applyAccessUi()}};
let readingImport=false,creatingCampaign=false,importGeneration=0,importError='';
function syncImportButton(message){
 const named=Boolean($('#campaignName').value.trim()),quotaError=typeof campaignImportError==='function'?campaignImportError(pending.length):'';
 $('#import').disabled=readingImport||creatingCampaign||!pending.length||!named||Boolean(quotaError);
 $('#import').textContent=creatingCampaign?'Criando campanha…':readingImport?'Lendo planilha…':'Criar campanha e consultar';
 $('#importStatus').textContent=message||importError||quotaError||(readingImport?'Aguarde a leitura da planilha.':!pending.length?'Selecione uma planilha preenchida com os dados dos clientes.':!named?'Planilha validada. Informe o nome da campanha para continuar.':`${pending.length} cliente(s) pronto(s) para consultar.`);
}
$('#campaignName').oninput=()=>syncImportButton();
function importHeader(value){
 const key=value.trim().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[_\s]+/g,' ');
 return ({'nome completo':'nome','nome do cliente':'nome','celular':'telefone','telefone com ddd':'telefone','telefone 1':'telefone','whatsapp':'telefone'})[key]||key;
}
function validateImportClassification(headers, rows, expected = null) {
 const normalized = value => String(value || '').normalize('NFD')
   .replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
 const stateAliases = {bahia:'ba',saopaulo:'sp'};
 const agreementAliases = {
   tribunaldejusticadabahia:'tjba',tribunaldejustica:'tjba',
   defensoriapublicadabahia:'dpeba',defensoriapublica:'dpeba',
   governodabahia:'saeb',governobasaeb:'saeb',suprevprevidencia:'suprev'
 };
 const aliases = {uf:stateAliases,convenio:agreementAliases};
 const groups = {uf:['uf','estado'],convenio:['convenio','orgao convenio']};
 for (const [field, names] of Object.entries(groups)) {
   const positions = headers.map((name,index) => names.includes(name) ? index : -1).filter(index => index >= 0);
   let firstValue = null;
   rows.forEach((row,index) => {
     for (const position of positions) {
       const raw = normalized(row[position]);
       if (!raw) continue;
       const value = aliases[field][raw] || raw;
       if (firstValue && firstValue !== value) {
         throw Error('Linha ' + (index+2) + ': a planilha contém ' +
           (field === 'uf' ? 'estados diferentes.' : 'convênios diferentes.') +
           ' Importe uma lista por estado e convênio.');
       }
       firstValue = value;
       if (expected?.[field] && value !== expected[field]) {
         throw Error('Linha ' + (index+2) + ': ' + field +
           ' diferente da seleção da campanha. Corrija a planilha ou a seleção.');
       }
     }
   });
 }
}
$('#file').onchange=async e=>{
 const generation=++importGeneration;pending=[];readingImport=true;importError='';
 $('#preview').classList.remove('hide');$('#preview').textContent='';syncImportButton();
 try{
 const file=e.target.files[0];if(!file){syncImportButton('Selecione uma planilha.');return;}
 if(file.name&&!/\.(csv|tsv|xlsx|xls)$/i.test(file.name))throw Error('Formato não suportado. Envie CSV, TSV, XLSX ou XLS.');
 const admin=typeof currentAccess!=='undefined'&&currentAccess?.role==='admin'&&currentAccess.active===true;
 if(!admin&&file.size>2000000)throw Error('Arquivo acima de 2 MB. Divida a planilha em arquivos menores.');
 let rows;
 if(/\.xlsx?$/i.test(file.name||'')){
 if(typeof XLSX==='undefined')throw Error('O leitor de Excel não carregou. Atualize a página e tente novamente.');
 let book;try{book=XLSX.read(await file.arrayBuffer(),{type:'array',...(admin?{}:{sheetRows:1002}),cellFormula:false,cellHTML:false,cellText:false});}catch{throw Error('Não foi possível abrir o Excel. Confira se o arquivo está íntegro e sem senha.');}
 const sheet=book.Sheets[book.SheetNames[0]];if(!sheet)throw Error('A planilha não contém abas.');
 const range=sheet['!fullref']||sheet['!ref'];if(!admin&&range&&XLSX.utils.decode_range(range).e.r>1000)throw Error('A primeira aba deve conter até 1.000 clientes e o cabeçalho. Remova linhas extras ou divida o arquivo.');
 rows=XLSX.utils.sheet_to_json(sheet,{header:1,raw:true,defval:'',blankrows:false}).map(row=>row.map(value=>String(value??'')));
 }else{
 let text=(await file.text()).replace(/^\uFEFF/,'').replace(/^sep=[;,]\r?\n/i,'');
 if(text.includes('\uFFFD'))throw Error('Codificação não reconhecida. Salve como CSV UTF-8 no Excel e envie novamente.');
 rows=csvParse(text);
 }
 if(generation!==importGeneration)return;
 if(!rows.length)throw Error('Arquivo vazio. Preencha o modelo com os dados dos clientes.');
 const headers=rows.shift().map(importHeader),missing=(selectedService()==='tjba_margem'?['cpf']:['nome','cpf','telefone']).filter(h=>!headers.includes(h));
 if(missing.length)throw Error('Colunas ausentes: '+missing.join(', ')+'. Use o modelo padrão e salve como CSV UTF-8.');
 if(new Set(headers).size!==headers.length)throw Error('Há títulos de colunas repetidos. Mantenha uma coluna nome, cpf e telefone.');
 if(!admin&&rows.length>1000)throw Error('Envie até 1.000 registros por campanha.');
 if(!rows.length)throw Error('A planilha contém apenas o cabeçalho. Adicione os clientes antes de enviar.');
 validateImportClassification(headers, rows, selectedService()==='tjba_margem'
   ? {uf:'ba',convenio:selectedConvenio()} : null);
 const errors=[],seen=new Set(),valid=[];
 rows.forEach((row,i)=>{try{
 const r=Object.fromEntries(headers.map((h,j)=>[h,(row[j]||'').trim()]));
 if((r.nome||'').toUpperCase()==='NOME COMPLETO DO CLIENTE'&&digits(r.cpf)==='00000000000')throw Error('Substitua a linha de exemplo pelos dados de um cliente.');
 if(selectedService()!=='tjba_margem'&&(!r.nome||r.nome.length>160))throw Error('Nome ausente ou acima de 160 caracteres.');
 if(/^\d{1,11}$/.test(r.cpf))r.cpf=r.cpf.padStart(11,'0');
 if(!/^\d{11}$/.test(digits(r.cpf)))throw Error('CPF deve ter 11 dígitos. Preserve os zeros à esquerda.');
 if((selectedService()!=='tjba_margem'||r.telefone)&&!/^\d{10,13}$/.test(digits(r.telefone)))throw Error('Telefone deve conter DDD e 10 a 13 dígitos.');
 if(selectedService()==='tjba_margem'&&/^0+$/.test(digits(r.cpf)))throw Error('Substitua o CPF de exemplo.');
 validate(r);if(seen.has(r.cpf))throw Error('CPF duplicado nesta planilha.');seen.add(r.cpf);valid.push(r);
 }catch(error){errors.push('Linha '+(i+2)+': '+error.message);}});
 pending=valid;$('#preview').textContent=`${pending.length} válidos · ${errors.length} inválidos\n`+errors.slice(0,30).join('\n')+(errors.length>30?'\nMais erros: revise as demais linhas.':'');
 if(!pending.length)throw Error('Nenhum cliente válido. Corrija os motivos abaixo e selecione o arquivo novamente.');
 }catch(error){if(generation===importGeneration){pending=[];$('#importStatus').textContent=error.message;importError=error.message;}}
 finally{if(generation===importGeneration){readingImport=false;syncImportButton();}}
};
$('#import').onclick=async()=>{
 if(creatingCampaign||readingImport)return;
 creatingCampaign=true;importError='';syncImportButton();
 try{const name=$('#campaignName').value.trim();if(!name)throw Error('Informe o nome da campanha.');if(!pending.length)throw Error('Selecione uma planilha com clientes válidos.');
 activeCampaign=await createCampaign(name,pending);pending=[];$('#campaignName').value='';$('#file').value='';$('#preview').classList.add('hide');$('#newCampaignPanel').open=false;renderCampaigns();toast('Campanha criada. Consultas adicionadas à fila.');
 }catch(e){toast(e.message);const feedback=$('#wizardFeedback');if(feedback)feedback.textContent=e.message;if(typeof refreshMyAccess==='function')await refreshMyAccess(true).catch(()=>{});}
 finally{creatingCampaign=false;syncImportButton();}
};
function download(name,content){const u=URL.createObjectURL(new Blob(['\uFEFF'+content],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),1000)}
async function exportResults(items,filename='consultas.csv') {
 const safe=value=>'"'+String(value??'').replace(/^[=+@\-]/,"'$&").replaceAll('"','""')+'"';
 let rows=[['nome','cpf','telefone','tipo_higienizacao','status','saldo','parcelas','valor_parcela','data','observacao'],
  ...items.map(row=>[row.nome,formatCpf(row.cpf),row.telefone,serviceLabel(row.servico),statusLabel(row.status),row.saldo,row.parcelas,row.valorParcela,row.date,resultMessage(row)])];
 if(typeof amigozAppendExport==='function') rows=await amigozAppendExport(rows,items.map(row=>({cpf:row.cpf,job_id:row.id,convenio:row.convenio||''})));
 if(typeof amigozCsvCells==='function') rows=[rows[0],...rows.slice(1).map(amigozCsvCells)];
 download(filename,rows.map(row=>row.map(safe).join(';')).join('\r\n'));
}
$('#export').onclick=()=>exportResults(individualRecords());
$('#exportCampaign').onclick=()=>exportResults(campaignRecords(activeCampaign),'campanha-resultados.csv');
$('#exportCampaignReport').onclick=()=>{
 const c=campaigns.find(c=>c.id===activeCampaign);if(!c)return;const n=campaignStats(campaignRecords(c.id));
 const safe=value=>'"'+String(value).replaceAll('"','""').replace(/^[=+@\-]/,"'$&")+'"';
 download('campanha-relatorio.csv',[['campanha','solicitadas',c.servico==='tjba_margem'?'cpfs_localizados':'clientes',c.servico==='tjba_margem'?'nao_encontrados':'nao_clientes','erros','revisao','interrompidas',...c.servico==='tjba_margem'?[]:['ja_vendeu'],'pendentes'],[c.nome,n.total,n.clients,n.nonclients,n.errors,n.review,n.interrupted,...c.servico==='tjba_margem'?[]:[n.sold],n.waiting]].map(row=>row.map(safe).join(';')).join('\r\n'));
};
$('#campaignList').onclick=e=>{const button=e.target.closest('[data-campaign]');if(!button)return;activeCampaign=button.dataset.campaign;renderCampaigns()};
$('#retryCampaign').onclick=async()=>{
 const button=$('#retryCampaign');retryingCampaign=true;button.disabled=true;
 try{const count=await retryCampaign(activeCampaign);toast(count+' consulta(s) reenviada(s) para a fila.');await loadCloud()}catch(e){toast(e.message)}finally{retryingCampaign=false;renderCampaigns()}
};

$('#rows').onclick=async e=>{const id=e.target.dataset.retry;if(!id)return;const r=records.find(r=>r.id===id);if(!r)return;e.target.disabled=true;try{await add([{nome:r.nome,cpf:digits(r.cpf),telefone:r.telefone}],r.servico||'digimais_saldo_parcela',r.convenio||'tjba')}catch(err){toast(err.message)}finally{if(e.target.isConnected)e.target.disabled=false}};
$('#search').oninput=render;$('#filter').onchange=render;
function navigate(page){
 currentPage=page;$('#consultationTabs').hidden=!['home','campaigns'].includes(page);document.querySelectorAll('[data-consultation]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.consultation===page)));if(typeof tickMonitoring==='function')tickMonitoring();$('#serviceContext').classList.toggle('hide',!['home','campaigns'].includes(page));
 $('#pageBreadcrumb').textContent=({opportunities:'Oportunidades',clients:'Clientes',home:'Consulta individual',campaigns:'Campanhas',settings:'Configurações'})[page];
 document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.dataset.page===page||(b.dataset.page==='home'&&page==='campaigns')));
 $('#opportunities').classList.toggle('hide',page!=='opportunities');
 $('#clients').classList.toggle('hide',page!=='clients');if(typeof syncCrmPage==='function')syncCrmPage(page);
 $('#home').classList.toggle('hide',page!=='home');$('#campaigns').classList.toggle('hide',page!=='campaigns');$('#settings').classList.toggle('hide',page!=='settings');$('#results').classList.toggle('hide',page!=='home');
}
document.querySelectorAll('nav button').forEach(b=>b.onclick=()=>navigate(b.dataset.page));
document.querySelectorAll('[data-consultation]').forEach(b=>b.onclick=()=>navigate(b.dataset.consultation));
render();

(()=>{
const button=document.createElement('button');
button.type='button';button.textContent='Reaproveitar base';
$('#exportCampaign').before(button);
const dialog=document.createElement('dialog');
dialog.setAttribute('aria-labelledby','reuseTitle');
dialog.innerHTML=`<section class="card"><div class="heading"><h2 id="reuseTitle">Reaproveitar base</h2><form method="dialog"><button>Fechar</button></form></div>
<form id="reuseForm">
<label class="field" for="reuseName">Nome da nova campanha</label><input id="reuseName" required maxlength="160">
<label class="field" for="reuseAgreement">Convênio Amigoz</label><select id="reuseAgreement" required></select>
<fieldset><legend>Consultas</legend>
<label><input id="reuseMargin" type="checkbox" checked> Margem consignável</label>
<label><input id="reuseCash" type="checkbox" checked> Saque complementar</label></fieldset>
<p id="reuseTotals"></p><p>Marque os resultados anteriores que deseja consultar novamente.</p>
<div id="reuseRows"></div>
<div class="actions"><button id="reusePrevious" type="button">Anterior</button><button id="reuseNext" type="button">Próxima</button>
<button id="reuseConfirm" class="primary" disabled>Colocar na fila</button></div></form>
<p id="reuseStatus" role="status"></p><h3>Campanhas criadas desta base</h3><ul id="reuseHistory"></ul></section>`;
document.body.append(dialog);
const labels={faltante:'Sem consulta',falha:'Falha anterior',consultado:'Já consultado',importado:'Dado importado',pendente:'Na fila'};
const modes=[['margem','#reuseMargin'],['saque','#reuseCash']];
let origin,epoch,generation=0,request,selection,seen,cursors,next,preview,busy=false;
const current=()=>dialog.open&&epoch===authEpoch&&authenticated;
const rpc=(name,payload)=>sbRequest('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(payload)});
const status=text=>{$('#reuseStatus').textContent=text;};
async function history(){
 const rows=await rpc('crm_status_reuso',{p_origem:origin});
 if(!current())return;
 $('#reuseHistory').replaceChildren(...rows.map(row=>{
  const item=document.createElement('li');
  item.textContent=row.nome+' · '+row.resposta.leads+' leads · '+row.pendentes+' pendentes · '+row.atencao+' com falha ou em revisão · '+(row.concluidas??0)+' concluídos'+(row.ultimo_http?' · último erro Amigoz HTTP '+row.ultimo_http:'');
  return item;
 }));
}
function render(){
 if(!preview)return;
 const chosen=modes.filter(([,id])=>$(id).checked).map(([mode])=>mode);
 let count=0;
 for(const mode of chosen){
  const totals=preview[mode]||{};
  count+=(totals.faltante||0)+(totals.falha||0);

 }
 let leads=count-(chosen.length===2?preview.ambos_sugeridos:0);
 for(const [cpf,selected] of Object.entries(selection)){
  const row=seen[cpf];
  const extra=chosen.filter(mode=>selected.includes(mode)&&['consultado','importado'].includes(row[mode])).length;
  count+=extra;
  if(extra&&!chosen.some(mode=>['faltante','falha'].includes(row[mode])))leads++;
 }
 $('#reuseTotals').textContent=preview.total+' leads na base · '+leads+' selecionados · '+count+' consultas previstas. '+chosen.map(mode=>{
  const totals=preview[mode]||{};
  return (mode==='margem'?'Margem':'Saque')+': '+(totals.faltante||0)+' sem consulta, '+(totals.consultado||0)+' já consultados, '+(totals.importado||0)+' importados, '+(totals.pendente||0)+' na fila, '+(totals.falha||0)+' com falha';
 }).join(' · ');
 $('#reuseRows').replaceChildren(...preview.linhas.map(row=>{
  const line=document.createElement('div');
  const name=document.createElement('strong');
  name.textContent=(row.nome||'')+' · '+formatCpf(row.cpf);
  line.append(name);
  for(const mode of chosen){
   const label=document.createElement('label');
   label.textContent=' '+(mode==='margem'?'Margem':'Saque')+' · '+labels[row[mode]]+' ';
   if(['consultado','importado'].includes(row[mode])){
    const input=document.createElement('input');input.type='checkbox';
    input.checked=selection[row.cpf]?.includes(mode)||false;
    input.onchange=()=>{
     request=crypto.randomUUID();
     const entries=new Set(selection[row.cpf]||[]);
     if(input.checked)entries.add(mode);else entries.delete(mode);
     selection[row.cpf]=[...entries];render();
    };
    label.prepend(input);
   }
   line.append(label);
  }
  return line;
 }));
 $('#reuseConfirm').disabled=busy||count===0;
}
async function loadPage(){
 const token=++generation;
 preview=null;$('#reuseRows').replaceChildren();$('#reuseTotals').textContent='';
 $('#reuseConfirm').disabled=$('#reusePrevious').disabled=$('#reuseNext').disabled=true;
 if(!$('#reuseAgreement').value)return;
 status('Preparando prévia…');
 try{
  const result=await rpc('crm_prever_reuso',{p_origem:origin,p_convenio:$('#reuseAgreement').value,p_apos:cursors.at(-1)});
  if(!current()||token!==generation)return;
  preview=result;next=result.proxima;
  for(const row of result.linhas)seen[row.cpf]=row;
  $('#reusePrevious').disabled=cursors.length<2;$('#reuseNext').disabled=!next;
  render();status('');
 }catch(error){if(current()&&token===generation)status(error.message);}
}
function reset(){
 selection={};seen={};cursors=[''];request=crypto.randomUUID();
 const option=$('#reuseAgreement').selectedOptions[0];
 for(const [mode,id] of modes){$(id).disabled=!option?.dataset.services?.includes('amigoz_'+mode);$(id).checked=!$(id).disabled;}
 loadPage();
}
button.onclick=async()=>{
 if(!activeCampaign||busy)return;
 origin=activeCampaign;epoch=authEpoch;
 $('#reuseName').value='Reuso · '+(campaigns.find(c=>c.id===origin)?.nome||'Campanha').slice(0,150);
 $('#reuseAgreement').replaceChildren();$('#reuseRows').replaceChildren();$('#reuseHistory').replaceChildren();
 $('#reuseTotals').textContent='';$('#reuseConfirm').disabled=$('#reuseNext').disabled=$('#reusePrevious').disabled=true;
 dialog.showModal();status('Carregando convênios…');
 try{
  const rows=await sbRequest('/rest/v1/crm_catalogo_importacao?select=codigo,nome,uf,servicos&servicos=ov.{amigoz_saque,amigoz_margem}&order=uf,nome');
  if(!current())return;
  $('#reuseAgreement').replaceChildren(new Option('Selecione um convênio',''),...rows.map(row=>{
   const option=new Option(row.uf+' · '+row.nome,row.codigo);
   option.dataset.services=row.servicos.join(',');return option;
  }));
  reset();status('');
  await history();
 }catch(error){if(current())status(error.message);}
};
$('#reuseAgreement').onchange=reset;
$('#reuseName').oninput=()=>{request=crypto.randomUUID();};
for(const [,id] of modes)$(id).onchange=()=>{request=crypto.randomUUID();render();};
$('#reusePrevious').onclick=()=>{cursors.pop();loadPage();};
$('#reuseNext').onclick=()=>{if(next){cursors.push(next);loadPage();}};
$('#reuseForm').onsubmit=async event=>{
 event.preventDefault();
 if(!current()||!preview||busy)return;
 busy=true;$('#reuseConfirm').disabled=true;status('Enfileirando…');
 const controls=[...event.target.elements].filter(control=>!control.disabled);
 controls.forEach(control=>{control.disabled=true;});
 try{
  const result=await rpc('crm_confirmar_reuso',{p_id:request,p_origem:origin,p_convenio:$('#reuseAgreement').value,
   p_nome:$('#reuseName').value,p_modalidades:modes.filter(([,id])=>$(id).checked).map(([mode])=>mode),p_incluir:selection});
  if(!current())return;
  preview=null;$('#reuseRows').replaceChildren();$('#reuseTotals').textContent='';
  status(result.leads+' leads · '+result.consultas+' consultas enfileiradas.');
  await history();
 }catch(error){if(current())status(error.message);}
 finally{busy=false;controls.forEach(control=>{control.disabled=false;});if(current()){render();if(!preview)$('#reuseConfirm').disabled=$('#reusePrevious').disabled=$('#reuseNext').disabled=true;}}
};
dialog.addEventListener('close',()=>{generation++;});
})();

const $=s=>document.querySelector(s);
const escapeHTML=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let records=[],pending=[];
function toast(message){$('#toast').textContent=message;$('#toast').style.display='block';setTimeout(()=>$('#toast').style.display='none',4500)}
function render(){
 const q=$('#search').value.toLowerCase(),filter=$('#filter').value;
 $('#total').textContent=records.length;
 $('#waiting').textContent=records.filter(r=>['Aguardando','Processando'].includes(r.status)).length;
 $('#done').textContent=records.filter(r=>r.status==='Concluída').length;
 $('#errors').textContent=records.filter(r=>['Erro','Revisão'].includes(r.status)).length;
 $('.modeNotice').textContent='Consultas salvas no Supabase. Acompanhe os resultados do robô da VPS por aqui.';
 $('#rows').innerHTML=records.filter(r=>(!filter||r.status===filter)&&`${r.nome} ${r.cpf}`.toLowerCase().includes(q)).map(r=>`<tr><td><b>${escapeHTML(r.nome)}</b><br><span class="muted">${escapeHTML(r.cpf)}</span></td><td><span class="pill ${r.status==='Concluída'?'ok':['Erro','Revisão'].includes(r.status)?'err':r.status==='Processando'?'run':''}">${escapeHTML(r.status)}</span><div class="progress-line"><progress max="100" value="${Math.max(0,Math.min(100,Number(r.progress)||(['Concluída','Não é cliente'].includes(r.status)?100:0)))}" aria-label="Progresso da consulta"></progress><small>${Math.max(0,Math.min(100,Number(r.progress)||(['Concluída','Não é cliente'].includes(r.status)?100:0)))}%</small></div><small class="muted">${escapeHTML(r.stage||'Aguardando na fila')}</small>${r.message?`<br><small>${escapeHTML(r.message)}</small>`:''}</td><td>${r.saldo==null?'—':r.saldo.toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}</td><td>${r.parcelas??'—'}</td><td>Supabase<br><span class="muted">${new Date(r.date).toLocaleString('pt-BR')}</span></td><td>${['Erro','Revisão'].includes(r.status)?`<button data-retry="${r.id}">Tentar novamente</button>`:'—'}</td></tr>`).join('')||'<tr><td colspan="6" class="empty">Nenhuma consulta encontrada.<br><small>Consulte um cliente ou importe a planilha padrão.</small></td></tr>';
}
const digits=s=>String(s).replace(/\D/g,'');
function validate(r){r.nome=r.nome.trim();r.cpf=digits(r.cpf);r.telefone=digits(r.telefone);if(!r.nome||r.nome.length>160||r.cpf.length!==11||!/^\d{10,13}$/.test(r.telefone))throw Error('Informe nome, CPF com 11 dígitos e telefone com DDD.');return r}
function csvParse(text){
 const sep=text.split(/\r?\n/)[0].includes(';')?';':',';let rows=[],row=[],value='',quoted=false;
 for(let i=0;i<text.length;i++){const c=text[i];if(c==='"'){if(quoted&&text[i+1]==='"'){value+='"';i++}else quoted=!quoted}else if(c===sep&&!quoted){row.push(value);value=''}else if(c==='\n'&&!quoted){row.push(value.replace(/\r$/,''));rows.push(row);row=[];value=''}else value+=c}
 if(quoted)throw Error('CSV com aspas não fechadas.');if(value||row.length){row.push(value.replace(/\r$/,''));rows.push(row)}return rows.filter(r=>r.some(v=>v.trim()));
}
$('#single').onsubmit=async e=>{e.preventDefault();const button=e.target.querySelector('button');button.disabled=true;try{await add([validate(Object.fromEntries(new FormData(e.target)))]);e.target.reset()}catch(e){toast(e.message)}finally{button.disabled=false}};
$('#file').onchange=async e=>{
 pending=[];$('#import').disabled=true;
 try{const file=e.target.files[0];if(!file)return;if(file.size>2000000)throw Error('Arquivo acima de 2 MB.');
 const rows=csvParse((await file.text()).replace(/^\uFEFF/,''));if(!rows.length)throw Error('Arquivo vazio.');const headers=rows.shift().map(x=>x.trim().toLowerCase());
 if(!['nome','cpf','telefone'].every(h=>headers.includes(h)))throw Error('Use o modelo padrão: nome, cpf e telefone.');if(rows.length>1000)throw Error('Envie até 1.000 registros.');let errors=[];
 rows.forEach((row,i)=>{try{const r=validate(Object.fromEntries(headers.map((h,j)=>[h,row[j]||''])));if(r.nome==='NOME COMPLETO DO CLIENTE'&&r.cpf==='00000000000')throw Error();pending.push(r)}catch{errors.push('Linha '+(i+2)+': corrija os dados ou substitua o exemplo.')}});
 $('#preview').classList.remove('hide');$('#preview').textContent=`${pending.length} válidos · ${errors.length} inválidos\n`+errors.slice(0,10).join('\n');$('#import').disabled=!pending.length;
 }catch(e){toast(e.message)}
};
$('#import').onclick=async()=>{const button=$('#import');button.disabled=true;try{await add(pending);pending=[];$('#file').value='';$('#preview').classList.add('hide')}catch(e){toast(e.message)}finally{button.disabled=!pending.length}};
function download(name,content){const u=URL.createObjectURL(new Blob(['\uFEFF'+content],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),1000)}
$('#export').onclick=()=>{const safe=v=>'"'+String(v??'').replace(/^[=+@\-]/,"'$&").replaceAll('"','""')+'"';download('consultas.csv',[['nome','cpf','telefone','status','saldo','parcelas','data','observacao'],...records.map(r=>[r.nome,r.cpf,r.telefone,r.status,r.saldo,r.parcelas,r.date,r.message])].map(r=>r.map(safe).join(';')).join('\r\n'))};
$('#rows').onclick=async e=>{const id=e.target.dataset.retry;if(!id)return;const r=records.find(r=>r.id===id);if(!r)return;e.target.disabled=true;try{await add([{nome:r.nome,cpf:r.cpf,telefone:r.telefone}])}catch(err){toast(err.message)}finally{if(e.target.isConnected)e.target.disabled=false}};
$('#search').oninput=render;$('#filter').onchange=render;
document.querySelectorAll('nav button').forEach(b=>b.onclick=()=>{document.querySelectorAll('nav button').forEach(x=>x.classList.toggle('active',x===b));$('#home').classList.toggle('hide',b.dataset.page!=='home');$('#settings').classList.toggle('hide',b.dataset.page!=='settings');$('#results').classList.toggle('hide',b.dataset.page==='settings')});
render();

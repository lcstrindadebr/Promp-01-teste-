// Celular (Fase 3): as tabelas de consultas e de clientes da campanha viram cartões em telas
// estreitas. Cada célula recebe o nome da coluna (data-label), que o CSS mostra no lugar do cabeçalho.
(function(){
 function label(tbody){
  const heads=[...(tbody.closest('table')?.querySelectorAll('thead th')||[])].map(th=>th.textContent.trim());
  for(const row of tbody.rows)[...row.cells].forEach((cell,i)=>{if(cell.colSpan===1&&heads[i])cell.dataset.label=heads[i];});
 }
 for(const id of ['rows','campaignRows']){
  const tbody=document.getElementById(id);if(!tbody)continue;
  tbody.closest('table')?.classList.add('responsive-table');
  label(tbody);
  new MutationObserver(()=>label(tbody)).observe(tbody,{childList:true});
  // O cabeçalho muda com o serviço (Digi+ ou ConsigX): reaplica os rótulos.
  const head=tbody.closest('table')?.querySelector('thead');
  if(head)new MutationObserver(()=>label(tbody)).observe(head,{childList:true,subtree:true});
 }
})();

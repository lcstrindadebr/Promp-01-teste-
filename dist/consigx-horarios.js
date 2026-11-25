// Campanhas ConsigX de convênio com horário (SAEB, SUPREV): fora do horário o robô não consulta e a campanha
// mostra quando retoma. Ela não é pausada de verdade: volta sozinha na abertura, e o "Pausar" continua manual.
// Os horários e consigxHorario ficam em tjba.js; este arquivo vem depois de workspace.js, onde está campaignPhaseLabel.
{
 const baseLabel=campaignPhaseLabel;
 campaignPhaseLabel=function(c,rows){
  const label=baseLabel(c,rows);
  if(c?.servico!=='tjba_margem'||c.paused||label!=='Na fila')return label;
  const h=consigxHorario(c.convenio);
  return h&&!h.aberto?`Fora do horário · retoma às ${h.abre}`:label;
 };
}
// O aviso de horário acompanha a troca de convênio (inclusive a feita pela importação do CRM, que chama onchange).
{
 const select=$('#convenioSelect'),baseChange=select.onchange;
 select.onchange=function(...args){const result=baseChange?.apply(this,args);renderConsigxHours();return result;};
}

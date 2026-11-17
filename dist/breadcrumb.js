// Caminho no topo da página (Fase 3): mostra onde a pessoa está de verdade,
// por exemplo "Campanhas › Servidores SP" ou "Configurações › Usuários da empresa".
(function(){
 const crumb=$('#pageBreadcrumb');if(!crumb)return;
 function updateBreadcrumb(){
  if(currentPage==='campaigns'){
   const c=campaigns.find(c=>c.id===activeCampaign);
   crumb.textContent=c?'Campanhas › '+c.nome:'Campanhas';
  }else if(currentPage==='settings'){
   const tab=document.querySelector('.settings-tabs [aria-selected="true"]');
   crumb.textContent=tab?'Configurações › '+tab.textContent.trim():'Configurações';
  }
 }
 const baseNavigate=navigate;navigate=function(...args){baseNavigate(...args);updateBreadcrumb();};
 const baseCampaigns=renderCampaigns;renderCampaigns=function(...args){baseCampaigns(...args);updateBreadcrumb();};
 if(typeof switchSettings==='function'){const baseSwitch=switchSettings;switchSettings=function(...args){baseSwitch(...args);updateBreadcrumb();};}
 window.updateBreadcrumb=updateBreadcrumb;
})();

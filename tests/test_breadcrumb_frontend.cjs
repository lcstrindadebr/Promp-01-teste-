const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run('function loadAmigozTables(){};function tickMonitoring(){};function loadApiTokens(){};function loadApiDocs(){};');
 run(fs.readFileSync('dist/settings.js','utf8'));
 run(fs.readFileSync('dist/breadcrumb.js','utf8'));
 run("campaigns=[{id:'c1',nome:'Servidores SP',servico:'digimais_saldo_parcela',created_at:'2026-11-17'}];records=[];activeCampaign=null;navigate('campaigns');");
 assert.equal(t.get('#pageBreadcrumb').textContent,'Campanhas');
 run("activeCampaign='c1';renderCampaigns();");
 assert.equal(t.get('#pageBreadcrumb').textContent,'Campanhas › Servidores SP');
 run("navigate('settings');switchSettings('account');");
 assert.equal(t.get('#pageBreadcrumb').textContent,'Configurações › Conta e diagnóstico');
 run("navigate('home');");
 assert.equal(t.get('#pageBreadcrumb').textContent,'Consulta individual');
 console.log('breadcrumb frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

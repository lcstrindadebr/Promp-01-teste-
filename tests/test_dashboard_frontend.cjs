const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 // setup() ran app.js, supabase.js and the first part of partners.js; Início builds on them.
 run(fs.readFileSync('dist/dashboard.js','utf8'));
 assert.equal(run('currentPage'),'dashboard','Panel opens on Início');
 assert.equal(t.get('#dashboard').classList.contains('hide'),false);
 assert.equal(t.get('#home').classList.contains('hide'),true);
 assert.equal(t.get('#pageBreadcrumb').textContent,'Início');
 assert.equal(t.window.document.querySelector('aside nav button').dataset.page,'dashboard','Início is the first menu item');

 const now=new Date().toISOString(),old='2020-01-01T12:00:00Z';
 run(`currentAccess={role:'partner',active:true,daily_limit:100,remaining:40,shared_quota:true,services:[{id:'digimais_saldo_parcela',enabled:true,allow_individual:true,allow_campaign:true}]};
 campaigns=[{id:'c1',nome:'Servidores SP',servico:'digimais_saldo_parcela',created_at:'${now}',paused:false},
  {id:'c2',nome:'Lista antiga',servico:'digimais_saldo_parcela',created_at:'${old}',paused:false}];
 records=[
  {id:'r1',lote_id:'c1',status:'Aguardando',servico:'digimais_saldo_parcela',nome:'A',cpf:'1',date:'${now}'},
  {id:'r2',lote_id:'c1',status:'Processando',servico:'digimais_saldo_parcela',nome:'B',cpf:'2',date:'${now}'},
  {id:'r3',lote_id:'c1',status:'Concluída',servico:'digimais_saldo_parcela',nome:'C',cpf:'3',date:'${now}'},
  {id:'r4',lote_id:'c2',status:'Concluída',servico:'digimais_saldo_parcela',nome:'D',cpf:'4',date:'${old}'},
  {id:'r5',lote_id:'solo',status:'Erro',servico:'digimais_saldo_parcela',nome:'Cliente com erro',cpf:'00000000191',date:'${now}'}];
 renderDashboard();`);
 assert.equal(t.get('#dashQueue').textContent,'2');assert.match(t.get('#dashQueueSub').textContent,/1 consultando/);
 assert.equal(t.get('#dashAttention').textContent,'1');
 assert.equal(t.get('#dashToday').textContent,'1','Only today counts');
 assert.equal(t.get('#dashCampaigns').textContent,'1','Finished campaigns are not in progress');
 assert.match(t.get('#dashCampaignList').textContent,/Servidores SP/);assert.match(t.get('#dashCampaignList').textContent,/1 de 3/);
 assert.doesNotMatch(t.get('#dashCampaignList').textContent,/Lista antiga/);
 assert.match(t.get('#dashboardQuota').textContent,/40 de 100 consultas disponíveis hoje/);
 assert.match(t.get('#dashAttentionList').textContent,/Cliente com erro/);

 // A record that needs attention opens the individual list filtered on it.
 t.get('[data-dashboard-record="r5"]').click();
 assert.equal(run('currentPage'),'home');assert.equal(t.get('#filter').value,'Erro');assert.equal(t.get('#search').value,'00000000191');
 assert.match(t.get('#rows').textContent,/Cliente com erro/);
 assert.equal(t.get('#dashboard').classList.contains('hide'),true);

 // Clickable counters on the individual consultation filter the list.
 t.window.document.querySelector('[data-stat-filter="grupo:atencao"]').click();
 assert.equal(t.get('#filter').value,'grupo:atencao');assert.equal(t.get('#search').value,'');
 assert.equal(t.window.document.querySelector('[data-stat-filter="grupo:atencao"]').getAttribute('aria-pressed'),'true');
 assert.match(t.get('#rows').textContent,/Cliente com erro/);

 // A campaign opens its detail.
 run("navigate('dashboard')");
 t.get('[data-dashboard-campaign="c1"]').click();
 assert.equal(run('currentPage'),'campaigns');assert.equal(run('activeCampaign'),'c1');

 // Admin: no quota banner; unlimited partner: says so.
 run("navigate('dashboard');currentAccess={...currentAccess,role:'admin'};renderDashboard()");
 assert.equal(t.get('#dashboardQuota').hidden,true);
 run("currentAccess={...currentAccess,role:'partner',daily_limit:null,remaining:null};renderDashboard()");
 assert.match(t.get('#dashboardQuota').textContent,/ilimitadas/);
 console.log('dashboard frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

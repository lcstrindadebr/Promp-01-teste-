const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
const tick=async(n=6)=>{for(let i=0;i<n;i++)await new Promise(setImmediate);};
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/tjba.js','utf8'));run(fs.readFileSync('dist/exclusao.js','utf8'));
 run(fs.readFileSync('dist/workspace.js','utf8'));
 run('function loadAmigozTables(){};function tickMonitoring(){};function loadApiTokens(){};function loadApiDocs(){};');
 run(fs.readFileSync('dist/settings.js','utf8'));
 run('function applyAccessUi(){};function resetPartnerSettings(){};');
 run(fs.readFileSync('dist/amigoz.js','utf8'));run(fs.readFileSync('dist/amigoz-coefficients.js','utf8'));
 run(fs.readFileSync('dist/simuladores.js','utf8'));
 const config=[
  {codigo:'amigoz',nome:'Amigoz',banco:'Amigoz',tipo:'amigoz',ativo:true,consultas_digimais:true,convenios:['amigoz_13','amigoz_33'],tabelas:[]},
  {codigo:'aki_siape',nome:'AKI Capital · SIAPE',banco:'AKI Capital',tipo:'coeficiente',ativo:true,consultas_digimais:true,convenios:['amigoz_13'],
   tabelas:[{codigo:'30077',nome:'CC_CP_SIAPE_PQ_F11_CO_CCC',produto:'cartao_credito',coeficiente:0.043297241,ativa:true},
    {codigo:'35445',nome:'CB_CP_SIAPE_PQ_F16_CO_CCC',produto:'cartao_beneficio',coeficiente:0.038850608,ativa:true}]}];
 const calls=[];let missing=false;
 t.handler(async(url,options)=>{
  const u=String(url),b=options?.body?JSON.parse(options.body):{};
  if(u.endsWith('/rpc/simuladores_config')){calls.push(['config']);return missing?response({code:'PGRST202',message:'missing'},404):response(config);}
  if(u.endsWith('/rpc/simular_coeficientes')){calls.push(['calc',b]);
   const base=b.p_parcela+(b.p_margem||0),tables=config[1].tabelas.filter(x=>x.produto===b.p_produto);
   return response({simulador:'aki_siape',nome:'AKI Capital · SIAPE',banco:'AKI Capital',produto:b.p_produto,parcela:b.p_parcela,margem:b.p_margem||0,saldo:b.p_saldo,base,
    tabelas:tables.map(x=>{const bruto=Math.round(base/x.coeficiente*100)/100;return {...x,bruto,liberado:Math.round((bruto-b.p_saldo)*100)/100,saldo_maior:b.p_saldo>bruto};})});}
  if(u.includes('crm_catalogo_importacao'))return response([{uf:'BR',codigo:'amigoz_13',nome:'SIAPE'},{uf:'BA',codigo:'tjba',nome:'TJBA'},{uf:'SP',codigo:'amigoz_33',nome:'Prefeitura SP'}]);
  if(u.endsWith('/rpc/admin_simulador_salvar')||u.includes('admin_simulador_tabela')){calls.push([u.split('/rpc/')[1],b]);return response(null);}
  return response([]);
 });
 run("authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600};currentAccess={role:'admin',active:true};");
 await run('loadSimuladores(true)');
 const digi={id:'d1',servico:'digimais_saldo_parcela',status:'Concluída',saldo:5000,valorParcela:300,cpf:'00000000191',nome:'Cliente Digi'};
 const tjba={id:'t1',servico:'tjba_margem',status:'Concluída',convenio:'tjba',cpf:'00000000272',nome:'Cliente TJBA'};
 run(`window.__digi=${JSON.stringify(digi)};window.__tjba=${JSON.stringify(tjba)}`);
 // Digi+: Amigoz and AKI Capital; ConsigX TJBA: none; waiting: none.
 const digiHtml=run('amigozAction(window.__digi)');
 assert.match(digiHtml,/data-simulate="d1">Simular Amigoz/);assert.match(digiHtml,/data-simulate-coef="aki_siape" data-job="d1">Simular AKI Capital/);
 assert.equal(run('amigozAction(window.__tjba)'),'','No simulator on TJBA');
 assert.equal(run("amigozAction({...window.__digi,status:'Processando'})"),'');
 // CRM: SIAPE client gets both; unknown agreement gets none.
 assert.deepEqual(run("crmSimuladorButtons({cpf:'1',nome:'X'},['amigoz_13']).map(b=>b.textContent)"),['Simular Amigoz','Simular AKI Capital']);
 assert.equal(run("crmSimuladorButtons({cpf:'1',nome:'X'},['tjba']).length"),0);

 // AKI window from a Digi+ consultation: prefilled and calculated on open.
 run("records=[window.__digi];render();");
 await run("openCoefSimulator({simulador:'aki_siape',jobId:'d1',cpf:'00000000191',nome:'Cliente Digi',parcela:300,saldo:5000})");await tick();
 assert.equal(t.get('#coefPanel').hidden,false);assert.equal(t.get('#appShell').inert,true);
 assert.equal(t.get('#coefParcela').value,'300,00');assert.equal(t.get('#coefSaldo').value,'5.000,00');
 let calc=calls.filter(c=>c[0]==='calc').at(-1)[1];
 assert.deepEqual(calc,{p_simulador:'aki_siape',p_produto:'cartao_beneficio',p_parcela:300,p_margem:0,p_saldo:5000,p_job_id:'d1',p_convenio:''});
 assert.match(t.get('#coefCards').textContent,/Tabela 35445/);assert.match(t.get('#coefCards').textContent,/R\$\s*2\.721,89/);
 assert.match(t.get('#coefBase').textContent,/parcela, sem margem/);
 // Credit card product: all its tables; best release highlighted.
 t.get('#coefProduto').value='cartao_credito';t.get('#coefProduto').onchange();await tick();
 assert.equal(calls.filter(c=>c[0]==='calc').at(-1)[1].p_produto,'cartao_credito');
 assert.match(t.get('#coefCards').innerHTML,/Maior valor liberado/);
 // Margin checkbox without value blocks; with value, base includes it. Changes mark results as stale.
 t.get('#coefUsarMargem').checked=true;t.get('#coefUsarMargem').onchange();
 assert.equal(t.get('#coefStale').hidden,false);
 const before=calls.length;await t.get('#coefForm').onsubmit({preventDefault(){}});
 assert.equal(calls.length,before,'No call without margin');assert.match(t.get('#coefStatus').textContent,/margem não foi informada/);
 t.get('#coefMargem').value='50,00';await t.get('#coefForm').onsubmit({preventDefault(){}});await tick();
 calc=calls.filter(c=>c[0]==='calc').at(-1)[1];assert.equal(calc.p_margem,50);
 assert.match(t.get('#coefBase').textContent,/parcela R\$\s*300,00 \+ margem R\$\s*50,00/);assert.equal(t.get('#coefStale').hidden,true);
 // Balance above gross is flagged.
 t.get('#coefSaldo').value='99.999,00';await t.get('#coefForm').onsubmit({preventDefault(){}});await tick();
 assert.match(t.get('#coefCards').textContent,/Saldo devedor maior que o valor bruto/);
 // Escape closes.
 t.get('#coefPanel').onkeydown({key:'Escape',preventDefault(){}});assert.equal(t.get('#coefPanel').hidden,true);

 // Settings: admin sees the tab, edits agreements and tables, saves.
 run('applyAccessUi()');assert.equal(t.get('#settings-tab-simuladores').hidden,false);
 run("navigate('settings');switchSettings('simuladores')");await tick(10);
 const card=t.get('#simSettingsList').querySelector('[data-sim="aki_siape"]');
 assert.ok(card);assert.equal(card.querySelector('[data-sim-count]').textContent,'1');
 card.querySelector('[data-sim-convenio][value="amigoz_33"]').checked=true;
 card.querySelector('[data-sim-convenio][value="amigoz_33"]').dispatchEvent(new t.window.Event('change',{bubbles:true}));
 assert.equal(card.querySelector('[data-sim-count]').textContent,'2');
 card.querySelector('[data-sim-digimais]').checked=false;
 card.querySelector('[data-t="coeficiente"]').value='0,05';
 card.querySelector('[data-sim-remove-table]').closest('tr').nextElementSibling.querySelector('[data-sim-remove-table]').click();
 calls.length=0;card.querySelector('[data-sim-save]').click();await tick(12);
 const saved=calls.find(c=>c[0]==='admin_simulador_salvar')[1];
 assert.deepEqual(saved,{p_codigo:'aki_siape',p_ativo:true,p_consultas_digimais:false,p_convenios:['amigoz_13','amigoz_33']});
 assert.deepEqual(calls.filter(c=>c[0]==='admin_simulador_tabela_excluir').map(c=>c[1].p_codigo),['35445']);
 const table=calls.find(c=>c[0]==='admin_simulador_tabela_salvar')[1];
 assert.equal(table.p_codigo,'30077');assert.equal(table.p_coeficiente,0.05);
 // Invalid coefficient is refused before any call.
 const card2=t.get('#simSettingsList').querySelector('[data-sim="aki_siape"]');
 card2.querySelector('[data-t="coeficiente"]').value='abc';calls.length=0;card2.querySelector('[data-sim-save]').click();await tick();
 assert.equal(calls.length,0);assert.match(card2.querySelector('[data-sim-status]').textContent,/coeficiente/);
 // Partner: no tab.
 run("currentAccess={role:'partner',active:true};applyAccessUi()");assert.equal(t.get('#settings-tab-simuladores').hidden,true);

 // Older database: simulator list missing → legacy Amigoz button, as before.
 run('showLogin()');run("authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600};currentAccess={role:'admin',active:true};");
 missing=true;await run('loadSimuladores(true)');
 assert.match(run('amigozAction(window.__digi)'),/Simular Amigoz/);
 console.log('simuladores frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

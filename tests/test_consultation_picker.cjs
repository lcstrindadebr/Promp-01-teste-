const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {setup, response} = require('./test_frontend.cjs');

// Real page in jsdom: amigoz-api.js adds the provider picker and the Amigoz panel to the DOM.
(async () => {
 const t = setup(), run = code => vm.runInContext(code, t.ctx), $ = s => t.window.document.querySelector(s);
 run('function applyAccessUi(){};function loadAmigozTables(){};function loadApiTokens(){};function loadApiDocs(){};');
 for (const file of ['monitoramento', 'settings']) run(fs.readFileSync(`dist/${file}.js`, 'utf8')); // page order
 t.handler(async () => response({data: [{uf: 'BA', id: 1, nome: 'Fixture'}]}));
 run("authenticated=true;session={access_token:'fixture',expires_at:Date.now()/1000+3600};currentAccess={active:true,role:'partner',allow_amigoz:false};currentPage='home'");
 let changed = 0;
 const services = $('#serviceSelect');
 const previousChange = services.onchange;
 services.onchange = () => { changed++; previousChange?.(); };
 run(fs.readFileSync('dist/amigoz-api.js', 'utf8'));
 run('applyAccessUi()');
 const picker = $('.consultation-picker'), panel = $('.amigoz-consult-card');
 const radio = value => picker.querySelector(`input[value="${value}"]`);
 const hidden = value => radio(value).hidden || radio(value).closest('label').hidden;
 assert.equal(hidden('amigoz'), true, 'Amigoz is hidden without permission');
 assert.equal($('#settings-tab-amigoz-api')?.hidden ?? true, true);
 radio('tjba_margem').checked = true;
 await picker.onchange({target: radio('tjba_margem')});
 assert.equal(changed, 1);
 assert.equal(services.value, 'tjba_margem');
 assert.equal($('#home').classList.contains('individual-consigx'), true);
 run('currentAccess.allow_amigoz=true;applyAccessUi()');
 assert.equal(hidden('amigoz'), false);
 radio('amigoz').checked = true;
 await picker.onchange({target: radio('amigoz')});
 assert.equal(panel.hidden, false);
 assert.equal($('#single').closest('.card').hidden, true);
 assert.equal($('#results').hidden, true);
 run('currentAccess.allow_amigoz=false;applyAccessUi()');
 assert.equal(panel.hidden, true);
 assert.equal($('#results').hidden, false);
 assert.equal($('#single').closest('.card').hidden, false);
 console.log('PASS: seleção de provedor, campos e histórico respeitam as permissões');
})().catch(error => {console.error(error); process.exitCode = 1;});

const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();vm.runInContext(fs.readFileSync('dist/amigoz.js','utf8'),t.ctx);vm.runInContext(fs.readFileSync('dist/exclusao.js','utf8'),t.ctx);vm.runInContext(fs.readFileSync('dist/tjba.js','utf8'),t.ctx);
 t.get('#serviceSelect').value='tjba_margem';t.get('#serviceSelect').onchange();assert.equal(t.get('#nome').required,false);assert.equal(t.get('#telefone').required,false);assert(t.get('#individualHead').innerHTML.includes('Empréstimo disponível'));assert(!t.get('#individualHead').innerHTML.includes('Saldo devedor'));
 await t.get('#file').onchange({target:{files:[{name:'tjba.csv',size:30,text:async()=> 'cpf\n123456789\n00000000191'}]}});
 assert.equal(vm.runInContext('pending.length',t.ctx),2);assert.equal(vm.runInContext('pending[0].cpf',t.ctx),'00123456789');
 vm.runInContext("authenticated=true;session={access_token:'test',expires_at:Date.now()/1000+3600,user:{id:'owner'}}",t.ctx);let created, saved;
 t.handler(async(u,o)=>{if(u.includes('create_consigx_campaign')){created=JSON.parse(o.body);return response('campaign')}if(u.includes('save_tjba_credentials')){saved=JSON.parse(o.body);return response(null)}if(u.includes('tjba_credentials_status'))return response({configured:true,username:'test',enabled:false});return response([])});
 t.get('#convenioSelect').value='embasa';t.get('#campaignName').value='EMBASA';await t.get('#import').onclick();assert.equal(created.p_items.length,2);assert.equal(created.p_convenio,'embasa');assert(!('p_servico' in created));
 t.get('#tjbaUsername').value='test';t.get('#tjbaPassword').value='fake-secret';t.get('#tjbaEnabled').checked=false;await t.get('#tjbaCredentials').onsubmit({preventDefault(){}});assert.equal(saved.p_password,'fake-secret');assert.equal(t.get('#tjbaPassword').value,'');assert(!t.get('#tjbaCredentialStatus').textContent.includes('fake-secret'));
 vm.runInContext("records=[{id:'t',servico:'tjba_margem',cpf:'00123456789',nome:'TESTE',status:'Concluída',tjba_status:'consultado',emprestimo_disponivel:'0.00',cartao_disponivel:'-10.25',matricula:'000123',date:'2026-11-02',progress:100},{id:'d',servico:'digimais_saldo_parcela',nome:'DIGI',status:'Concluída',saldo:999,valorParcela:55}];render()",t.ctx);
 assert(t.get('#rows').innerHTML.includes('000123'));assert(t.get('#rows').innerHTML.includes('0,00'));assert(/-R\$[^<]*10,25/.test(t.get('#rows').innerHTML));assert(!t.get('#rows').innerHTML.includes('DIGI'));assert(!t.get('#rows').innerHTML.includes('Simular Amigoz'));
 t.get('#filter').value='tjba:revisao_matricula';vm.runInContext('render()',t.ctx);assert(!t.get('#rows').innerHTML.includes('000123'));
 t.get('#serviceSelect').value='digimais_saldo_parcela';t.get('#serviceSelect').onchange();assert(t.get('#rows').innerHTML.includes('DIGI'));assert(!t.get('#rows').innerHTML.includes('000123'));assert.equal(t.get('#telefone').required,true);
 vm.runInContext('showLogin()',t.ctx);assert.equal(t.get('#tjbaUsername').value,'');
 console.log('PASS: TJBA selection, CPF-only import, normalized leading zeros, separate campaign RPC, password clearing, zero/negative margins, no Digi+ mixing, subtype filter and logout');
})().catch(e=>{console.error(e);process.exitCode=1});

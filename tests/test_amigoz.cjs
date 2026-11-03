const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
(async()=>{
const t=setup();vm.runInContext(fs.readFileSync('dist/amigoz.js','utf8'),t.ctx);
assert(vm.runInContext("amigozAction({id:'x',saldo:1,valorParcela:1,status:'Concluída'})",t.ctx).includes('data-simulate'));
assert(!vm.runInContext("amigozAction({id:'x',saldo:1,valorParcela:null,status:'Revisão'})",t.ctx).includes('data-simulate'));
vm.runInContext("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600,user:{id:'u'}};records=[{id:'j',nome:'TESTE',saldo:1000,valorParcela:179.37,status:'Concluída'}]",t.ctx);
t.handler(async()=>response({job_id:'j',saldo:1000,parcela:179.37,tabelas:[{taxa:3,quitacao:1000,troco:3780.17,percentual:5,comissao:239.01},{taxa:3.25,quitacao:1000,troco:100,percentual:null,comissao:null}]}));
await vm.runInContext("simulateAmigoz('j')",t.ctx);
assert(t.get('#amigozCards').innerHTML.includes('239,01'));
assert.equal((t.get('#amigozCards').innerHTML.match(/Comissão estimada do vendedor/g)||[]).length,1);
let requestBody;
t.handler(async(u,o)=>{requestBody=JSON.parse(o.body);return response({job_id:'j',saldo:1000,parcela:179.37,parcela_simulada:243.25,margem_adicional:63.88,tabelas:[{taxa:3,limite:7633.48,quitacao:1000,troco:6633.48,percentual:5,comissao:381.67}]})});
t.get('#amigozAlterarParcela').checked=true;t.get('#amigozAlterarParcela').onchange();t.get('#amigozNovaParcela').value='243.25';t.get('#amigozPrazo').value='96';
await vm.runInContext("simulateAmigoz('j')",t.ctx);
assert.equal(requestBody.p_condicoes._parcela_simulada,243.25);for(const rate of [3,3.25,3.5,3.75,3.98,4.5,4.8])assert.deepEqual(requestBody.p_condicoes[String(rate)],{encargos_modo:'sem_encargos'});assert(!t.get('#amigozCards').innerHTML.includes('cost-mode-'));assert(!t.get('#amigozCards').innerHTML.includes('Custos e teto'));assert(t.get('#amigozCards').innerHTML.includes('estimativa antes dos encargos'));assert.equal(requestBody.p_prazo,96);assert.equal(vm.runInContext('records[0].valorParcela',t.ctx),179.37);
assert(t.get('#amigozCards').innerHTML.includes('7.633,48'));assert(t.get('#amigozMarginInfo').textContent.includes('63,88'));

vm.runInContext('records[0].saldo=2000;refreshAmigoz()',t.ctx);assert(t.get('#amigozCards').hidden);assert(!t.get('#amigozStale').hidden);
vm.runInContext('resetAmigoz()',t.ctx);assert(t.get('#amigozPanel').hidden);assert.equal(t.get('#amigozCards').innerHTML,'');
console.log('PASS: eligibility, conditional commission, stale simulation and logout cleanup');
})().catch(e=>{console.error(e);process.exitCode=1});

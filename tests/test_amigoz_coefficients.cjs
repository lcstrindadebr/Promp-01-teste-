const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const {setup,response} = require('./test_frontend.cjs');

(async () => {
  const t = setup();
  t.ctx.document.createElement = () => ({hidden:false,innerHTML:'',className:''});
  t.ctx.Option = function(text,value) {this.text=text;this.value=value;};
  t.ctx.setInterval = () => {};
  const ids = ['#amigozAgreement','#amigozMarginSelect','#amigozCards','#amigozClose'];
  for (const id of ids) Object.assign(t.get(id), {replaceChildren(){},add(){},focus(){},setAttribute(){}});
  t.get('#settings-commissions').appendChild = () => {};
  vm.runInContext('function applyAccessUi(){};function exportResults(){};',t.ctx);
  vm.runInContext(fs.readFileSync('dist/amigoz.js','utf8'),t.ctx);
  vm.runInContext(fs.readFileSync('dist/amigoz-coefficients.js','utf8'),t.ctx);
  vm.runInContext("authenticated=true;currentAccess={active:true,role:'admin'};session={access_token:'fixture',expires_at:Date.now()/1000+3600};",t.ctx);
  const margin={key:'a',elegivel:true,produto:'beneficio',valor:50,convenio:'amigoz_23',matricula:'A',instituicao:'amigoz',observado_em:'2026-11-11T12:00:00Z'};
  const source={saldo:200,parcela:200};
  const context={cpf:'00000000191',convenio:'amigoz_23',elegivel:true,fonte:source,version_id:1,config:{eligibilidade:[{convenio:'amigoz_23'}]},margens:[margin]};
  const result={cpf:'00000000191',convenio:'amigoz_23',fonte:source,base:250,margem_adicional:50,margem_selecionada:margin,version_id:1,prazo:96,motivo:'Simulação preliminar',tabelas:[{taxa:3,troco:4938.77,limite:7497.5,quitacao:200,limite_restante:7297.5,regra_calculo:"limite_residual_v1",situacao:"pre_aprovada_com_troco"}]};
  t.handler(async (url,options) => {
    if(url.includes('simulation_context')) return response(context);
    if(url.includes('simular_coeficientes')) return response(result);
    if(url.includes('exportar_estimativas')) return response(JSON.parse(options.body).p_items.map(()=>result));
    return response([]);
  });
  await vm.runInContext("openAmigozClient('00000000191','amigoz_23',null,'Fixture')",t.ctx);
  t.get('#amigozBaseMode').value='aggregate';t.get('#amigozMarginSelect').value='a';t.get('#amigozManualTotal').value='';
  await t.get('#amigozCoefficientCalculate').onclick();
  assert(t.get('#amigozCards').innerHTML.includes('4.938,77'));
  assert.equal(JSON.parse(t.calls.at(-1)[1].body).p_input.mode,'aggregate');
  t.get('#amigozBaseMode').value='manual';t.get('#amigozManualTotal').value='229.37';
  await t.get('#amigozCoefficientCalculate').onclick();
  assert.equal(JSON.parse(t.calls.at(-1)[1].body).p_input.manual,229.37);
  const rows=await vm.runInContext("amigozAppendExport([['CPF'],['000.000.001-91']],[{cpf:'00000000191'}])",t.ctx);
  assert.equal(rows[0].length,12);assert.equal(rows[1].length,12);assert.equal(rows[1][1],4938.77);
  assert.equal(rows[1][2],''); // An unavailable rate must not become a numeric zero.
  const originalCard=result.tabelas[0];
  for(const [state,limit,debt,label] of [
    ['limite_insuficiente',9612.69,11131.31,'Limite insuficiente'],
    ['pre_aprovada_sem_troco',5998,5598,'Pré-aprovada sem troco']]){
    result.tabelas=[{...originalCard,situacao:state,troco:0,limite:limit,quitacao:debt}];
    await t.get('#amigozCoefficientCalculate').onclick();
    assert(t.get('#amigozCards').innerHTML.includes(label));
    assert(t.get('#amigozCards').innerHTML.includes('R$ 0,00'));
  }
  result.tabelas=[{...originalCard,regra_calculo:undefined}];
  await t.get('#amigozCoefficientCalculate').onclick();
  assert(t.get('#amigozCards').innerHTML.includes('cálculo antigo foi bloqueado'));
  await assert.rejects(vm.runInContext("amigozExportEstimates([{cpf:'00000000191'}])",t.ctx),/Atualize o cálculo/);
  result.tabelas=[originalCard];
  let marginCalls=0;
  t.ctx.window.consultarMargemAmigozSimulador=async input=>{
    marginCalls++;assert.equal(input.cpf,'00000000191');assert.equal(input.convenio,'amigoz_23');
    assert.equal(input.senha,'test-only');return {salvo_no_historico:true,margem:{status:'respondido'}};
  };
  t.get('#amigozQueryRegistration').value='';t.get('#amigozQueryPassword').value='test-only';
  await t.get('#amigozQueryMargin').onclick();
  assert.equal(marginCalls,1);assert.equal(t.get('#amigozQueryPassword').value,'');
  assert(t.get('#amigozQueryMarginStatus').textContent.includes('Margem atualizada'));
  t.ctx.window.consultarMargemAmigozSimulador=async()=>({salvo_no_historico:false,margem:{status:'respondido'}});
  await t.get('#amigozQueryMargin').onclick();
  assert(t.get('#amigozQueryMarginStatus').textContent.includes('Não repita'));
  context.version_id=2;
  await vm.runInContext('refreshAmigoz()',t.ctx);
  assert.equal(t.get('#amigozCards').innerHTML,'');
  vm.runInContext('resetAmigoz()',t.ctx);
  assert.equal(t.get('#amigozPanel').hidden,true);
  console.log('PASS: coefficient inputs, cards, six export columns, stale results and logout');
})().catch(error=>{console.error(error);process.exitCode=1;});

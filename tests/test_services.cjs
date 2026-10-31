const {setup,response}=require('./test_frontend.cjs');const vm=require('vm'),assert=require('assert');
(async()=>{
 const t=setup();vm.runInContext("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600,user:{id:'u'}}",t.ctx);let payload;
 t.handler(async(u,o)=>{if(u.includes('create_consulta_campaign')){payload=JSON.parse(o.body);return response('c')}return response([])});
 t.get('#serviceSelect').value='margem';await assert.rejects(vm.runInContext("createCampaign('Teste',[{nome:'TESTE',cpf:'00123456789',telefone:'11999999999'}])",t.ctx),/disponível/);assert.equal(t.calls.length,0);
 t.get('#serviceSelect').value='digimais_saldo_parcela';await vm.runInContext("createCampaign('Teste',[{nome:'TESTE',cpf:'00123456789',telefone:'11999999999'}])",t.ctx);assert.equal(payload.p_servico,'digimais_saldo_parcela');
 t.handler(async(u,o)=>{if(o.method==='POST'&&u.includes('consulta_lotes')){assert.equal(JSON.parse(o.body).servico,'digimais_saldo_parcela');return response([{id:'lot'}])}if(o.method==='POST'&&u.includes('consulta_jobs'))assert.equal(JSON.parse(o.body)[0].servico,'digimais_saldo_parcela');return response([])});
 await vm.runInContext("add([{nome:'TESTE',cpf:'00123456789',telefone:'11999999999'}])",t.ctx);
 assert(vm.runInContext("rowsHTML([{id:'x',nome:'TESTE',status:'Concluída',servico:'digimais_saldo_parcela'}])",t.ctx).includes('Digi+ · Saldo devedor e parcela'));
 console.log('PASS: service selection, future-service rejection, individual/campaign persistence and history label');
})().catch(e=>{console.error(e);process.exitCode=1});

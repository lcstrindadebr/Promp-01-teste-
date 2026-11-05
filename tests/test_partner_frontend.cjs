const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();vm.runInContext(fs.readFileSync('dist/partners.js','utf8').split('const quotaBox=')[0],t.ctx);
 vm.runInContext("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600,user:{id:'p'}};currentAccess={role:'partner',active:true,services:[{id:'digimais_saldo_parcela',enabled:true,allow_individual:true,daily_limit:2,remaining:1,allow_campaign:false}]}",t.ctx);
 vm.runInContext("assertCanSubmit('digimais_saldo_parcela','individual')",t.ctx);
 assert.throws(()=>vm.runInContext("assertCanSubmit('digimais_saldo_parcela','campaign')",t.ctx),/Campanhas/);
 assert.throws(()=>vm.runInContext("assertCanSubmit('tjba_margem','individual')",t.ctx),/não está liberado/);
 vm.runInContext('currentAccess.services[0].remaining=0',t.ctx);
 assert.throws(()=>vm.runInContext("assertCanSubmit('digimais_saldo_parcela','individual')",t.ctx),/Limite diário/);
 vm.runInContext('currentAccess.services[0].remaining=1',t.ctx);let payload;
 t.handler(async(u,o)=>{if(u.includes('create_individual_consulta')){payload=JSON.parse(o.body);return response('job-id')}return response([])});
 await vm.runInContext("add([{nome:'TEST',cpf:'00000000191',telefone:'11999999999'}],'digimais_saldo_parcela')",t.ctx);
 assert.equal(payload.p_servico,'digimais_saldo_parcela');assert.equal(payload.p_item.cpf,'00000000191');assert(!t.calls.some(([u,o])=>u.includes('/consulta_lotes')&&o?.method==='POST'));
 console.log('PASS: partner service/campaign/quota guards and atomic individual submission');
})().catch(e=>{console.error(e);process.exitCode=1});

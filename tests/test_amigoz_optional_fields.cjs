const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
test('PM SP can submit margin and saque with CPF and no registration/password',()=>{
 const source=fs.readFileSync('dist/amigoz-api.js','utf8');
 const start=source.indexOf('function updateAmigozConvenio()');
 const end=source.indexOf("$('#amigozState').onchange",start);
 const fields={};
 const $=id=>fields[id]??={value:'',required:true};
 $('#amigozConvenio').value='33';$('#amigozMode').value='ambos';
 const context=vm.createContext({$,amigozCatalog:[{id:33,averbadora:9,matricula_obrigatoria:true,senha_servidor:true,produtos:[]}]});
 vm.runInContext(source.slice(start,end),context);context.updateAmigozConvenio();
 assert.equal($('#amigozRegistration').required,false);
 assert.equal($('#amigozServerPassword').required,false);
 assert.match(source,/<details id="amigozExtraMargin"/);
});

test('simulator margin adapter reuses authenticated route and validates agreement',async()=>{
 const source=fs.readFileSync('dist/amigoz-api.js','utf8');
 const start=source.indexOf('window.consultarMargemAmigozSimulador=');
 const end=source.indexOf('function updateAmigozPanel()',start);
 const calls=[];let allowed=true;
 const ctx=vm.createContext({window:{},amigozCanConsult:()=>allowed,amigozCatalog:[],amigozRequest:async(route,payload)=>{
  calls.push({route,payload});return route==='convenios'?[{id:23,averbadora:9,senha_servidor:false}]:{salvo_no_historico:true,margem:{status:'respondido'}};
 }});
 vm.runInContext(source.slice(start,end),ctx);
 await ctx.window.consultarMargemAmigozSimulador({cpf:'00000000191',convenio:'amigoz_23',senha:'discard'});
 assert.equal(calls.length,2);assert.equal(calls[1].route,'consultar');
 assert.deepEqual(JSON.parse(JSON.stringify(calls[1].payload)),{modo:'margem',convenio_id:23,cpf:'00000000191'});
 allowed=false;
 await assert.rejects(ctx.window.consultarMargemAmigozSimulador({convenio:'amigoz_23'}),/não liberado/);
 allowed=true;
 await assert.rejects(ctx.window.consultarMargemAmigozSimulador({convenio:'tjba'}),/Selecione/);
 await assert.rejects(ctx.window.consultarMargemAmigozSimulador({convenio:'amigoz_999'}),/indisponível/);
 assert.equal(calls.length,2);
});

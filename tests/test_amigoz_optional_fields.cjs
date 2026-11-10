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

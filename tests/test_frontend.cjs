const fs=require('fs'),vm=require('vm'),assert=require('assert');
function setup(stored){
 const nodes=new Map();function element(){return {value:'',textContent:'',innerHTML:'',hidden:false,disabled:false,classList:{add(){},remove(){},toggle(){}},querySelector(){return element()}}}
 const get=s=>{if(!nodes.has(s))nodes.set(s,element());return nodes.get(s)};get('#appShell').hidden=true;
 const data=new Map(stored||[]),storage={getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k)};
 const calls=[];let handler=async()=>({ok:true,status:200,text:async()=>JSON.stringify([])});
 const ctx={document:{querySelector:get,querySelectorAll:()=>[]},window:{SUPABASE_CONFIG:{url:'https://test.supabase.co',key:'sb_publishable_test'}},sessionStorage:storage,setTimeout:()=>{},setInterval:()=>{},AbortSignal:{timeout:()=>undefined},fetch:async(u,o)=>{calls.push([u,o]);return handler(u,o)},console};vm.createContext(ctx);
 vm.runInContext(fs.readFileSync('dist/app.js','utf8'),ctx);vm.runInContext(fs.readFileSync('dist/supabase.js','utf8'),ctx);
 return {ctx,get,calls,handler:f=>handler=f};
}
const response=(data,status=200)=>({ok:status<400,status,text:async()=>JSON.stringify(data)});
(async()=>{
 const t=setup();assert.equal(t.calls.length,0,'No data request before login');assert.equal(t.get('#appShell').hidden,true);
 await assert.rejects(vm.runInContext('add([{nome:"X",cpf:"00000000000",telefone:"11999999999"}])',t.ctx),/Entre/);
 t.handler(async u=>u.includes('/token?')?response({access_token:'test',refresh_token:'test',expires_in:3600,user:{id:'user1',email:'test@example.com'}}):response([]));
 t.get('#email').value='test@example.com';t.get('#password').value='password';await t.get('#login').onsubmit({preventDefault(){}});assert.equal(t.get('#appShell').hidden,false);assert.equal(t.get('#loginPage').hidden,true);
 await t.get('#logout').onclick();assert.equal(t.get('#appShell').hidden,true);assert.equal(t.get('#loginPage').hidden,false);
 const bad=setup();bad.handler(async()=>response({msg:'Invalid login credentials'},400));await bad.get('#login').onsubmit({preventDefault(){}});assert.equal(bad.get('#appShell').hidden,true);assert.match(bad.get('#loginError').textContent,/inválidos/);
 const stale=setup([['apoiarcred-auth:https://test.supabase.co',JSON.stringify({access_token:'revoked',refresh_token:'x',expires_at:Date.now()/1000+3600})]]);stale.handler(async()=>response({},401));await new Promise(setImmediate);assert.equal(stale.get('#appShell').hidden,true,'Revoked stored session must not open dashboard');
 const rows=vm.runInContext('csvParse("nome;cpf;telefone\\nCliente;00123456789;11999999999")',t.ctx);assert.equal(rows[1][1],'00123456789');
 const model=fs.readFileSync('dist/modelo-importacao.csv','utf8');assert(model.includes('nome;cpf;telefone'));
 assert(!fs.readFileSync('dist/index.html','utf8').includes('id="mode"'));console.log('PASS: login gate, login failure, logout, revoked session, authenticated-only requests, CSV and no mode selector');
})().catch(e=>{console.error(e);process.exitCode=1});

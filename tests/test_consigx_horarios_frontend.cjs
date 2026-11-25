const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 for(const file of ['tjba','exclusao','workspace','campaign-detail','campaign-server','consigx-horarios'])run(fs.readFileSync(`dist/${file}.js`,'utf8'));
 // Hours in Brasília (UTC-3): SAEB 07:00–20:00, SUPREV 07:00–22:00, TJBA always.
 const at=iso=>run(`new Date('${iso}')`);
 const open=(c,iso)=>vm.runInContext(`consigxHorario('${c}',new Date('${iso}'))?.aberto`,t.ctx);
 assert.equal(open('saeb','2026-11-25T22:59:00Z'),true);assert.equal(open('saeb','2026-11-25T23:00:00Z'),false);
 assert.equal(open('suprev','2026-11-26T00:59:00Z'),true);assert.equal(open('suprev','2026-11-26T01:00:00Z'),false);
 assert.equal(open('saeb','2026-11-26T09:59:00Z'),false);assert.equal(open('saeb','2026-11-26T10:00:00Z'),true);
 assert.equal(run("consigxHorario('tjba')"),null);

 // Force "closed now" for the rest of the test.
 run("const realHorario=consigxHorario;consigxHorario=(c)=>{const h=realHorario(c);return h&&{...h,aberto:false};}");
 // Campaign: shows when it resumes; manual pause and other services stay as they were.
 assert.equal(run("campaignPhaseLabel({servico:'tjba_margem',convenio:'saeb',paused:false},[{status:'Aguardando'}])"),'Fora do horário · retoma às 07:00');
 assert.equal(run("campaignPhaseLabel({servico:'tjba_margem',convenio:'saeb',paused:true},[{status:'Aguardando'}])"),'Pausada');
 assert.equal(run("campaignPhaseLabel({servico:'tjba_margem',convenio:'saeb',paused:false},[{status:'Processando'}])"),'Em andamento','A job already running finishes');
 assert.equal(run("campaignPhaseLabel({servico:'tjba_margem',convenio:'tjba',paused:false},[{status:'Aguardando'}])"),'Na fila');
 assert.equal(run("campaignPhaseLabel({servico:'digimais_saldo_parcela',paused:false},[{status:'Aguardando'}])"),'Na fila');

 // Individual consultation waiting outside hours reads as scheduled.
 t.get('#serviceSelect').value='tjba_margem';t.get('#serviceSelect').onchange();
 run(`records=[{id:'a',servico:'tjba_margem',convenio:'saeb',cpf:'00000000191',nome:'AGENDADA',status:'Aguardando',date:'2026-11-25',progress:0},
  {id:'b',servico:'tjba_margem',convenio:'tjba',cpf:'00000000272',nome:'TJBA',status:'Aguardando',date:'2026-11-25',progress:0},
  {id:'c',servico:'tjba_margem',convenio:'suprev',cpf:'11614200530',nome:'MIGRADA',status:'Concluída',emprestimo_disponivel:'321.00',cartao_disponivel:null,matricula:'900',message:'Matrícula migrada no SAEB; margem consultada no SUPREV.',date:'2026-11-25',progress:100},
  {id:'d',servico:'tjba_margem',convenio:'tjba',cpf:'00000000353',nome:'CARTAO',status:'Concluída',emprestimo_disponivel:'1.00',cartao_disponivel:null,date:'2026-11-25',progress:100}];campaigns=[];navigate('home');render();`);
 const row=name=>[...t.get('#rows').querySelectorAll('tr')].find(r=>r.textContent.includes(name)).textContent;
 assert.match(row('AGENDADA'),/Agendada · começa às 07:00/);assert.doesNotMatch(row('TJBA'),/Agendada/);
 // SUPREV/SAEB have no card margin; the SAEB migration note shows on the row (the panel's real renderer, workspace.js).
 assert.match(row('MIGRADA'),/Não se aplica/);assert.match(row('MIGRADA'),/Matrícula migrada no SAEB; margem consultada no SUPREV\./);
 assert.doesNotMatch(row('CARTAO'),/Não se aplica/,'TJBA without card value still shows —');

 // Agreement hint and the notice after sending.
 t.get('#convenioSelect').value='suprev';t.get('#convenioSelect').onchange();
 assert.match(t.get('#consigxHoursHint').textContent,/SUPREV atende das 07:00 às 22:00 \(horário de Brasília\)\. Agora está fora do horário/);
 t.get('#convenioSelect').value='tjba';t.get('#convenioSelect').onchange();assert.equal(t.get('#consigxHoursHint').hidden,true);
 t.get('#convenioSelect').value='saeb';t.get('#convenioSelect').onchange();
 run("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600};currentAccess={role:'admin',active:true,services:[]}");
 t.handler(async()=>response([]));
 await run("add([{nome:'',cpf:'00000000191',telefone:''}],'tjba_margem','saeb')");
 assert.match(t.get('#toast').textContent,/Agendada: o SAEB atende das 07:00 às 20:00/);
 console.log('consigx horarios frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

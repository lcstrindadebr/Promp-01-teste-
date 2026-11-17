const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/tjba.js','utf8'));run(fs.readFileSync('dist/workspace.js','utf8').split('// Reuse the existing inputs')[0]);
 run(fs.readFileSync('dist/mobile-tables.js','utf8'));
 assert.ok(t.get('#rows').closest('table').classList.contains('responsive-table'));
 run(`records=[{id:'a',lote_id:'x',status:'Erro',nome:'Ana',cpf:'00000000191',servico:'digimais_saldo_parcela',date:'2026-11-17'}];render();`);
 await new Promise(r=>setTimeout(r,0));
 const cells=[...t.get('#rows').rows[0].cells].map(c=>c.dataset.label);
 const heads=[...t.get('#rows').closest('table').querySelectorAll('thead th')].map(th=>th.textContent.trim());
 assert.deepEqual(cells,heads,'Each cell carries its column name');
 // Switching to ConsigX changes the columns; labels follow.
 run(`$('#serviceSelect').value='tjba_margem';$('#serviceSelect').onchange();records=[{id:'b',lote_id:'x',status:'Concluída',nome:'Bia',cpf:'00000000272',servico:'tjba_margem',date:'2026-11-17'}];render();`);
 await new Promise(r=>setTimeout(r,0));
 assert.ok([...t.get('#rows').rows[0].cells].some(c=>c.dataset.label==='Empréstimo'));
 // The empty-state row spans every column and gets no label.
 run(`records=[];render();`);await new Promise(r=>setTimeout(r,0));
 assert.equal(t.get('#rows').rows[0].cells[0].dataset.label,undefined);
 console.log('mobile tables frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});

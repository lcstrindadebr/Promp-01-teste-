const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function element() {
 const classes = new Set();
 return {
  value: '', hidden: false, disabled: false,
  classList: {toggle(name, value) { if (value) classes.add(name); else classes.delete(name); }, contains: name => classes.has(name)},
  before() {}, appendChild() {}, replaceChildren() {}, reset() {},
  closest() { return this; },
 };
}

(async () => {
 const els = new Map();
 const select = id => {
  if (!els.has(id)) els.set(id, element());
  return els.get(id);
 };
 const radios = ['digimais_saldo_parcela', 'tjba_margem', 'amigoz'].map(value => ({...element(), value}));
 const picker = element();
 picker.querySelectorAll = () => radios;
 const panel = element();
 const services = select('#serviceSelect');
 services.options = radios.slice(0, 2).map(({value}) => ({value, disabled: false}));
 services.value = radios[0].value;
 let changed = 0;
 services.onchange = () => changed++;
 const context = vm.createContext({
  $: select, document: {createElement: (() => { const nodes = [picker, panel]; return () => nodes.shift() || element(); })()},
  authenticated: true, currentAccess: {active: true, role: 'partner', allow_amigoz: false}, currentPage: 'home',
  authEpoch: 0, applyAccessUi() {}, switchSettings() {}, showLogin() {}, refreshSession: async () => {},
  session: {access_token: 'fixture'}, AbortSignal, Option: function(label, value) { this.label = label; this.value = value; },
  fetch: async () => ({ok: true, json: async () => ({data: [{uf: 'BA', id: 1, nome: 'Fixture'}]})}),
 });
 vm.runInContext(fs.readFileSync('dist/amigoz-api.js', 'utf8'), context);
 assert.equal(radios[2].hidden, true);
 assert.equal(select('#settings-tab-amigoz-api').hidden, true);
 await picker.onchange({target: radios[1]});
 assert.equal(changed, 1);
 assert.equal(services.value, 'tjba_margem');
 assert.equal(select('#home').classList.contains('individual-consigx'), true);
 context.currentAccess.allow_amigoz = true;
 context.applyAccessUi();
 assert.equal(radios[2].hidden, false);
 await picker.onchange({target: radios[2]});
 assert.equal(panel.hidden, false);
 assert.equal(select('#single').hidden, true);
 assert.equal(select('#results').hidden, true);
 context.currentAccess.allow_amigoz = false;
 context.applyAccessUi();
 assert.equal(panel.hidden, true);
 assert.equal(select('#results').hidden, false);
 assert.equal(select('#single').hidden, false);
 console.log('PASS: seleção de provedor, campos e histórico respeitam as permissões');
})().catch(error => {console.error(error); process.exitCode = 1;});

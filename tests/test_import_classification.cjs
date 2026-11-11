const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('dist/app.js','utf8');
const start = source.indexOf('function validateImportClassification(');
const end = source.indexOf("$('#file').onchange", start);
const context = vm.createContext({});
vm.runInContext(source.slice(start,end),context);
const validate = context.validateImportClassification;
assert.doesNotThrow(() => validate(['cpf'],[['00000000001']]));
assert.doesNotThrow(() => validate(['estado','convenio'],
  [['Bahia','TJBA'],['BA','Tribunal de Justiça da Bahia']],{uf:'ba',convenio:'tjba'}));
assert.throws(() => validate(['estado'],[['BA'],['SP']]),/Linha 3/);
assert.throws(() => validate(['convenio'],[['tjba'],['saeb']]),/convênios diferentes/);
assert.throws(() => validate(['convenio'],[['saeb']],{uf:'ba',convenio:'tjba'}),/diferente da seleção/);
assert.throws(() => validate(['uf','estado'],[['BA','São Paulo']]),/estados diferentes/);
console.log('PASS: classificação única e divergências bloqueadas antes da importação');

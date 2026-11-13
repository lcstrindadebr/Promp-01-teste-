(()=>{
const amigozConfigPanel=$('#settings-amigoz-api');
amigozConfigPanel.innerHTML=`<section class="card">
 <h2>Integração Amigoz</h2><p>Configure a API e valide o login antes da primeira consulta.</p>
 <form id="amigozApiConfig">
  <label class="field" for="amigozApiUrl">URL base HTTPS</label><input id="amigozApiUrl" type="url" placeholder="https://api.exemplo.com.br" required>
  <label class="field" for="amigozApiUser">Usuário</label><input id="amigozApiUser" autocomplete="off" required maxlength="200">
  <label class="field" for="amigozApiPassword">Senha</label><input id="amigozApiPassword" type="password" autocomplete="new-password" maxlength="512"><small>Deixe em branco para manter a senha do mesmo usuário e endereço.</small>
  <div class="actions"><button class="primary" type="submit">Salvar credenciais</button><button id="amigozApiTest" type="button">Testar conexão salva</button></div>
 </form><p id="amigozConfigStatus" role="status"></p>
</section>`;
const amigozPicker=document.createElement('div');
amigozPicker.className='consultation-picker';amigozPicker.hidden=true;
amigozPicker.innerHTML=`<fieldset class="consultation-options">
 <legend>O que você quer consultar?</legend>
 <div class="consultation-options-grid">
  <label><input type="radio" name="consultationProvider" value="digimais_saldo_parcela" checked><span><strong>Digi+</strong><small>Saldo devedor e parcela</small></span></label>
  <label><input type="radio" name="consultationProvider" value="tjba_margem"><span><strong>ConsigX</strong><small>Margem consignável · Bahia (BA)</small></span></label>
  <label><input type="radio" name="consultationProvider" value="amigoz"><span><strong>Amigoz</strong><small>Saque complementar e margem</small></span></label>
 </div>
</fieldset>`;
$('#individualChoice').appendChild(amigozPicker);
let individualProvider='existing';
const amigozConsultPanel=document.createElement('section');
amigozConsultPanel.className='card amigoz-consult-card';amigozConsultPanel.hidden=true;
amigozConsultPanel.innerHTML=`<header class="amigoz-consult-heading"><h2>Consulta Amigoz</h2>
 <p>Consulte o saque complementar, a margem consignável ou ambos.</p></header>
 <form id="amigozConsultForm">
  <fieldset class="amigoz-form-group"><legend>Modalidade e convênio</legend>
   <div class="amigoz-form-fields">
    <div class="amigoz-field-wide"><label class="field" for="amigozMode">Modalidade</label><select id="amigozMode"><option value="saque">Saque complementar</option><option value="margem">Margem consignável</option><option value="ambos">Saque complementar + margem</option></select></div>
    <div><label class="field" for="amigozState">Estado</label><select id="amigozState" required><option value="">Selecione o estado</option></select></div>
    <div><label class="field" for="amigozConvenio">Convênio</label><select id="amigozConvenio" aria-describedby="amigozConvenioHint" required disabled><option value="">Selecione o estado primeiro</option></select></div>
   </div>
   <p id="amigozConvenioHint" class="muted"></p>
  </fieldset>
  <fieldset class="amigoz-form-group"><legend>Dados do cliente</legend>
   <div class="amigoz-form-fields">
    <div><label class="field" for="amigozConsultCpf">CPF</label><input id="amigozConsultCpf" inputmode="numeric" placeholder="000.000.000-00" required></div>
    <details id="amigozExtraMargin" class="amigoz-field-wide" hidden><summary>Dados adicionais (opcionais)</summary>
     <div><label class="field" for="amigozRegistration">Matrícula (opcional)</label><input id="amigozRegistration" maxlength="256"></div>
     <div id="amigozServerPasswordField" hidden><label class="field" for="amigozServerPassword">Senha do servidor (opcional)</label><input id="amigozServerPassword" type="password" autocomplete="off" maxlength="256"></div>
    </details>
   </div>
  </fieldset>
  <div class="actions"><button type="submit" class="primary">Consultar Amigoz</button><p id="amigozConsultStatus" role="status"></p></div>
 </form><div id="amigozConsultResults"></div>`;
const standardConsultCard=$('#single').closest('.card');
standardConsultCard.before(amigozConsultPanel);
const stateLabelsAmigoz={AC:'Acre',AL:'Alagoas',AM:'Amazonas',CE:'Ceará',ES:'Espírito Santo',GO:'Goiás',MA:'Maranhão',MG:'Minas Gerais',MS:'Mato Grosso do Sul',MT:'Mato Grosso',PA:'Pará',PB:'Paraíba',PE:'Pernambuco',PI:'Piauí',PR:'Paraná',RJ:'Rio de Janeiro',RN:'Rio Grande do Norte',RO:'Rondônia',RR:'Roraima',SC:'Santa Catarina',SE:'Sergipe',SP:'São Paulo',TO:'Tocantins',BR:'Federal / Nacional'};
const localAmigozCatalog=[{"id":131,"nome":"AMAZONPREV-AM","uf":"AM","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"223 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"295 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":52,"nome":"Bombeiros Militar - Minas Gerais - MG","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"99 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"100 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":53,"nome":"Defensoria - Minas Gerais - MG","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"101 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"102 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":132,"nome":"Governo Amazonas - AM","uf":"AM","averbadora":1,"senha_servidor":true,"produtos":[{"produto":"225 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"239 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":46,"nome":"Governo da Paraíba - PB","uf":"PB","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"89 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":105,"nome":"Governo de Alagoas - AL","uf":"AL","averbadora":8,"senha_servidor":true,"produtos":[{"produto":"185 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"193 Cartão Benefício","codigo_produto":7,"tipo_margem":2}]},{"id":15,"nome":"Governo de Goias","uf":"GO","averbadora":7,"senha_servidor":true,"produtos":[{"produto":"26 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"137 Cartão Benefício","codigo_produto":7,"tipo_margem":1}]},{"id":48,"nome":"Governo de Minas Gerais - MG","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"91 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"92 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":139,"nome":"Governo de Pernambuco - PE","uf":"PE","averbadora":1,"senha_servidor":true,"produtos":[{"produto":"235 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"265 Cartão Benefício","codigo_produto":7,"tipo_margem":1}]},{"id":25,"nome":"Governo de Piauí","uf":"PI","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"44 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"72 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"120 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"125 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":68,"nome":"Governo de Rondônia - RO","uf":"RO","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"130 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"131 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":23,"nome":"Governo de São Paulo","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"38 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"39 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":135,"nome":"Governo de São Paulo - Lei 500","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"230 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"231 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":26,"nome":"Governo de São Paulo - Secr. da Educação","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"47 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"48 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":95,"nome":"Governo do Ceará - CE","uf":"CE","averbadora":8,"senha_servidor":true,"produtos":[{"produto":"172 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"267 Cartão Benefício","codigo_produto":7,"tipo_margem":2}]},{"id":56,"nome":"Governo do Espírito Santo - ES","uf":"ES","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"106 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":39,"nome":"Governo do Maranhão - MA","uf":"MA","averbadora":1,"senha_servidor":true,"produtos":[{"produto":"78 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"79 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":93,"nome":"Governo do Paraná - PR","uf":"PR","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"168 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":81,"nome":"IMPCG - Inst. Mun. de Prev. de Campo Grande – MS","uf":"MS","averbadora":1,"senha_servidor":true,"produtos":[{"produto":"156 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":16,"nome":"INSS","uf":"BR","averbadora":5,"senha_servidor":false,"produtos":[{"produto":"27 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"28 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":75,"nome":"INSS - APOSENTADORIA POR INVALIDEZ","uf":"BR","averbadora":5,"senha_servidor":false,"produtos":[{"produto":"146 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"147 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":159,"nome":"IPAMV - Prev. Vitória - ES","uf":"ES","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"276 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":104,"nome":"IPER - Inst. de Prev. de Roraima - RR","uf":"RR","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"183 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"184 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":160,"nome":"IPMC - Prev. Carpina - PE","uf":"PE","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"279 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"280 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":142,"nome":"IPMC - Prev. Cascavel - PR","uf":"PR","averbadora":8,"senha_servidor":true,"produtos":[{"produto":"244 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":70,"nome":"IPMO - Inst. Prev. de Osasco - SP","uf":"SP","averbadora":1,"senha_servidor":true,"produtos":[{"produto":"134 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":28,"nome":"IPREM - SP - APOSENTADOS","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"52 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":27,"nome":"IPREM - SP - PENSIONISTAS","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"50 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":129,"nome":"IPREV -  Santos - SP","uf":"SP","averbadora":10,"senha_servidor":false,"produtos":[{"produto":"220 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":99,"nome":"IPSA - Inst. de Prev. de Santo André - SP","uf":"SP","averbadora":11,"senha_servidor":false,"produtos":[{"produto":"177 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":67,"nome":"IPSEM - Instituto de Previdência Campina de Grande - PB","uf":"PB","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"127 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"128 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"135 Cartão Benefício","codigo_produto":7,"tipo_margem":2}]},{"id":50,"nome":"IPSEMG - MG - Previdencia","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"95 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"96 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":49,"nome":"IPSM - MG - Militares","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"93 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"94 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":146,"nome":"JFPREV - Prev. Juiz de Fora - MG","uf":"MG","averbadora":3,"senha_servidor":true,"produtos":[{"produto":"250 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":73,"nome":"Manausprev - AM","uf":"AM","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"144 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":34,"nome":"MaringaPrev - PR","uf":"PR","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"66 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":51,"nome":"Policia Militar - Minas Gerais - MG","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"97 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"98 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":33,"nome":"Polícia Militar - São Paulo","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"61 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"62 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":54,"nome":"Prefeitura Campinas - SP","uf":"SP","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"103 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"115 Cartão Consignado","codigo_produto":15,"tipo_margem":1}]},{"id":147,"nome":"Prefeitura de Aracaju - SE","uf":"SE","averbadora":14,"senha_servidor":false,"produtos":[{"produto":"251 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"252 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":154,"nome":"Prefeitura de Aracruz - ES","uf":"ES","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"269 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"270 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":60,"nome":"Prefeitura de Araguaína - TO","uf":"TO","averbadora":1,"senha_servidor":true,"produtos":[{"produto":"114 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":140,"nome":"Prefeitura de Araraquara - SP","uf":"SP","averbadora":8,"senha_servidor":true,"produtos":[{"produto":"238 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"241 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":145,"nome":"Prefeitura de Ariquemes - RO","uf":"RO","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"248 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"249 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":157,"nome":"Prefeitura de Belém - Compra Cliente","uf":"PA","averbadora":8,"senha_servidor":false,"produtos":[{"produto":"274 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":156,"nome":"Prefeitura de Belém - PA","uf":"PA","averbadora":8,"senha_servidor":false,"produtos":[{"produto":"272 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"296 Cartão Benefício","codigo_produto":7,"tipo_margem":1}]},{"id":96,"nome":"Prefeitura de Betim - MG","uf":"MG","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"173 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":118,"nome":"Prefeitura de Boa Vista - RR","uf":"RR","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"207 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":97,"nome":"Prefeitura de Caldas Novas - GO","uf":"GO","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"174 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"175 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":3,"nome":"Prefeitura de Campina Grande - PB","uf":"PB","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"5 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"6 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"136 Cartão Benefício","codigo_produto":7,"tipo_margem":1}]},{"id":92,"nome":"Prefeitura de Campinas – SP – Celetistas","uf":"SP","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"167 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":116,"nome":"Prefeitura de Carpina - PE","uf":"PE","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"203 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"204 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":106,"nome":"Prefeitura de Cascavel - PR","uf":"PR","averbadora":8,"senha_servidor":true,"produtos":[{"produto":"186 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":122,"nome":"Prefeitura de Cascavel - PR - (SEMED e SESAU)","uf":"PR","averbadora":8,"senha_servidor":true,"produtos":[{"produto":"211 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":148,"nome":"Prefeitura de Chapecó - SC","uf":"SC","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"255 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":83,"nome":"Prefeitura de Contagem - MG","uf":"MG","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"158 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":45,"nome":"Prefeitura de Curitiba - PR","uf":"PR","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"88 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":127,"nome":"Prefeitura de Ferraz de Vasconcelos - SP","uf":"SP","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"217 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"218 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":144,"nome":"Prefeitura de Guarulhos - SP","uf":"SP","averbadora":12,"senha_servidor":false,"produtos":[{"produto":"247 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"261 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"262 Cartão Benefício","codigo_produto":7,"tipo_margem":1}]},{"id":137,"nome":"Prefeitura de Ilhabela - SP","uf":"SP","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"232 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"233 Cartão Benefício","codigo_produto":7,"tipo_margem":1}]},{"id":155,"nome":"Prefeitura de Itapeva - SP","uf":"SP","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"271 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":35,"nome":"Prefeitura de Jaboatão dos Guararapes - PE","uf":"PE","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"67 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"68 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"69 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"70 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"71 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":2,"nome":"Prefeitura de João Pessoa - PB","uf":"PB","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"4 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"63 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"64 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"65 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"107 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"129 Cartão Benefício","codigo_produto":7,"tipo_margem":2}]},{"id":30,"nome":"Prefeitura de Juazeiro do Norte - CE","uf":"CE","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"55 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"56 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":11,"nome":"Prefeitura de Juiz de Fora - MG","uf":"MG","averbadora":3,"senha_servidor":true,"produtos":[{"produto":"14 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":158,"nome":"Prefeitura de Jundiaí - SP","uf":"SP","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"275 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":143,"nome":"Prefeitura de Linhares - ES","uf":"ES","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"245 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":141,"nome":"Prefeitura de Macaé - RJ","uf":"RJ","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"243 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":55,"nome":"Prefeitura de Macaíba - RN","uf":"RN","averbadora":11,"senha_servidor":false,"produtos":[{"produto":"105 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"190 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":162,"nome":"Prefeitura de Mariana - MG","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"288 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"289 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":32,"nome":"Prefeitura de Maringa - PR","uf":"PR","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"60 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":130,"nome":"Prefeitura de Mauá - SP","uf":"SP","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"222 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":152,"nome":"Prefeitura de Medianeira - PR","uf":"PR","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"266 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":151,"nome":"Prefeitura de Mossoró - RN","uf":"RN","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"263 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"264 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":19,"nome":"Prefeitura de Natal - RN","uf":"RN","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"32 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"236 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"237 Cartão Benefício","codigo_produto":7,"tipo_margem":2}]},{"id":58,"nome":"Prefeitura de Navegantes - SC","uf":"SC","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"110 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"111 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":76,"nome":"Prefeitura de Nova Iguaçu - RJ","uf":"RJ","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"149 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"210 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":47,"nome":"Prefeitura de Nova Lima - MG","uf":"MG","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"90 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":40,"nome":"Prefeitura de Olinda - PE","uf":"PE","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"80 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"154 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"155 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"159 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"160 Cartão Benefício","codigo_produto":7,"tipo_margem":2}]},{"id":18,"nome":"Prefeitura de Parnamirim - RN","uf":"RN","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"31 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":102,"nome":"Prefeitura de Ponta Grossa - PR","uf":"PR","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"181 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":29,"nome":"Prefeitura de Porto Velho - RO","uf":"RO","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"53 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":123,"nome":"Prefeitura de Praia Grande - SP","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"213 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":1,"nome":"Prefeitura de Recife - PE","uf":"PE","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"1 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"2 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":85,"nome":"Prefeitura de Ribeirão Preto -SP","uf":"SP","averbadora":10,"senha_servidor":false,"produtos":[{"produto":"163 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"281 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"282 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"283 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"284 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"285 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":138,"nome":"Prefeitura de Rio Branco - AC","uf":"AC","averbadora":10,"senha_servidor":false,"produtos":[{"produto":"234 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":110,"nome":"Prefeitura de Sabará - MG","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"192 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":74,"nome":"Prefeitura de Santo André - SP","uf":"SP","averbadora":11,"senha_servidor":false,"produtos":[{"produto":"145 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":61,"nome":"Prefeitura de Santos -SP","uf":"SP","averbadora":8,"senha_servidor":true,"produtos":[{"produto":"116 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":164,"nome":"Prefeitura de São Bernardo do Campo - SP","uf":"SP","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"292 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"293 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":134,"nome":"Prefeitura de São José do Rio Preto - SP","uf":"SP","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"229 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":108,"nome":"Prefeitura de São José dos Campos - SP","uf":"SP","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"189 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":100,"nome":"Prefeitura de São Luís - MA","uf":"MA","averbadora":7,"senha_servidor":true,"produtos":[{"produto":"178 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":17,"nome":"Prefeitura de São Paulo - SP","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"29 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":124,"nome":"Prefeitura de São Pedro da Aldeia - RJ","uf":"RJ","averbadora":2,"senha_servidor":true,"produtos":[{"produto":"214 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":163,"nome":"Prefeitura de Saquarema - RJ","uf":"RJ","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"291 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":115,"nome":"Prefeitura de Serra - ES","uf":"ES","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"201 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"202 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":66,"nome":"Prefeitura de Sorocaba - SP","uf":"SP","averbadora":7,"senha_servidor":true,"produtos":[{"produto":"126 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"212 Cartão Benefício","codigo_produto":7,"tipo_margem":2}]},{"id":12,"nome":"Prefeitura de Sorriso - MT","uf":"MT","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"15 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"18 Saque Complementar","codigo_produto":14,"tipo_margem":1}]},{"id":41,"nome":"Prefeitura de Suzano - SP","uf":"SP","averbadora":1,"senha_servidor":false,"produtos":[{"produto":"82 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"83 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":165,"nome":"Prefeitura de Taboão da Serra - SP","uf":"SP","averbadora":10,"senha_servidor":false,"produtos":[{"produto":"297 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"299 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":20,"nome":"Prefeitura de Tangará da Serra - MT","uf":"MT","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"33 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":112,"nome":"Prefeitura de Uberaba - MG","uf":"MG","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"195 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":166,"nome":"Prefeitura de Valparaíso de Goiás - GO","uf":"GO","averbadora":7,"senha_servidor":true,"produtos":[{"produto":"300 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":126,"nome":"PREVINI-RJ","uf":"RJ","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"215 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"216 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":43,"nome":"Previso - MT","uf":"MT","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"86 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":167,"nome":"SGPREVI - Prev. São Gonçalo - RJ","uf":"RJ","averbadora":7,"senha_servidor":true,"produtos":[{"produto":"302 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":13,"nome":"SIAPE","uf":"BR","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"20 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"23 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":94,"nome":"SIAPE Celetista","uf":"BR","averbadora":null,"senha_servidor":false,"produtos":[{"produto":"169 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"170 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":31,"nome":"SPPREV - São Paulo - SP","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"58 Cartão Consignado","codigo_produto":15,"tipo_margem":3},{"produto":"59 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":133,"nome":"TJAL - Tribunal de Justiça de Alagoas - AL","uf":"AL","averbadora":2,"senha_servidor":false,"produtos":[{"produto":"226 Cartão Benefício","codigo_produto":7,"tipo_margem":2},{"produto":"227 Cartão Benefício","codigo_produto":7,"tipo_margem":1},{"produto":"228 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]},{"id":168,"nome":"TJSP - Tribunal de Justiça de São Paulo","uf":"SP","averbadora":9,"senha_servidor":false,"produtos":[{"produto":"309 Cartão Benefício","codigo_produto":7,"tipo_margem":3}]},{"id":4,"nome":"Tribunal de Justiça de Minas Gerais","uf":"MG","averbadora":null,"senha_servidor":true,"produtos":[{"produto":"8 Cartão Benefício","codigo_produto":7,"tipo_margem":3},{"produto":"24 Cartão Consignado","codigo_produto":15,"tipo_margem":3}]}];
let amigozCatalog=[],amigozBusy=false,amigozConfigBusy=false;
const amigozIsAdmin=()=>Boolean(authenticated&&currentAccess?.active&&currentAccess.role==='admin');

const amigozCanConsult=()=>Boolean(amigozIsAdmin()||(authenticated&&currentAccess?.active&&currentAccess.allow_amigoz&&!currentAccess.trial_expired));
async function loadAmigozCatalog(){
 if(!amigozCanConsult())throw Error('Acesso Amigoz não liberado para esta conta.');
 if(amigozCatalog.length)return amigozCatalog;
 try{
  const rows=await amigozRequest('convenios');
  if(Array.isArray(rows)&&rows.length)return rows;
 }catch(error){
  if([401,403].includes(error.status))throw error;
 }
 return localAmigozCatalog;
}
async function amigozRequest(route,body){
 const consultationRoute=route==='consultar'||route==='convenios';
 if(!(consultationRoute?amigozCanConsult():amigozIsAdmin()))throw Error('Acesso Amigoz não liberado para esta conta.');
 await refreshSession();
 const response=await fetch('/api/admin/amigoz/'+route,{
  method:body?'POST':'GET',headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},
  ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(route === 'consultar' ? 240000 : 40000)
 });
 let value;
 try{value=await response.json();}catch{throw Error('Não foi possível acessar a API Amigoz do ApoiarCred.');}
 if(!response.ok)throw Object.assign(Error(value.error?.message||'Falha ao acessar a integração Amigoz.'),{status:response.status});
 return value.data;
}
// Reuse the authenticated route, quota checks and CRM persistence from the simulator.
window.consultarMargemAmigozSimulador=async function(input){
 const match=/^amigoz_([0-9]+)$/.exec(input.convenio||'');
 if(!match)throw Error('Selecione um convênio Amigoz para consultar a margem.');
 if(!amigozCanConsult())throw Error('Acesso Amigoz não liberado para esta conta.');
 const catalog=await loadAmigozCatalog();
 const convenio=catalog.find(row=>row.id===Number(match[1]));
 if(!convenio||convenio.averbadora==null)throw Error('Consulta de margem indisponível neste convênio.');
 return amigozRequest('consultar',{modo:'margem',convenio_id:convenio.id,cpf:input.cpf,
  ...(input.matricula?{numero_matricula:input.matricula}:{}),
  ...(convenio.senha_servidor&&input.senha?{senha_servidor:input.senha}:{})});
};
function updateAmigozPanel(){
 const admin=amigozIsAdmin(),home=currentPage==='home',allowed=amigozCanConsult();
 $('#settings-tab-amigoz-api').hidden=!admin;
 amigozPicker.hidden=!home||!authenticated;
 if(!allowed){
  $('#amigozConsultResults').replaceChildren();
  $('#amigozServerPassword').value='';
  individualProvider='existing';
 }
 const standard=$('#serviceSelect');
 for(const radio of amigozPicker.querySelectorAll('input')){
  const isAmigoz=radio.value==='amigoz';
  radio.disabled=isAmigoz?!allowed:![...standard.options].some(option=>option.value===radio.value&&!option.disabled);
  radio.closest('label').hidden=radio.disabled;
  radio.checked=radio.value===(individualProvider==='amigoz'?'amigoz':standard.value);
 }
 const showing=allowed&&home&&individualProvider==='amigoz';
 amigozConsultPanel.hidden=!showing;
 standardConsultCard.hidden=showing;
 $('#home').classList.toggle('individual-amigoz',showing);
 $('#results').hidden=showing;
 $('#consultationSummaryTitle').textContent=standard.value==='tjba_margem'?'Resumo ConsigX':'Resumo Digi+';
 $('#home').classList.toggle('individual-picker-ready',!amigozPicker.hidden);
 $('#home').classList.toggle('individual-consigx',!showing&&standard.value==='tjba_margem');
 $('#serviceContext').classList.toggle('amigoz-context-hidden',showing);
}
const amigozPreviousAccess=applyAccessUi;
applyAccessUi=function(){amigozPreviousAccess();updateAmigozPanel();};
const amigozPreviousSettings=switchSettings;
switchSettings=function(id){
 if(id==='amigoz-api'&&!amigozIsAdmin())return;
 amigozPreviousSettings(id);
 if(id==='amigoz-api')loadAmigozConfig();
};
async function loadAmigozConfig(){
 const epoch=authEpoch;
 try{
  const value=await amigozRequest('configuracao');
  if(epoch!==authEpoch)return;
  $('#amigozApiUrl').value=value.url||'';$('#amigozApiUser').value=value.usuario||'';
  $('#amigozApiPassword').value='';
  $('#amigozConfigStatus').textContent=value.configured?'Credenciais cadastradas.':'Configure a conexão.';
 }catch(error){if(epoch===authEpoch)$('#amigozConfigStatus').textContent=error.message;}
}
async function changeAmigozConfig(route,payload,message){
 if(amigozConfigBusy)return;
 amigozConfigBusy=true;const epoch=authEpoch;
 $('#amigozConfigStatus').textContent='Aguarde…';
 try{
  await amigozRequest(route,payload);
  if(epoch===authEpoch)$('#amigozConfigStatus').textContent=message;
 }catch(error){if(epoch===authEpoch)$('#amigozConfigStatus').textContent=error.message;}
 finally{amigozConfigBusy=false;if(epoch===authEpoch)$('#amigozApiPassword').value='';}
}
$('#amigozApiConfig').onsubmit=e=>{
 e.preventDefault();
 changeAmigozConfig('configuracao',{url:$('#amigozApiUrl').value.trim(),usuario:$('#amigozApiUser').value.trim(),senha:$('#amigozApiPassword').value},'Credenciais salvas.');
};
$('#amigozApiTest').onclick=()=>changeAmigozConfig('testar',{},'Login aceito pela Amigoz.');

function optionsAmigoz(select,placeholder,items){
 select.replaceChildren(new Option(placeholder,''),...items.map(([id,label])=>new Option(label,id)));
}
function updateAmigozConvenio(){
 const convenio=amigozCatalog.find(row=>String(row.id)===$('#amigozConvenio').value);
 const wantsMargin=$('#amigozMode').value!=='saque',available=Boolean(convenio&&convenio.averbadora!=null);
 $('#amigozExtraMargin').hidden=!wantsMargin||!available;
 $('#amigozRegistration').required=false;
 $('#amigozServerPasswordField').hidden=!wantsMargin||!available||!convenio.senha_servidor;
 $('#amigozServerPassword').required=false;
 if($('#amigozServerPasswordField').hidden)$('#amigozServerPassword').value='';
 const products=convenio?.produtos.map(p=>`${p.produto} (produto ${p.codigo_produto}, margem ${p.tipo_margem})`).join(' · ');
 $('#amigozConvenioHint').textContent=[wantsMargin&&convenio&&!available?'Margem indisponível. O catálogo não informa a averbadora.':'',products].filter(Boolean).join(' ');
}
$('#amigozState').onchange=()=>{
 const uf=$('#amigozState').value;
 optionsAmigoz($('#amigozConvenio'),uf?'Selecione o convênio':'Selecione o estado primeiro',amigozCatalog.filter(row=>row.uf===uf).map(row=>[row.id,row.nome]));
 $('#amigozConvenio').disabled=!uf;$('#amigozConvenio').onchange();
};
$('#amigozConvenio').onchange=()=>{$('#amigozRegistration').value='';$('#amigozServerPassword').value='';updateAmigozConvenio();};
$('#amigozMode').onchange=updateAmigozConvenio;
$('#amigozConsultCpf').onblur=e=>{e.target.value=formatCpf(digits(e.target.value));};
amigozPicker.onchange=async e=>{
 const choice=e.target.value;
 individualProvider=choice==='amigoz'?'amigoz':'existing';
 if(individualProvider==='existing'){
  $('#serviceSelect').value=choice;
  $('#serviceSelect').onchange?.();
 }
 updateAmigozPanel();
 if(individualProvider!=='amigoz'||amigozCatalog.length)return;
 $('#amigozConsultStatus').textContent='Carregando estados e convênios…';
 const epoch=authEpoch;
 try{
  const list=await loadAmigozCatalog();
  if(epoch!==authEpoch)return;
  amigozCatalog=list;
  const states=[...new Set(list.map(row=>row.uf))].map(uf=>[uf,stateLabelsAmigoz[uf]||uf]).sort((a,b)=>a[1].localeCompare(b[1],'pt-BR'));
  optionsAmigoz($('#amigozState'),'Selecione o estado',states);
  $('#amigozConsultStatus').textContent='';
 }catch(error){if(epoch===authEpoch)$('#amigozConsultStatus').textContent=error.message;}
};
function showAmigozResult(result){
 const output=$('#amigozConsultResults');output.replaceChildren();
 for(const [key,title] of [['saque','Saque complementar'],['margem','Consulta de margem']]){
  const value=result[key];if(!value)continue;
  const section=document.createElement('section'),heading=document.createElement('h3');
  heading.textContent=title;section.appendChild(heading);output.appendChild(section);
  if(value.status!=='respondido'){const p=document.createElement('p');p.textContent=value.mensagem;section.appendChild(p);continue;}
  if(key==='saque'){
   const {ofertas,total_sem_correspondencia}=value.dados;
   const p=document.createElement('p');p.textContent=ofertas.length?`${ofertas.length} resultado(s) associado(s) ao convênio selecionado.`:'Nenhum resultado foi associado com segurança ao convênio selecionado.';
   if(total_sem_correspondencia)p.textContent+=` ${total_sem_correspondencia} resultado(s) sem correspondência.`;
   section.appendChild(p);
   const labels={elegivel:'Elegibilidade',valor_saque_disponivel:'Saque disponível',valor_saque_minimo:'Saque mínimo',limite_cartao:'Limite do cartão',limite_disponivel_cliente:'Limite disponível',status:'Status',nome_oferta:'Oferta',erro_informado:'Erro informado pela Amigoz'};
   const money=new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'});
   for(const offer of ofertas){
    const list=document.createElement('dl');
    for(const [field,label] of Object.entries(labels)){
     if(offer[field]==null)continue;
     const dt=document.createElement('dt'),dd=document.createElement('dd');
     dt.textContent=label;dd.textContent=field==='erro_informado'?(offer[field]?'Sim':'Não'):typeof offer[field]==='number'?money.format(offer[field]):String(offer[field]);list.append(dt,dd);
    }
    section.appendChild(list);
   }
  }else{
   const p=document.createElement('p');p.textContent='Retorno da Amigoz para conferência durante a homologação.';
   const pre=document.createElement('pre');pre.textContent=JSON.stringify(value.dados,null,2);section.append(p,pre);
  }
 }
}
$('#amigozConsultForm').onsubmit=async e=>{
 e.preventDefault();if(amigozBusy)return;
 const epoch=authEpoch,button=e.target.querySelector('button');
 const payload={modo:$('#amigozMode').value,convenio_id:Number($('#amigozConvenio').value),cpf:$('#amigozConsultCpf').value};
 if(!$('#amigozExtraMargin').hidden)payload.numero_matricula=$('#amigozRegistration').value;
 if(!$('#amigozServerPasswordField').hidden)payload.senha_servidor=$('#amigozServerPassword').value;
 $('#amigozServerPassword').value='';$('#amigozConsultResults').replaceChildren();
 amigozBusy=true;button.disabled=true;$('#amigozConsultStatus').textContent='Consultando…';
 try{
  const result=await amigozRequest('consultar',payload);
  if(epoch!==authEpoch||!amigozCanConsult())return;
  $('#amigozConsultStatus').textContent='Resposta recebida para '+result.cpf+'.' + (result.salvo_no_historico === false ? ' Não foi possível salvar o resultado. Não repita a consulta; confira o histórico e o diagnóstico.' : result.salvo_no_historico ? ' Salva no histórico do cliente.' : '');showAmigozResult(result);
 }catch(error){if(epoch===authEpoch)$('#amigozConsultStatus').textContent=error.message;}
 finally{amigozBusy=false;button.disabled=false;if(epoch===authEpoch)refreshMyAccess(true).catch(()=>{});}
};
const previousAmigozLogout=showLogin;
showLogin=function(...args){
 amigozCatalog=[];optionsAmigoz($('#amigozState'),'Selecione o estado',[]);$('#amigozState').onchange();$('#amigozConsultForm').reset();$('#amigozApiConfig').reset();individualProvider='existing';
 $('#amigozConsultResults').replaceChildren();$('#amigozConsultStatus').textContent='';$('#amigozConfigStatus').textContent='';
 optionsAmigoz($('#amigozState'),'Selecione o estado',[]);$('#amigozState').onchange();
 previousAmigozLogout(...args);updateAmigozPanel();
};
updateAmigozPanel();
})();

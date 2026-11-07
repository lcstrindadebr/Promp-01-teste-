# ApoiarCred · MVP

Ubuntu Server **24.04 x86-64**, 2 vCPU e 4 GB RAM. Instalação direta, sem Docker.

## DNS

| Tipo | Nome | Valor |
|---|---|---|
| A | consultas | IP público da VPS |

Libere TCP 80/443 no provedor. Se usar Cloudflare, comece com Somente DNS.

## Instalar

Na VPS como root:

```bash
git clone --branch apoiarcred-consultas-mvp --single-branch https://github.com/lcstrindadebr/Promp-01-teste-.git /opt/apoiarcred-src && bash /opt/apoiarcred-src/instalar.sh
```

Se o Git não existir: `apt update && apt install -y git`.

### Já baixou ou instalou antes?

```bash
git -C /opt/apoiarcred-src pull --ff-only origin apoiarcred-consultas-mvp && bash /opt/apoiarcred-src/instalar.sh
```

O menu identifica a instância em `/opt/apoiarcred`:

- **Sem instalação completa:** oferece instalar. Pergunta subdomínio, e-mail do SSL e chave secret/service_role do Supabase e configura os serviços.
- **Com instalação completa:** oferece atualizar pelo GitHub, trocar a conexão do Supabase ou sair. Não reinstala nem pede domínio e certificado novamente.

O MVP gerencia uma instância por VPS no caminho padrão. Instalações incompletas podem ser retomadas pela opção instalar. Atualizações preservam `.env`, projeto Supabase, certificado e modo do robô. Painel, robô, dependências, scripts do menu e configuração do serviço são atualizados pelo mesmo menu. Não precisa copiar o robô manualmente.

## Trocar API/conexão do Supabase

Abra o mesmo menu e escolha **2) Trocar conexão/API do Supabase**.

Ele pede URL do projeto, chave **publishable/anon** do painel e chave **secret/service_role** do robô, com chaves ocultas. Valida a conexão e as tabelas antes de salvar. A chave secreta fica somente em `/opt/apoiarcred/.env`; nunca é enviada ao frontend. O worker é parado durante a troca e retomado se estava ativo.

A conexão é atualizada no painel e no robô. Recarregue o navegador e entre novamente. Os usuários e dados não são migrados para o outro projeto; ele precisa ter o schema do MVP e contas Auth configurados. URLs de projeto neste MVP usam `https://REFERENCIA.supabase.co`.

## Acesso ao sistema

A primeira tela é **login**. Entre com um usuário criado em Supabase → Authentication → Users. Não existe opção de modo de operação: consultas e resultados usam sempre o Supabase. A configuração web mostra apenas a conta conectada e permite sair.

O projeto original já tem o banco configurado. Não reaplique o schema nele. Cada usuário vê somente suas próprias consultas.

## Importar clientes

No painel, clique em **Baixar modelo CSV** ou **Baixar modelo padrão de importação**. O arquivo contém:

```csv
nome;cpf;telefone
NOME COMPLETO DO CLIENTE;00000000000;11999999999
```

Substitua o exemplo pelos clientes. CPF e telefone devem ser texto para preservar zeros à esquerda. O painel valida a planilha e mostra linhas que precisam de correção antes da importação. A linha de exemplo não é enviada ao robô. Os arquivos devem ter no máximo 2 MB.

## Atualizar sem abrir o menu

```bash
apoiarcred-atualizar
```

Busca e aplica atualizações quando executado. Sem agendamento em segundo plano. Não sobrescreve alterações locais. Se o serviço estava parado, permanece parado. Se a atualização falhar, confira o erro antes de reiniciar.

## Nova dinâmica de consulta e progresso

O robô abre diretamente o endereço público do chat que o widget do banco utiliza. A consulta não depende da página institucional nem da abertura de popup. Preenche os dados e envia o CPF no padrão **000.000.000-00**, pelo botão de envio.

Cada CPF mostra barra e etapa atual: iniciar navegador, abrir site, abrir chat, preencher dados, selecionar consignado/boleto, enviar CPF e aguardar saldo. O progresso é informado pelo worker, sem simulação por tempo. Erros mantêm o percentual e a etapa da falha.

Resposta explícita de documento não localizado recebe **Não é cliente** e 100% (consulta concluída sem valores). Timeout, ausência de resposta ou encerramento silencioso são erro/revisão, não ausência de cliente. Resposta parcial também exige revisão.

O banco original já recebeu os campos `progress` e `stage` e o status `nao_cliente`. Para outro projeto já existente, aplique `supabase/upgrade_progress.sql` no SQL Editor antes de atualizar. O atualizador verifica o schema antes de parar o robô. Para projeto novo, use o schema completo.

Atualize tudo por **1) Atualizar pelo GitHub** no menu. O launcher baixa a branch e executa a lógica de atualização recém-baixada, inclusive quando o próprio atualizador mudou.

## Robô

O robô inicia com `ROBOT_MODE=disabled` no servidor. Isso é uma proteção de homologação do worker, **não um modo selecionável no painel**: a fila e os resultados continuam no Supabase. Nesse estado, registros retornam Revisão sem consultar o banco.

A execução completa no Digi+ ainda precisa de homologação na VPS. Para uma consulta autorizada de teste:

```bash
nano /opt/apoiarcred/.env
# Altere ROBOT_MODE=disabled para ROBOT_MODE=live, salve e execute:
systemctl restart apoiarcred-robo
```

Valide uma consulta individual antes de lotes. Se uma tarefa for interrompida, revise antes de reenviar: recuperação automática de consultas em processamento ainda não está implementada.

## Diagnosticar falha de abertura do banco

Depois de atualizar pela opção **1**, abra novamente o instalador e selecione **3) Diagnosticar robô**.

O teste roda como o mesmo usuário do worker (`apoiarcred`), com o mesmo Chromium, e verifica DNS, TLS, navegador e formulário do **chat direto**, sem enviar nome, telefone ou CPF.

A página institucional falhou na VPS com `ERR_HTTP2_PROTOCOL_ERROR` e depois `ERR_EMPTY_RESPONSE`. A consulta não passa mais por essa página: usa o endereço público do widget, que já foi aberto e utilizado na demonstração. Não há troca de IP, proxy ou desativação da validação TLS. Se o próprio chat apresentar verificação adicional, o robô para para revisão.

O teste exibe a linha `Rota da consulta | chat direto` e precisa terminar com `Chat direto | formulário/menu identificado` e `RESULTADO: PASSOU`. Se falhar, envie a saída para identificarmos o acesso ao chat nessa máquina. A troca de rota foi testada com respostas simuladas; a confirmação na VPS depende deste diagnóstico.

## Comandos úteis

```bash
journalctl -u apoiarcred-robo -n 50 -f
systemctl restart apoiarcred-robo
systemctl stop apoiarcred-robo
certbot renew --dry-run
```

Configure backups e retenção no Supabase. Scripts novos ficam em `scripts/`; execute pelo menu principal, não pelo instalador interno.

## Verificação do código

```bash
python3 -m unittest discover -s tests -v
node tests/test_frontend.cjs
```

Os testes cobrem menu, instalação simulada, troca de configuração, autenticação do frontend com respostas simuladas e interpretação do robô. Não substituem a validação na VPS real.



### Correção do travamento em 40% (31/10/2026)

O formulário do chat valida nome/telefone por eventos de teclado. Apenas preencher o
valor podia deixar “Campo obrigatório” no telefone; o robô aguardava um menu que
nunca abriria. Agora digita os campos, confirma a chegada do menu e só então avança
para 40%. Validação recusada, sessão encerrada e menu indisponível têm mensagens
específicas. Não há reenvio automático do CPF nem aumento artificial do progresso.
CPF recusado pelo banco fica em Revisão, nunca “Não é cliente”.

Instale essa correção com a opção **1 — Atualizar** do instalador. Ela está no
próprio `vps/robot.py`, copiado e reiniciado pelo atualizador existente. A opção 3
verifica infraestrutura/abertura do formulário, **não** homologa uma consulta.
Após atualizar, use uma nova consulta individual autorizada para verificar também
o ambiente da VPS. Os testes locais simulam falhas e transições; não garantem
 disponibilidade do serviço externo nem uma resposta de saldo/parcelas.

Homologação assistida no chat em 31/10/2026 confirmou os três retornos: CPF
recusado como inválido, documento não localizado e saldo com total de parcelas.
A resposta positiva usa `Valor Saldo: R$ 1234.56` (exemplo fictício), com ponto
decimal. O robô aceita esse formato e o brasileiro, abre “Visualizar Chat” no
encerramento e permite a chegada da última mensagem. Ainda é necessário validar
a execução na VPS após a atualização; teste assistido no navegador não equivale
a executar o worker nessa máquina.

Para acompanhar o tempo acumulado de cada etapa, sem dados pessoais nos logs:

```bash
journalctl -u apoiarcred-robo -f
```

### Duas consultas por CPF: saldo e valor da parcela

1. O robô consulta o saldo de liquidação e o total de parcelas.
2. Se o banco informar explicitamente que não é cliente, encerra sem segunda consulta.
3. Se houver saldo conclusivo, salva esse resultado no mesmo registro antes de abrir
   uma sessão nova para o mesmo CPF e selecionar **Valor de Parcela**.
4. Salva `valor_parcela` e os resultados separados em `resultado_saldo` e
   `resultado_parcela`. Se a segunda falhar, mantém saldo e quantidade, com status
   Revisão e explicação do que faltou. Falha na primeira interrompe o fluxo.

O progresso vai de 0 a 50% na primeira consulta e de 50 a 100% na segunda.
O painel e a exportação CSV incluem Valor da parcela. Não há cálculo estimado
por divisão do saldo: o valor é lido da resposta do banco.

O botão **Baixar planilha padrão (.csv)** fornece o modelo compatível com Excel
e Google Planilhas (`nome;cpf;telefone`). Substitua a linha de exemplo e mantenha
os identificadores como texto; os resultados são preenchidos automaticamente.

O projeto Supabase original já recebeu as novas colunas. Para outro projeto
existente, execute `supabase/upgrade_valor_parcela.sql` no SQL Editor antes de
atualizar. Instalações novas usam `supabase/schema.sql`. O atualizador verifica
as colunas antes de trocar o código; não executa SQL com a chave de serviço.

Atualize pelo menu, opção 1. A homologação assistida confirmou o retorno do valor
da parcela no chat, mas a execução das duas sessões pelo worker precisa ser
verificada na VPS após instalar a versão.

### Exibição simplificada das consultas

Durante o processamento, o painel mostra **Consultando...** e a barra percentual.
Etapas e mensagens técnicas ficam em **Configurações → Log de consultas**,
recolhido por padrão. Esse log mostra o último estado salvo de cada consulta e
os detalhes dos resultados de saldo/parcela, sem exigir nova coluna no banco.
A lista principal e o CSV de resultados usam mensagens resumidas.

### Consulta individual e campanhas

- **Consulta individual:** formulário de um cliente e a mesma tabela de resultados,
  com saldo, total de parcelas, valor da parcela e progresso.
- **Campanhas:** informe um nome, baixe o modelo padrão e importe o CSV. O nome e
  os clientes são salvos juntos; uma falha na importação não cria campanha vazia.
  Administradores podem importar campanhas sem limite de registros. Para parceiros, a importação é de até 1.000 clientes. CPFs repetidos são indicados na prévia.
- Selecione uma campanha para ver seus resultados e o relatório: consultas
  solicitadas, clientes identificados, não clientes, erros, revisões e pendências.
  O relatório é atualizado enquanto o robô trabalha e fica finalizado quando
  não existem registros na fila/em processamento. Clientes com resposta parcial
  podem estar também na contagem de revisão. A exportação da campanha é separada
  da exportação individual, com opção adicional de baixar o relatório resumido.
- **Nova tentativa: erros e revisão:** recoloca somente esses registros na fila,
  dentro da mesma campanha. Não duplica o total solicitado e não altera consultas
  concluídas, não clientes ou em andamento. Os resultados dos registros reenviados
  são limpos para não misturar respostas de tentativas diferentes.
- As importações CSV antigas passam a aparecer em Campanhas, mantendo o histórico.
  Consultas individuais antigas continuam na aba individual.
- A logo anexada fica em `dist/logo-apoiarcred.png`, tanto no login quanto no menu.
  A instalação não depende do endereço externo da imagem.

O Supabase original já recebeu `upgrade_campanhas.sql`. Para outro projeto,
execute esse arquivo no SQL Editor após as migrações anteriores e antes de
atualizar o painel. Instalações novas usam o schema completo. A função pública
que solicita nova tentativa executa como usuário; a escrita fica em um auxiliar
no schema privado, limitado ao dono da campanha e aos status erro/revisão.
Nenhuma permissão geral de edição de resultados é concedida ao painel.

Atualize pelo menu **1 — Atualizar**. O instalador valida a coluna `tipo` antes de
copiar o painel. Não é necessário mudar as chaves ou reinstalar o robô.

Validação desta mudança: testes do painel (`node tests/test_frontend.cjs` e
`node tests/test_campaigns.cjs`), suíte Python e teste transacional no Supabase de
criação atômica, isolamento por conta, escopo da nova tentativa e totais estáveis.
Os dados usados para testar o banco foram desfeitos na mesma transação; nenhuma
consulta real ao banco Digi+ foi disparada por esses testes.

### Simulação Amigoz e comissão

Em consultas individuais ou campanhas, clique em **Simular Amigoz** quando saldo e parcela estiverem disponíveis na mesma consulta. As sete tabelas são calculadas juntas no Supabase. Em **Configurações → Comissão do vendedor · Amigoz**, informe o percentual de cada tabela e salve. Campo vazio oculta a comissão; zero mostra R$ 0,00. Percentuais pertencem à conta conectada e ficam disponíveis em outros dispositivos.

Método autorizado: estimativa de valor presente pelo CET mensal de referência, 96 parcelas iguais e primeira parcela após um mês. `liberado = parcela × [1 − (1 + CET)^(-96)] / CET`; `troco = liberado − dívida`; `comissão = (dívida + troco) × percentual / 100`. Valores arredondados em centavos. IOF e demais custos representados no CET não são descontados novamente. O limite pré-aprovado não pode ser deduzido dessa fórmula e aparece como indisponível. Disponibilidade insuficiente não gera troco negativo nem comissão.

**São estimativas teóricas, não resultados homologados pelo banco.** A tabela de 3% usa CET de 3,63% e retorna R$ 3.780,17 no exemplo de parcela R$ 179,37 e dívida R$ 1.000,00, diferente do troco bancário observado de R$ 3.639,44. Essa diferença é conhecida. As regras individuais de custos e limites ainda não estão disponíveis. A autorização para estimar as sete tabelas substitui a orientação anterior de deixar seis tabelas sem parametrização.

Cada simulação guarda entradas, resultados, percentuais, método, versão e data. Se os dados da consulta mudarem, o resultado aberto é ocultado e sinalizado como desatualizado; clique em Recalcular. Não é necessário consultar o banco novamente para simular.

O projeto Supabase original já recebeu a atualização. Para outro projeto existente, execute `supabase/upgrade_amigoz.sql` no SQL Editor uma vez antes de atualizar o painel. Instalações novas usam `supabase/schema.sql`. O auto instalador (opção 1) distribui todo o código atualizado, incluindo `dist/amigoz.js`; preserva as configurações e não executa SQL em projetos externos automaticamente.

### Excluir campanhas e consultas

Use **Excluir** na linha de uma consulta (individual ou dentro da campanha), ou **Excluir campanha** na campanha selecionada. O sistema pede confirmação. A exclusão é definitiva e remove também as simulações relacionadas; excluir a campanha remove todas as suas consultas. Cada conta só pode excluir os próprios registros. Consultas ainda na fila deixam de ser executadas; um atendimento já iniciado no banco pode continuar até encerrar, sem recriar o registro apagado.

O Supabase original já foi atualizado. Em outro projeto existente, execute `supabase/upgrade_exclusao.sql` antes de atualizar pela opção 1 do auto instalador. Instalação nova: `supabase/schema.sql`.

### Importação de campanhas: Excel, CSV e TSV

Aceita `.xlsx`, `.xls`, `.csv` (vírgula ou ponto e vírgula) e `.tsv` (tabulação). Para parceiros, a importação aceita até 2 MB e 1.000 clientes. Para administradores, o painel não impõe esses limites. No Excel, coloque os dados na primeira aba, com cabeçalho na primeira linha: `nome`, `cpf`, `telefone`. Também são reconhecidos `Nome completo`, `Celular` e `Telefone com DDD`. Substitua a linha de exemplo antes de importar. CPF e telefone devem ser texto; CPFs numéricos curtos recebem zeros à esquerda até completar 11 dígitos.

O botão é liberado depois da leitura, com nome de campanha e ao menos uma linha válida. Erros ficam visíveis abaixo do botão, com detalhes por linha. Linhas inválidas e CPFs duplicados não são enviados; revise a prévia antes de criar a campanha. O leitor Excel SheetJS CE 0.20.3 é distribuído localmente em `dist/vendor`, com licença; o navegador não depende de CDN para importar.

Validação: `node tests/test_import_formats.cjs` testa arquivos reais nos quatro formatos, criação via RPC simulada, zeros à esquerda, arquivo inválido, limite de linhas e troca rápida de arquivo. `tests/campaigns_database.sql` valida a criação e o isolamento no banco em transação revertida, sem deixar clientes na fila.

### Tipos de higienização

A central agora identifica o serviço antes de iniciar consultas individuais ou campanhas. **Digi+ · Saldo devedor e parcela** está disponível. **Consulta de margem → TJBA** está integrada em homologação, com acesso configurado por conta. Outros bancos e convênios poderão ser adicionados ao catálogo.

O identificador `digimais_saldo_parcela` é salvo nos lotes e consultas; os registros anteriores recebem esse valor. Histórico, campanhas e exportações identificam o serviço. Cada serviço usa sua fila correspondente no mesmo worker serial. A RPC anterior permanece compatível. Para habilitar um serviço futuro, será necessário adicionar suas regras, permissões e processamento, além de sua opção no catálogo.

O Supabase original já recebeu a migração. Em outro projeto existente, execute `supabase/upgrade_servicos.sql` antes de atualizar. O auto instalador distribui o painel, o novo CSS e a proteção de roteamento do worker. Execute a opção 1 e recarregue a página com Ctrl + F5.

### Monitoramento da VPS

Em **Configurações → Recursos da VPS**, acompanhe CPU, RAM utilizada/disponível, swap, disco, tempo ligada e estado do serviço do robô. O coletor independente `apoiarcred-monitor` envia uma coleta a cada 5 segundos. A interface consulta os dados enquanto Configurações estiver aberta e a página visível. Após 20 segundos sem coleta recente, sinaliza dados desatualizados. Serviço ativo e modo de consultas habilitado são indicadores separados.

A opção **1 — Atualizar** instala e inicia o coletor automaticamente. Ele usa a conexão existente com Supabase e não abre portas nem altera Nginx. Trocar o Supabase pelo instalador também reinicia o monitor. O projeto original já recebeu a tabela; em outro projeto, execute `supabase/upgrade_monitoramento.sql` antes de atualizar. Instalação nova usa o schema completo.

O Supabase mantém apenas a última coleta agregada, sem histórico crescente, nomes de processos, comandos, credenciais ou dados de clientes. As contas autenticadas do sistema interno podem ler as métricas; apenas a chave de serviço da VPS pode gravar. Este MVP monitora uma VPS por projeto Supabase. Dois coletores no mesmo projeto disputariam o registro `principal`.

Se os dados não aparecerem, verifique:

```bash
systemctl status apoiarcred-monitor
journalctl -u apoiarcred-monitor -n 50 --no-pager
```

O coletor usa apenas a biblioteca padrão Python e `/proc` do Linux. O serviço tem limite de memória de 64 MB e cota de CPU de 10% de um núcleo. As métricas representam o total da VPS. Se a máquina cair, o painel sinalizará dados antigos; não substitui alertas externos de disponibilidade.

### TJBA · Consulta de margem

Selecione **Consulta de margem → TJBA** no tipo de higienização. O CPF é obrigatório; nome e telefone são opcionais. Aceita consulta individual e campanhas com Excel, CSV ou TSV. O botão de modelo baixa `modelo-tjba.csv` quando TJBA está selecionado. Substitua o CPF de exemplo. Zeros à esquerda são completados até 11 dígitos.

Os resultados mostram nome retornado pelo portal, CPF, matrícula, tipo de servidor, situação, margem **disponível** de empréstimo, margem **disponível** de cartão, data, status e observações. Ausência de valor é `null`, exibido como `—`; valores zero e negativos são preservados. A simulação Amigoz se aplica apenas aos resultados Digi+. Histórico, filtros, exportação, exclusão e nova tentativa da campanha usam o serviço correspondente.

Em **Configurações → Acesso ao portal TJBA**, informe usuário e senha do portal e salve. A senha é cifrada no Supabase Vault e não volta para o navegador; o robô na VPS é o único consumidor da leitura do segredo. Cada conta usa suas próprias credenciais. Senha vazia mantém o segredo existente; trocar o usuário exige informar a nova senha. O campo de senha é limpo depois de enviar. **A habilitação vem desmarcada**: ative depois de homologar o fluxo com CPFs autorizados. Nunca coloque credenciais no código, no GitHub, em capturas ou nos logs.

O worker usa a mesma infraestrutura, processando um CPF por vez, alternando as filas Digi+ e TJBA quando ambas têm consultas. A integração do banco é aditiva: `tjba_lotes`, `tjba_jobs` e `consulta_tjba_historico`, com RLS por conta. As tabelas e RPCs existentes do Digi+ permanecem preservadas. Resultados TJBA são gravados como `NUMERIC(14,2)`; CPF e matrícula são texto. O histórico mantém resultados anteriores nas novas tentativas de campanha e é removido junto da consulta/campanha quando você confirmar a exclusão.

A sessão do navegador TJBA é reutilizada entre CPFs consecutivos da mesma conta e revisão das credenciais. Trocar conta, alterar credenciais, ficar ocioso por 120 segundos ou processar Digi+ fecha essa sessão. Não são salvos cookies nem estado de navegador em disco. Falha de autenticação/expiração pausa novas tentativas de login daquela revisão; valide o acesso e salve novamente as configurações para liberar uma tentativa. CAPTCHA, MFA ou mudança de fluxo retornam revisão; não são contornados.

**Validação realizada em 02/11/2026:** login autorizado no navegador, seleção do convênio pela tabela `#gvOrgao`, confirmação pelo cabeçalho `#descricaoOrgaoLabel`, primeira e segunda consulta na mesma sessão, botão `#body_voltarButton`, dados do servidor e as duas margens. Um caso retornou margem negativa, preservada. A coluna correta é “Margem Disponível (R$)”; não é margem total. O campo `#body_cpf_nascimentoTextBox` contém o CPF retornado nessa tela, apesar do nome. Nenhum CPF real ou credencial é incluído no repositório.

**Limites:** esses testes foram interativos no navegador. O worker autônomo ainda precisa de homologação na sua VPS. Casos reais de múltiplas matrículas, CPF não encontrado, CAPTCHA e sessão expirada não foram fornecidos nesta validação; há testes automatizados de parsing/isolamento/sessão, e o robô retorna revisão se não conseguir confirmar a estrutura. Múltiplas matrículas só permitem seleção quando existe uma única situação ativa verificável e a ação Selecionar é reconhecida. Não há clique em Reservar Margem, propostas ou operações financeiras. Sem integração com Google Sheets.

O projeto Supabase original já recebeu `upgrade_tjba.sql` e `upgrade_tjba_privacy.sql`. Em outro projeto existente, execute os dois arquivos, nessa ordem, uma única vez, antes de atualizar pela opção 1. Instalação nova usa `supabase/schema.sql`. O instalador distribui `vps/tjba.py`, o roteamento do worker e as telas; não precisa de nova dependência Python.

Rotas Supabase (sempre com autenticação da conta; a chave de serviço só fica na VPS):

| Operação | Rota |
| --- | --- |
| Criar campanha TJBA | `POST /rest/v1/rpc/create_tjba_campaign` com `p_nome` e `p_items` |
| Criar consulta individual | `POST /rest/v1/tjba_lotes` com tipo `individual`, depois `POST /rest/v1/tjba_jobs` com o lote e CPF |
| Ler resultados | `GET /rest/v1/tjba_jobs?id=eq.ID` ou `lote_id=eq.ID` |
| Ler histórico | `GET /rest/v1/consulta_tjba_historico?job_id=eq.ID` |
| Nova tentativa da campanha | `POST /rest/v1/rpc/retry_tjba_campaign` com `p_campaign_id` |
| Salvar acesso | `POST /rest/v1/rpc/save_tjba_credentials` com `p_username`, `p_password`, `p_enabled` |
| Ver configuração sem senha | `POST /rest/v1/rpc/tjba_credentials_status` |
| Buscar credencial / retirar da fila | `get_tjba_credentials` / `claim_tjba_job`: exclusivos do serviço na VPS |

Exemplo **fictício** de resultado normalizado:

```json
{"cpf":"00123456789","status":"concluida","servico":"tjba_margem","tipo_higienizacao":"margem","provedor":"tjba","matricula":"000123","tipo_servidor":"ESTATUTARIO","situacao_atual":"Ativo - ATIVO","emprestimo_disponivel":"0.00","cartao_disponivel":"-10.25","tjba_status":"consultado"}
```

Testes: `python3 -m unittest discover -s tests -q`, `node tests/test_tjba_frontend.cjs` e regressões do painel. `tests/tjba_database.sql` verifica Vault, três CPFs sintéticos, isolamento entre contas, bloqueio de leitura de senha no navegador, zero/negativo, histórico, nova tentativa e exclusão em transação revertida. Nenhuma consulta de teste fica na fila.

### Correção do acesso TJBA e diagnóstico por etapa

O robô inicia pela página pública `/`, aguarda a navegação do login, seleciona o convênio e somente depois abre `/Margem/ConsultaMargem.aspx`. O transporte Chromium do ConsigX usa a configuração padrão, sem herdar os ajustes HTTP/2 específicos do Digi+. O aviso de cookies conhecido é fechado antes das ações e por um handler persistente.

O log em Configurações distingue: carregar Playwright (5%), iniciar Chromium (8%), criar contexto (10%), abrir login (12%), identificar formulário (15%), enviar login (18%), selecionar convênio (22%) e abrir consulta (28%). Durante a execução, a tela principal continua mostrando apenas “Consultando...”. Em falhas, a porcentagem e a etapa efetivamente atingidas são preservadas. O diagnóstico guarda somente tipo de exceção, código de rede aprovado e rota conhecida sem parâmetros; não copia a exceção bruta, senha, cookies ou tokens.

Para falhas antes da consulta, atualize pela opção 1 e use **4 — Diagnosticar ambiente TJBA**. O comando testa DNS, TLS, inicialização do Chromium e a página pública como usuário do serviço, **sem fazer login e sem enviar CPF**. Um diagnóstico aprovado confirma o ambiente e a abertura do formulário, mas não comprova a autenticação nem a consulta completa. Confira também `journalctl -u apoiarcred-robo -n 80 --no-pager` e o log por CPF em Configurações.

A revisão foi conferida com teste interativo de um terceiro CPF autorizado; o portal retornou ambas as margens. A execução autônoma da VPS ainda depende do teste local e do novo log por etapa para identificar qualquer divergência do ambiente. Casos de login, ordem das rotas, aviso de cookies e preservação segura do erro têm testes automatizados com páginas simuladas; não são apresentados como login real executado pelo worker na VPS.


### Proxy privado exclusivo do TJBA

Atualize pela opção 1 e reabra `bash /opt/apoiarcred-src/instalar.sh`.
A opção **5 — Configurar ou remover proxy TJBA** solicita endereço completo
(`http://HOST:PORTA`), usuário e senha oculta. Use um proxy HTTP/HTTPS com suporte
CONNECT. As credenciais ficam somente em `/opt/apoiarcred/tjba-proxy.json`,
com dono root, grupo apoiarcred e permissão 640; nunca no frontend ou GitHub.
O arquivo é preservado nas atualizações. Não inclua esse arquivo em commits.
A opção 5 reinicia o robô se estiver ativo: configure quando não houver consulta em execução.

Execute a opção **4** após configurar. Ela usa o mesmo proxy do robô e verifica
HTTPS e os campos de login sem enviar credenciais do portal ou CPF. Nesse modo,
não testa a rota direta ao ConsigX, pois ela pode estar indisponível.
Só considere homologado após uma consulta individual real concluir e salvar os resultados.

O proxy afeta exclusivamente o navegador TJBA. Digi+, Supabase, SSH e site mantêm
suas conexões. A validação TLS continua habilitada. Configuração inválida gera erro;
não há tentativa automática pela conexão direta. Para voltar ao acesso direto,
use a opção 5 e escolha remover. A senha do proxy é diferente da senha do portal.

### Conferir credenciais TJBA no banco (administrador)

No SQL Editor do Supabase, como postgres, execute:

```sql
select * from apoiarcred_private.tjba_credentials_admin;
```

A consulta exibe login e senha atual, versão da senha, data de alteração real e data
do último salvamento. Não compartilhe o resultado. A view privada não é acessível
pelo frontend nem pelos papéis anon/authenticated/service_role. O Vault mantém a
senha criptografada em repouso. Alterações feitas pelo formulário incrementam a
versão somente quando o conteúdo da senha muda. Senha em branco preserva a anterior;
a mesma senha não incrementa a versão. Registros anteriores começam em versão zero
e data desconhecida; não reconstruímos histórico anterior. Edições diretas no Vault
não passam por esse controle: use o formulário do sistema para alterar.

### Novas tentativas de login TJBA

O robô tenta autenticar até três vezes no mesmo navegador, contexto e proxy,
com pausa de dois segundos e limite total de 90 segundos para a autenticação.
Repete apenas retorno simples ao formulário, campos limpos ou timeout transitório.
Senha inválida permite uma segunda tentativa com as mesmas credenciais, fechando somente
o aviso informativo OK. Se persistir na segunda tentativa, interrompe.
Outros avisos do portal, CAPTCHA, bloqueio, confirmação e cadastro interrompem
as tentativas. O log técnico mostra o número da tentativa; o painel mantém Consultando.
Após esgotar as tentativas, a autenticação fica pausada até salvar o acesso novamente
ou reiniciar o serviço. As consultas de CPF não são repetidas por essa lógica.

O aviso exato “Usuário já logado, deseja desconectar seu usuário dos outros terminais?”
é confirmado automaticamente conforme autorização do operador. Isso encerra outras
sessões desse mesmo usuário no ConsigX. O robô aguarda a lista de convênios ou
o cabeçalho do convênio após confirmar; outras confirmações permanecem manuais.

### Confirmação com elementos sobrepostos no ConsigX

Para o aviso autorizado de desconexão de outros terminais, o robô ativa o botão
`ucAjaxModalPopupConfirmacao1_btnConfirmarPopup` com Enter, evitando que a sobreposição
visual do formulário de login intercepte o clique. A ação ocorre apenas após conferir
o texto específico do aviso. Depois exige a lista de convênios ou o cabeçalho TJBA;
a presença de formulários de cadastro no documento não equivale a um cadastro ativo.
Essa adaptação não corrige os scripts do portal: valide uma consulta individual após
atualizar pela opção 1 do instalador.

### Consulta TJBA mantendo a verba padrão

Validado visualmente no portal: a consulta por CPF com Cartão selecionado retorna
as linhas de empréstimo e cartão em Detalhes da Margem. O robô preserva a seleção
padrão e lê a coluna Margem Disponível de cada linha; não utiliza o valor isolado
do cabeçalho para representar as duas margens. Isso remove a troca de verba que
parava nos 40%. Outros convênios ainda exigem validação própria.

### Convênios ConsigX

Selecione ConsigX — Consulta de margem e escolha TJBA, DPEBA, EMBASA, SAEB
ou SUPREV no campo Convênio. A escolha vale para a consulta individual ou nova
campanha; cada campanha mantém seu convênio em novas tentativas. Consultas antigas
são TJBA. O mesmo login e proxy privado são utilizados, mas ao mudar de convênio
o robô cria uma sessão com verificação do cabeçalho do órgão escolhido.

Resultados, lista de campanhas e exportação identificam o convênio. Os quatro
convênios além do TJBA estão disponíveis para homologação: ainda não tiveram suas
margens validadas com CPFs reais nesta integração. Diferenças de estrutura resultam
em revisão, nunca em margem zero presumida. Em instalações com outro Supabase,
aplique também `supabase/upgrade_consigx.sql` antes de atualizar o painel. No projeto
original essa atualização do banco já foi aplicada. Instalações novas usam schema.sql.

Quando há múltiplas matrículas, o robô só seleciona se houver uma única situação
ativa identificável. Usa o botão de imagem Selecionar da linha ativa. Se houver
mais de uma ativa, ou nenhuma verificável, solicita revisão com os vínculos retornados.

### Dois executores Digi+ na mesma campanha

A atualização inicia dois executores Digi+ por padrão dentro do serviço existente.
Não execute dois serviços completos manualmente. Cada executor possui seu próprio
navegador/chat. A arquitetura é:

```mermaid
flowchart TD
  A[Campanha com CPFs únicos] --> B[Fila Supabase: reserva atômica]
  B --> C[Executor Digi+ 1]
  B --> D[Executor Digi+ 2]
  C --> E[Resultados por consulta]
  D --> E
```

A RPC `claim_consulta_job` reserva uma linha aguardando com `FOR UPDATE SKIP LOCKED`
e a marca processando na mesma transação. O segundo executor recebe outra linha.
O índice único `(lote_id, cpf)` impede CPF repetido na mesma campanha, inclusive
por inserção direta. Resultados concluídos não entram na reserva; a nova tentativa
da campanha continua restrita a erros/revisão, atualizando as mesmas linhas.

Se salvar o resultado falhar, o executor mantém o trabalho e repete somente a gravação,
sem consultar o banco novamente. Se o serviço cair durante uma consulta, o trabalho
permanece processando: não é reenfileirado automaticamente, pois a consulta externa
pode já ter ocorrido. É necessária conferência antes de qualquer reenvio. Não existe
promessa de execução exatamente uma vez no portal externo após uma falha de processo.

O CPF pode aparecer em campanhas diferentes para uma nova consulta intencional;
o resultado histórico de outra campanha não é tratado como atualizado. A prevenção
de repetição é por campanha. CPFs são armazenados com 11 dígitos, sem pontuação.

Os três robôs alternam Digi+ e ConsigX. No ConsigX, cada login de portal
tem uma consulta ativa por vez para evitar que novas sessões derrubem a consulta
em andamento. Logins distintos podem ser processados em paralelo. Em Configurações → Operação → Acesso ao portal ConsigX, o administrador pode cadastrar um login por robô para as campanhas da própria conta. Robôs sem login exclusivo usam o acesso principal. As senhas ficam no Vault.

O serviço começa com um robô ativo e libera os demais após períodos de folga.
A cada 5 segundos, verifica CPU e RAM da VPS. Com RAM disponível abaixo de 256 MiB
ou 15% do total (o maior valor), ou CPU acima de 95% por três coletas,
suspende um robô adicional. O robô termina e grava a consulta atual antes de fechar
o navegador. Após seis coletas com CPU de até 75% e RAM disponível de pelo menos
512 MiB e 25% do total, libera um robô por vez. Um robô permanece ativo.
`ROBOT_WORKERS` define o máximo entre 1 e 3 e substitui a configuração legada
`DIGIMAIS_WORKERS` quando ambas estiverem presentes. Sem configuração, o máximo é 3.

A opção 1 do auto instalador publica o novo worker e preserva o .env/proxy/SSL.
No projeto Supabase original o índice já foi aplicado; outros projetos precisam
executar `supabase/upgrade_digimais_concurrency.sql`. A migração não apaga duplicados:
se houver registros antigos repetidos, resolva-os antes de criar o índice.

Validação: teste automatizado executa os dois slots simultaneamente com CPFs distintos,
simula falha ao salvar e confirma uma única execução por trabalho. Teste SQL verifica
bloqueio de CPF duplicado em transação revertida. Velocidade e memória reais devem ser
medidas numa campanha pequena na VPS; o limite externo do chat pode afetar o ganho.

### Atualizar com uma campanha em andamento

Use a opção 1 normalmente, sem parar o serviço manualmente. Antes de copiar o código,
o instalador solicita uma pausa temporária na reserva de novos trabalhos pelo banco.
As consultas já em execução continuam no código antigo até salvarem o resultado.
Só quando não houver trabalhos processando ele para o serviço, aplica a atualização,
libera a fila e inicia a nova versão. Os dois executores Digi+ pegam os CPFs restantes
com status aguardando. Campanhas, resultados, progresso e contagens ficam no Supabase.
A pausa de reserva também protege a sessão ConsigX enquanto o mesmo serviço é atualizado;
a concorrência adicional continua exclusiva do Digi+.

Se houver um trabalho antigo preso em processando, o instalador aguarda no máximo
10 minutos e cancela a atualização, liberando a fila e mantendo o serviço em execução.
Ele não transforma trabalhos incertos em aguardando nem repete consultas automaticamente.
Se o terminal desaparecer durante a manutenção, a pausa expira em 30 minutos; use o
instalador novamente para conferir o estado antes de retomar uma atualização incompleta.
Essa proteção não cobre desligamento abrupto da VPS ou kill forçado. O helper usa
um token de manutenção e bloqueio transacional compartilhado com as RPCs de reserva,
para que uma nova consulta não comece entre a última verificação e o stop do serviço.

### Interface e controle de campanhas

Nova campanha tem três etapas: Consulta → Planilha → Conferir e iniciar.
Use Saldo e parcela — Digi+ ou Margem — ConsigX; convênio só é necessário no segundo.
O modelo Digi+ permanece com nome, cpf e telefone. O modelo ConsigX contém somente cpf.
Excel, CSV e TSV continuam aceitos; nome e telefone extras são opcionais no ConsigX.

Todas as campanhas aparecem juntas, com busca, filtro de andamento, progresso e
identificação da consulta/convênio. Ao abrir, há resultados na ordem de entrada,
CPF(s) em execução, Pausar/Retomar e repetição de erros/revisões. Ações por cliente
ficam no menu Ações. A data de consulta só aparece após o retorno ser registrado.

A pausa é persistida no Supabase e impede novas reservas daquela campanha; consultas
já reservadas terminam. Retomar preserva os resultados e libera apenas os pendentes.
Cada fila (Digi+ e ConsigX) prioriza o lote mais antigo não pausado com pendentes ou
em andamento. Só passa ao próximo quando o anterior terminar ou for pausado.
Digi+ ainda pode ter dois CPFs em execução: ordem de reserva é estável, conclusão
pode variar. Consulta individual também usa essa fila e respeita sua vez.

Novas campanhas usam a ordem explícita das linhas importadas. Nos registros antigos,
a sequência anterior não foi armazenada: a atualização atribui uma ordem estável,
mas não recupera com certeza a ordem original das planilhas antigas. Não apaga nem
reconsulta resultados. A numeração da tabela é a posição dentro da campanha e não
muda quando se usa filtro. Exportações também respeitam a ordenação.

O projeto Supabase original já recebeu a migração. Em outros projetos, aplique
`supabase/upgrade_campaign_ux.sql` após as migrações anteriores, antes de atualizar
o painel. Para instalar a nova interface na VPS, use opção 1 do instalador e Ctrl+F5.
Testes: `node tests/test_workspace.cjs` e `tests/campaign_ux_database.sql` (rollback).
O teste SQL verifica ordem, avanço entre campanhas, pausa/retomada e isolamento.

### Simulador Amigoz: juros Price, encargos e agregação de margem

As sete tabelas usam suas taxas contratuais mensais (3; 3,25; 3,50; 3,75; 3,98;
4,50; 4,80%), prazo editável de 1 a 600 meses e primeira parcela após um mês.
O CET não é somado nem utilizado como taxa de juros. A capacidade financiada é
parcela × (1 − (1 + i)^(-n)) / i; com i zero, parcela × prazo.

O painel considera somente juros mensais, parcela e prazo. IOF, seguros,
despesas e teto pré-aprovado não entram no cálculo; os campos para informar esses
custos foram removidos. Limite, troco e comissão são estimativas antes dos encargos.
O cálculo preserva precisão numeric no banco, arredonda o limite para baixo em
centavos e confere se a parcela cabe na escolhida. Troco = limite − quitação.
Se insuficiente, não exibe troco ou comissão disponível. A comissão configurada
permanece opcional e incide sobre quitação + troco.

Agregar margem / alterar parcela aceita a parcela total escolhida para esta
simulação, preservando valor_parcela do trabalho original. O resultado registra
parcela original, parcela simulada e margem adicional necessária. A disponibilidade
extra precisa ser conferida no banco: ela não é inferida da consulta Digi+.
Não use esse modelo para carência, vencimentos irregulares ou juros diários.

A RPC simular_amigoz_price valida proprietário e salva todas as condições e saídas
em amigoz_simulacoes. O método é price_juros_contratuais_encargos_separados_v2;
simulações históricas anteriores mantêm seu próprio método. O helper interno
também trata taxa efetiva anual via potência 1/12, nunca divisão por 12.
Em outros projetos Supabase, aplique upgrade_amigoz_price.sql. O projeto original
já foi atualizado. Testes numéricos e de isolamento: tests/amigoz_database.sql.

### Simulação simplificada por juros mensais

O painel usa somente taxa de juros mensal, parcela e prazo na Tabela Price.
IOF, seguros, despesas e teto pré-aprovado não entram no cálculo. Os campos
para informar esses custos foram removidos. Limite, troco e comissão são
estimativas antes dos encargos, sujeitas à confirmação do banco. A opção
de agregar margem preserva a parcela original da consulta. O cálculo no
Supabase continua disponível; o painel envia explicitamente o modo sem
encargos financiados para as sete tabelas em cada simulação.

O simulador organiza prazo, parcela e recálculo em um painel único e compara
as sete taxas em cartões, destacando o maior troco entre resultados disponíveis.
Alterações exibem aviso para recalcular. A janela aceita Escape para fechar e
mantém a navegação de teclado dentro do simulador. Em telas pequenas, os cartões
ficam em uma coluna. Esta alteração visual preserva o cálculo por juros mensais.

### Ciclo de navegador Digi+ por CPF

Cada executor abre um Chromium para o CPF e reaproveita esse navegador entre
as consultas de saldo e parcela. Ao terminar o CPF, fecha o navegador antes de
salvar o resultado final e reservar o próximo trabalho. O padrão foi ajustado
para evitar manter processos e caches do Chromium durante uma campanha inteira
na VPS de 2 GB. Os dois executores continuam em paralelo, sem esperar pelo outro.

Cada atendimento usa um contexto novo, fechado ao terminar, sem compartilhar
cookies ou dados de clientes. O fluxo do portal permanece o mesmo. Não reutiliza
um chat encerrado. A regra de pular parcela para não clientes e o salvamento
parcial do saldo continuam ativos. Falhas não repetem automaticamente a consulta;
se falhar a gravação final, somente a gravação é repetida.

O monitoramento permanece ativo. Os logs ETAPA identificam o executor e tempo
acumulado; DURAÇÃO separa processamento e gravação final para investigar lentidão.
Não registram CPF ou credenciais. Consulte `journalctl -u apoiarcred-robo -n 80 --no-pager`.
A alteração reduz a retenção de navegadores entre CPFs; não comprova por si só a
causa de uma lentidão. É necessário comparar tempo/volume e RAM/swap na VPS.

Instale pela opção 1 do auto instalador. Não exige variáveis, migração de banco ou
alteração nas credenciais. O instalador aguarda as consultas em andamento antes
de trocar o código. Validação sem tráfego ao banco: `python3 -m unittest discover -s tests`.

### Monitoramento de atividade dos robôs

Configurações → Atividade dos robôs mostra até três executores, serviço atual,
progresso, duração e pausas por pressão de recursos.
A atualização é a cada 5 segundos, enquanto Configurações estiver aberta.

O worker escreve um estado agregado em `/run/apoiarcred-robots/state.json`,
com permissão 0600. O diretório 0700 pertence ao usuário do serviço e é criado
pelo systemd. O coletor existente envia os agregados no payload de monitoramento.
Não transmite CPF, nome, telefone, IDs de consultas ou credenciais. Mantém a mesma
regra existente de acesso ao monitor: usuários autenticados veem dados agregados
da operação. Não é necessário mudar o esquema do Supabase.

Volume, erros, revisões, percentual conclusivo e duração média usam uma janela
móvel de 60 minutos, limitada ao período desde o último reinício do worker.
Só contam consultas após confirmação de salvamento final. A duração mede o
processamento (inclui as duas etapas Digi+ e o checkpoint do saldo), excluindo
espera na fila e tentativas de gravar o resultado final. Retorno conclusivo inclui
concluído e ausência confirmada de cliente/registro; revisão e erro não contam.
A mensagem de ausência de avanço é um aviso, não diagnóstico automático de travamento.
Após 20 segundos sem heartbeat ou coletor atualizado, o painel não confirma o
estado atual e sinaliza dados desatualizados. Estatísticas não são histórico permanente.

A opção 1 do auto instalador atualiza worker, coletor, serviço e painel, aguardando
as consultas em execução como antes. Nenhuma configuração extra é necessária.

### API v1 e novas configurações

Configurações foi organizada em Operação, Robôs e monitoramento, Comissões,
Integrações e Conta e diagnóstico. Os formulários anteriores permanecem nesses grupos.
Em Integrações, gere um token por sistema, escolha validade/permissões e copie
uma única vez. A lista permite conferir último uso e revogar. Token nunca é
salvo em texto no banco; as chaves Supabase não são tokens de integração.

A documentação completa, payloads, respostas e cURLs ficam na própria página.
Arquivo OpenAPI em `/openapi.json` e instruções também em [docs/api.md](docs/api.md).
Base: `https://SEU_SUBDOMINIO/api/v1`. Cada token acessa somente sua conta.
Crie campanha (pausada), adicione leads e inicie. Consultas são assíncronas e
seguem a fila existente. POST de escrita exige Idempotency-Key por operação.

O Supabase original já recebeu a atualização. Em outro projeto, execute
`supabase/upgrade_api.sql` após as atualizações anteriores. Então use opção 1 do
instalador na VPS e Ctrl+F5. O instalador instala e habilita apoiarcred-api,
configura o Nginx preservando SSL e publica o serviço em /api/. Nenhum token é
gerado automaticamente. Não é preciso abrir nova porta ou usar Docker.
A API escuta apenas em 127.0.0.1:8877, com até 16 requisições simultâneas;
limite por token de 120/minuto e proteção por IP de 5/s (rajada de 20).

Diagnóstico: `systemctl status apoiarcred-api` e
`curl --fail http://127.0.0.1:8877/api/health`. O health confirma o processo;
verifique GET /api/v1/servicos com seu token para confirmar acesso ao banco.
Os logs HTTP não incluem token, payload ou CPF. Migrações não são executadas
pelo instalador: o projeto original já foi migrado; projetos próprios exigem o SQL.

Validação: `tests/api_database.sql` roda em transação com rollback e exercita
idempotência, importação parcial, pausa, busca, permissões e isolamento entre contas.
`python3 -m unittest discover -s tests` cobre gateway HTTP e instalação/atualização.

### Perfis de administrador e parceiro

Configurações → Parceiros (somente administrador) permite criar acesso por e-mail
e senha inicial, definir nome, ativar/desativar novos envios e configurar cada tipo:
Digi+ saldo/parcela e ConsigX margem. Cada tipo tem liberação, individuais,
limite diário inteiro (0 bloqueia) e permissão de campanhas independentes.
ConsigX compartilha a mesma cota entre TJBA, DPEBA, EMBASA, SAEB e SUPREV.
Campanhas permitidas não consomem a cota individual. O administrador é ilimitado.

O parceiro vê apenas suas próprias consultas e campanhas, tipos liberados e saldo
individual do dia. O monitor global e a gestão de parceiros são restritos ao admin.
ConsigX mantém as credenciais de portal próprias de cada conta; não compartilha
senhas do administrador. Liberar esse serviço não dispensa configurar/homologar
o acesso ao portal em Operação.

A cota usa America/Sao_Paulo e renova à meia-noite. Conta cada novo pedido individual
aceito na fila, independentemente do resultado posterior; nova tentativa consome
nova cota. Saldo e parcela Digi+ contam juntos como uma consulta. Excluir registros
não devolve a cota. Repetir uma requisição de API com a mesma Idempotency-Key não
consome novamente. O contador fica no banco, protegido por bloqueio transacional;
vale na interface, API e inserções diretas autorizadas. Não é controle só visual.
Alterar permissões vale para novos envios/retomadas; trabalhos aceitos continuam.

No projeto original, a única conta existente foi configurada como administrador.
Em outro projeto, aplique `supabase/upgrade_partners.sql` após upgrade_api.sql.
Se houver exatamente uma conta existente, ela será o admin inicial. Em projetos
com várias contas, o responsável pelo banco deve escolher explicitamente o admin:

```sql
insert into apoiarcred_private.user_profiles(user_id,role,name,email)
select id,'admin',split_part(email,'@',1),email from auth.users
where email='EMAIL_DO_ADMIN'
on conflict(user_id) do update set role='admin',active=true;
```

Nenhum usuário pode escolher ou promover seu próprio perfil. Metadados editáveis
de usuário não são usados para autorizar ações. O backend verifica a sessão Auth
e o perfil do administrador antes de criar acesso com a chave privada da VPS.
A senha vai somente ao Supabase Auth; nunca é salva em texto no cadastro de parceiro
ou devolvida pela listagem. Falha ao configurar permissões tenta desfazer apenas a
conta recém-criada, que permanece sem acesso se a limpeza também falhar.

O cadastro administrativo usa /api/admin/parceiros (sessão de administrador),
não aceita tokens de integração. Atualize pela opção 1 do instalador para publicar
API e painel novos; depois Ctrl+F5 e entre novamente. Supabase original já migrado.
Não há migração automática pelo instalador em projetos diferentes.

Validação adicional: `tests/partners_database.sql` (rollback) verifica cotas por
tipo, não reembolso por exclusão, API/idempotência, campanhas e permissões.
`tests/test_partners_admin.py` testa autorização, criação e falhas do gateway sem
criar contas reais. Contas sintéticas das demais suítes SQL são admins de teste.

## Webhooks de resultados

Configure em **Configurações → Integrações → Webhooks** ou pelo botão no detalhe da campanha. Escolha origem/campanha, serviço, status, identificação do cliente e resultados parciais. Há teste fictício, segredo de assinatura, pausa, histórico e reenvio. Os envios usam um serviço independente dos robôs.

A opção **1** do instalador também atualiza e inicia `apoiarcred-webhooks`. No Supabase já conectado, a migração foi aplicada; em outro projeto existente execute `supabase/upgrade_webhooks.sql` uma vez. Para um banco novo, o schema completo já inclui webhooks.

Veja [payloads, assinatura, tentativas e instalação](docs/webhooks.md).

### Liberação de integrações para parceiros

Em **Configurações → Parceiros**, marque **Liberar integrações (API e webhooks)** ao criar ou editar o parceiro. Parceiros novos e existentes começam sem essa liberação; administradores ativos mantêm acesso. Desativar bloqueia a API (inclusive tokens já criados), a gestão de integrações e novos envios de webhook. Os pendentes são preservados para quando houver nova liberação; um envio já iniciado pode terminar. As consultas do painel seguem suas próprias permissões.

O parceiro não visualiza **Conexão e administração** nem as orientações de troca de chaves do Supabase. A opção 1 do instalador atualiza a interface e a API administrativa. A alteração de banco já foi aplicada no projeto conectado; em outro projeto execute `supabase/upgrade_partner_integrations.sql` depois das migrações de parceiros e webhooks. O schema completo já inclui a alteração.

Em projetos Supabase existentes, aplique `supabase/upgrade_admin_campaign_limits.sql` para habilitar campanhas sem limite de registros para administradores.

A migração `supabase/upgrade_shared_robots.sql` habilita a reserva paralela do ConsigX por login. A tabela de clientes das campanhas exibe 50 registros por página.

Para a tela unificada de acesso ConsigX, aplique `supabase/upgrade_consigx_access_editor.sql` após a migração dos três robôs. A tela usa os acessos e as senhas já cadastrados no Vault.

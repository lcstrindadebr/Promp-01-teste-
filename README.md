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

Substitua o exemplo pelos clientes. CPF e telefone devem ser texto para preservar zeros à esquerda. O painel aceita até 1.000 registros, valida a planilha e mostra linhas que precisam de correção antes da importação. A linha de exemplo não é enviada ao robô. Os arquivos devem ter no máximo 2 MB.

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
  Cada campanha admite até 1.000 clientes. CPFs repetidos são indicados na prévia.
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

Aceita `.xlsx`, `.xls`, `.csv` (vírgula ou ponto e vírgula) e `.tsv` (tabulação). Limites: 2 MB e 1.000 clientes. No Excel, coloque os dados na primeira aba, com cabeçalho na primeira linha: `nome`, `cpf`, `telefone`. Também são reconhecidos `Nome completo`, `Celular` e `Telefone com DDD`. Substitua a linha de exemplo antes de importar. CPF e telefone devem ser texto; CPFs numéricos curtos recebem zeros à esquerda até completar 11 dígitos.

O botão é liberado depois da leitura, com nome de campanha e ao menos uma linha válida. Erros ficam visíveis abaixo do botão, com detalhes por linha. Linhas inválidas e CPFs duplicados não são enviados; revise a prévia antes de criar a campanha. O leitor Excel SheetJS CE 0.20.3 é distribuído localmente em `dist/vendor`, com licença; o navegador não depende de CDN para importar.

Validação: `node tests/test_import_formats.cjs` testa arquivos reais nos quatro formatos, criação via RPC simulada, zeros à esquerda, arquivo inválido, limite de linhas e troca rápida de arquivo. `tests/campaigns_database.sql` valida a criação e o isolamento no banco em transação revertida, sem deixar clientes na fila.

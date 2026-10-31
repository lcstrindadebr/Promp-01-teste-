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

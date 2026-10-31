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

O MVP gerencia uma instância por VPS no caminho padrão. Instalações incompletas podem ser retomadas pela opção instalar. Atualizações preservam `.env`, projeto Supabase, certificado e modo do robô, sem executar migrações automaticamente.

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

## Robô

O robô inicia com `ROBOT_MODE=disabled` no servidor. Isso é uma proteção de homologação do worker, **não um modo selecionável no painel**: a fila e os resultados continuam no Supabase. Nesse estado, registros retornam Revisão sem consultar o banco.

A execução completa no Digi+ ainda precisa de homologação na VPS. Para uma consulta autorizada de teste:

```bash
nano /opt/apoiarcred/.env
# Altere ROBOT_MODE=disabled para ROBOT_MODE=live, salve e execute:
systemctl restart apoiarcred-robo
```

Valide uma consulta individual antes de lotes. Se uma tarefa for interrompida, revise antes de reenviar: recuperação automática de consultas em processamento ainda não está implementada.

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

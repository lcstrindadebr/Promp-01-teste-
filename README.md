# ApoiarCred · Instalar direto do GitHub

VPS Ubuntu Server **24.04 x86-64**, **2 vCPU e 4 GB RAM**. Sem Docker e sem ZIP. Os comandos são executados na VPS como root.

## 1. DNS

| Tipo | Nome | Valor |
|---|---|---|
| **A** | **consultas** | **IP público da VPS** |

Resultado: `consultas.apoiarcred.com.br`. É A porque o destino é um IP. Libere TCP 80/443 no provedor. Se usar Cloudflare, comece com Somente DNS.

## 2. Instalar direto do repositório

Se a chave SSH da VPS já tem acesso ao repositório privado, basta executar:

```bash
apt update && apt install -y git openssh-client
git clone --branch apoiarcred-consultas-mvp --single-branch git@github.com:lcstrindadebr/Promp-01-teste-.git /opt/apoiarcred-src
bash /opt/apoiarcred-src/instalar.sh
```

O Git é instalado automaticamente **na VPS**, apenas para puxar o código. Não precisa instalar GitHub nem baixar nada no seu computador. No primeiro acesso SSH, confira a impressão digital do GitHub antes de aceitar.

O instalador pergunta **subdomínio, e-mail do SSL e chave secreta do Supabase**, e pede confirmação dos termos do certificado. Depois configura Python, Chromium, Nginx, HTTPS e o serviço do robô.

### Se aparecer Permission denied (publickey)

O repositório é privado: a VPS precisa de autorização uma única vez. Se ainda não tem chave, crie na VPS:

```bash
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -C apoiarcred-vps
cat /root/.ssh/id_ed25519.pub
```

Se o arquivo já existir, não sobrescreva: use a chave existente. Copie a chave **pública** para o GitHub → repositório → Settings → Deploy keys → Add deploy key. Deixe somente leitura. Depois repita o clone e a instalação. A chave privada fica na VPS; não envie por chat.

[Conferir impressão digital SSH do GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).

Se a pasta `/opt/apoiarcred-src` já existir por uma tentativa anterior, não clone por cima. Confira se é este repositório e, nele, use `git pull --ff-only origin apoiarcred-consultas-mvp` e execute o instalador. Não apague instalações existentes.

## 3. Atualizar com um comando

Após instalar:

```bash
apoiarcred-atualizar
```

Ele puxa a branch do MVP, verifica o Python, faz backup do código anterior, aplica os arquivos, atualiza dependências e reinicia o robô se ele estava ligado. **Preserva `.env`, chave do Supabase, certificado e modo do robô.** Se o serviço estava parado manualmente, continua parado.

Esse comando busca e aplica atualizações quando você o executa; não há atualização agendada em segundo plano. Alterações locais ou divergência da branch interrompem a atualização em vez de sobrescrever seu trabalho. Mudanças de banco e infraestrutura não são aplicadas automaticamente. Uma falha pode deixar o robô parado: confira a mensagem e os logs antes de reiniciar.

Se já instalou anteriormente por ZIP, use o clone do passo 2 e rode o instalador uma vez para registrar o comando de atualização. Essa reinstalação pede as informações e redefine o robô para disabled.

## 4. Primeiro acesso

Crie seu usuário no Supabase → Authentication → Users. Abra o subdomínio → Configurações → entre com esse usuário → selecione **Supabase · fila real**. A chave do worker fica em Project Settings → API Keys, tipo secret/service_role; ela é solicitada de forma oculta e salva somente na VPS.

O banco já está configurado. Não reaplique o SQL. Cada usuário vê apenas as próprias consultas.

O robô começa em **disabled**, testando a fila sem consulta bancária. A execução completa do Digi+ ainda precisa de homologação na VPS. Para testar uma consulta real autorizada:

```bash
nano /opt/apoiarcred/.env
# Altere ROBOT_MODE=disabled para ROBOT_MODE=live, salve e execute:
systemctl restart apoiarcred-robo
```

Valide uma consulta individual antes de enviar lotes. CSV: `nome;cpf;telefone`, até 1.000 linhas.

## Comandos úteis

```bash
journalctl -u apoiarcred-robo -n 50 -f
systemctl restart apoiarcred-robo
systemctl stop apoiarcred-robo
certbot renew --dry-run
```

Se uma consulta for interrompida, revise antes de reenviar: a recuperação automática de tarefas em processamento ainda não está implementada. Configure backups e retenção no Supabase. A instalação real depende do acesso SSH ao GitHub, do DNS e das portas livres na VPS.

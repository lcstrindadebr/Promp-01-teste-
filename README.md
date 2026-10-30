# ApoiarCred · Instalação do MVP

## 1. DNS

| Tipo | Nome | Valor |
|---|---|---|
| A | consultas | IP público da VPS |

Deixe as portas 80/443 livres e liberadas no provedor. Se usar Cloudflare, comece com Somente DNS.

## 2. Instalar por HTTPS

Na VPS Ubuntu Server **24.04 x86-64**, como root, execute o bloco inteiro:

```bash
git clone --branch apoiarcred-consultas-mvp --single-branch https://github.com/lcstrindadebr/Promp-01-teste-.git /opt/apoiarcred-src && bash /opt/apoiarcred-src/instalar.sh
```

O repositório está público: não precisa de chave SSH, senha do GitHub ou ZIP. Caso o comando git não exista, execute primeiro `apt update && apt install -y git`.

Se aparecer “destination path already exists”, não apague a pasta. Se ela já contém este repositório:

```bash
git -C /opt/apoiarcred-src remote set-url origin https://github.com/lcstrindadebr/Promp-01-teste-.git &&
git -C /opt/apoiarcred-src pull --ff-only origin apoiarcred-consultas-mvp &&
bash /opt/apoiarcred-src/instalar.sh
```

O instalador pergunta **subdomínio, e-mail do SSL e chave secreta do Supabase**, além da confirmação dos termos do certificado. Configura Python, Chromium, Nginx, HTTPS e serviço do robô. Sem Docker. Sugestão inicial: 2 vCPU e 4 GB RAM.

A chave secret/service_role fica no Supabase → Project Settings → API Keys. A digitação é oculta e a chave fica somente no .env da VPS. Não use a publishable no lugar dela.

## 3. Atualizar

```bash
apoiarcred-atualizar
```

Busca e aplica o código mais recente da branch, atualiza dependências e reinicia o robô se ele estava ligado. Preserva .env, modo do robô e certificado. Não há atualização agendada; execute o comando quando quiser atualizar. Não sobrescreve alterações locais nem executa migrações de banco.

Se o repositório voltar a privado, será necessário autorizar o acesso da VPS novamente.

## 4. Entrar e testar

Crie seu usuário em Supabase → Authentication → Users. Abra o subdomínio → Configurações → entre → selecione **Supabase · fila real**. O banco já está configurado; não reaplique o schema.

O robô inicia em **disabled**, testando a fila sem consulta bancária. A execução completa do Digi+ ainda precisa ser homologada na VPS. Para uma consulta real autorizada de teste:

```bash
nano /opt/apoiarcred/.env
# Troque ROBOT_MODE=disabled por ROBOT_MODE=live, salve e execute:
systemctl restart apoiarcred-robo
```

Valide uma consulta individual antes de enviar lotes. CSV: nome;cpf;telefone, até 1.000 linhas. Cada usuário vê apenas as próprias consultas.

## Comandos úteis

```bash
journalctl -u apoiarcred-robo -n 50 -f
systemctl restart apoiarcred-robo
systemctl stop apoiarcred-robo
certbot renew --dry-run
```

Se uma consulta for interrompida, revise antes de reenviar. Configure backups e retenção no Supabase. Se a instalação falhar, corrija o erro e execute novamente; uma reinstalação redefine o robô para disabled e pode interromper temporariamente o serviço.

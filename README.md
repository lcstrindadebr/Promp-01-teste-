# ApoiarCred · Instalação simples na VPS

Ubuntu 24.04, 2 vCPU e 4 GB de RAM. Instalação direta com Python e Nginx, sem Docker e sem instalar Git ou GitHub na máquina.

## 1. Registro DNS

Crie somente este registro no DNS que já administra seu domínio:

| Tipo | Nome | Valor |
|---|---|---|
| **A** | **consultas** | **IP público da VPS** |

Resultado: `consultas.apoiarcred.com.br`. Neste caso é **A, não CNAME**, porque o destino é um IP. Não coloque `https://` nem porta no valor. Mantenha os demais registros do domínio. Se usar Cloudflare, deixe Somente DNS durante a instalação do certificado.

## 2. Baixar o repositório

Abra o [repositório na branch do MVP](https://github.com/lcstrindadebr/Promp-01-teste-/tree/apoiarcred-consultas-mvp), conectado à sua conta do GitHub. Clique em **Code → Download ZIP** e renomeie o arquivo para `apoiarcred.zip`.

Como o repositório é privado, um wget sem autenticação não consegue baixar. Não precisa instalar Git: envie o ZIP para a VPS por SFTP ou, na pasta onde baixou o arquivo, execute no PowerShell:

```powershell
scp apoiarcred.zip root@IP_DA_VPS:/tmp/apoiarcred.zip
ssh root@IP_DA_VPS
```

Substitua `IP_DA_VPS` pelo IP real. Os comandos a seguir são executados no terminal da VPS como root. Se estiver conectado com outro usuário, use `sudo -i` primeiro. O guia assume uma instalação nova e portas 80/443 livres.

## 3. Instalar e extrair

```bash
apt update
apt install -y nginx python3-venv python3-pip unzip certbot python3-certbot-nginx
mkdir -p /opt/apoiarcred
unzip /tmp/apoiarcred.zip -d /tmp/apoiarcred-extraido
cp -a /tmp/apoiarcred-extraido/Promp-01-teste--apoiarcred-consultas-mvp/. /opt/apoiarcred/
cd /opt/apoiarcred
python3 -m venv .venv
.venv/bin/pip install -r vps/requirements.txt
PLAYWRIGHT_BROWSERS_PATH=/opt/apoiarcred/browsers .venv/bin/playwright install --with-deps chromium
chmod -R a+rX /opt/apoiarcred/dist /opt/apoiarcred/browsers
chmod 755 /opt/apoiarcred
```

A pasta dentro do ZIP deve conter `dist`, `vps` e `supabase`. Se o GitHub mudar o nome da pasta extraída, ajuste somente o caminho de origem no comando `cp`. A instalação do Chromium pode levar alguns minutos.

## 4. Configurar o Supabase

O banco deste projeto já foi criado e configurado. **Não execute o schema novamente.** O painel já tem a URL e a chave pública.

Crie o arquivo de configuração do robô:

```bash
nano /opt/apoiarcred/.env
```

Cole, substituindo apenas a chave:

```dotenv
SUPABASE_URL=https://yypwsxrlyvzvrbnwccmv.supabase.co
SUPABASE_SERVICE_ROLE_KEY=COLE_A_CHAVE_SECRETA_AQUI
ROBOT_MODE=disabled
```

A chave fica no dashboard do Supabase → Project Settings → API Keys: use secret ou service_role. Ela é exclusiva do servidor; não coloque no painel nem no GitHub. Salve no Nano com Ctrl+O, Enter e Ctrl+X.

```bash
chmod 600 /opt/apoiarcred/.env
```

No Supabase → Authentication → Users, crie seu usuário com e-mail e senha. Cada usuário vê somente suas próprias consultas.

## 5. Colocar o painel no subdomínio

```bash
nano /etc/nginx/sites-available/apoiarcred
```

Cole:

```nginx
server {
    listen 80;
    server_name consultas.apoiarcred.com.br;
    root /opt/apoiarcred/dist;
    index index.html;

    add_header X-Content-Type-Options nosniff always;
    add_header Cache-Control "no-store" always;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Salve e ative:

```bash
ln -s /etc/nginx/sites-available/apoiarcred /etc/nginx/sites-enabled/apoiarcred
nginx -t
systemctl enable --now nginx
systemctl reload nginx
```

Se o link já existir, não precisa recriá-lo. Só recarregue se `nginx -t` passar. O Nginx deve servir **somente a pasta dist**, nunca a pasta inteira do projeto, que contém a chave secreta.

Libere TCP **80 e 443** no firewall da VPS/provedor. Se usar UFW, permita essas portas preservando o acesso SSH. Não há porta do robô para abrir.

## 6. Ativar HTTPS

Quando o DNS estiver apontando para a VPS e `http://consultas.apoiarcred.com.br` abrir:

```bash
certbot --nginx -d consultas.apoiarcred.com.br --redirect
certbot renew --dry-run
```

Informe seu e-mail e aceite os termos se estiver de acordo. O Certbot instala o certificado e configura a renovação automática. Não entre com senha antes de o HTTPS funcionar.

Acesse: **https://consultas.apoiarcred.com.br**.

## 7. Deixar o robô funcionando ao fechar o terminal

Crie um usuário de serviço e sua configuração:

```bash
id apoiarcred >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/apoiarcred --shell /usr/sbin/nologin apoiarcred
nano /etc/systemd/system/apoiarcred-robo.service
```

Cole:

```ini
[Unit]
Description=Robo de consultas ApoiarCred
Wants=network-online.target
After=network-online.target

[Service]
User=apoiarcred
WorkingDirectory=/opt/apoiarcred/vps
EnvironmentFile=/opt/apoiarcred/.env
Environment=PLAYWRIGHT_BROWSERS_PATH=/opt/apoiarcred/browsers
ExecStart=/opt/apoiarcred/.venv/bin/python -u worker.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Salve e inicie:

```bash
systemctl daemon-reload
systemctl enable --now apoiarcred-robo
systemctl status apoiarcred-robo --no-pager
```

O serviço inicia com a VPS e continua trabalhando quando o terminal é fechado. O systemd lê o arquivo .env protegido e passa as variáveis ao processo.

## 8. Primeiro acesso e teste

1. Abra o subdomínio com HTTPS.
2. Vá em Configurações e entre com o usuário criado no Supabase.
3. Selecione **Supabase · fila real** e salve.
4. Envie um registro fictício para testar a fila. Em `disabled`, ele deve retornar **Revisão**, sem consultar o banco.

**O robô está programado, mas a execução completa no Digi+ ainda precisa ser validada na VPS.** Os testes de interpretação de respostas passaram; isso não substitui uma consulta real de homologação.

Para homologar com um cliente autorizado, edite `.env`, troque para `ROBOT_MODE=live` e reinicie:

```bash
systemctl restart apoiarcred-robo
```

Confira uma consulta individual manualmente antes de importar lotes. Documento não localizado é um resultado próprio, nunca saldo zero. Para voltar a desativar, use `ROBOT_MODE=disabled` e reinicie o serviço.

CSV aceito: `nome;cpf;telefone`, até 1.000 linhas. Preserve os zeros iniciais do CPF. O modo Demonstração é separado e não consulta o banco.

## Comandos úteis

```bash
# Ver mensagens do robô; Ctrl+C fecha só o acompanhamento
journalctl -u apoiarcred-robo -n 50 -f

# Reiniciar ou parar o robô
systemctl restart apoiarcred-robo
systemctl stop apoiarcred-robo

# Conferir Nginx
nginx -t
systemctl status nginx --no-pager
```

Se uma consulta ficar processando após uma interrupção, revise antes de reenviar: a recuperação automática dessa situação ainda não está implementada.

## Atualizar depois

Baixe o ZIP novo da mesma branch e envie à VPS como no passo 2. Extraia em uma pasta temporária nova. Pare o robô, substitua `dist` e os arquivos de `vps` pelos novos e preserve `.env`, `.venv` e `browsers`. Se mudar `requirements.txt`, repita a instalação das dependências e do Chromium do passo 3. Depois inicie com `systemctl start apoiarcred-robo`.

O banco continua no Supabase; ele não é substituído ao atualizar os arquivos. Defina backups e retenção no Supabase antes de operar com dados reais.

Referências: [Playwright](https://playwright.dev/python/docs/browsers), [Nginx](https://nginx.org/en/docs/http/ngx_http_core_module.html), [systemd](https://freedesktop.org/software/systemd/man/latest/systemd.exec.html).

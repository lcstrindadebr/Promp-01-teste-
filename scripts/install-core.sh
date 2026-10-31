#!/usr/bin/env bash
# ApoiarCred MVP — instalação direta em Ubuntu 24.04 amd64.
set -Eeuo pipefail
umask 022
APP=/opt/apoiarcred
CONF=/etc/nginx/sites-available/apoiarcred-mvp.conf
UNIT=/etc/systemd/system/apoiarcred-robo.service
SB_URL=https://yypwsxrlyvzvrbnwccmv.supabase.co
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STAGE='preparação'
WORK=''
SUCCESS=0
OLD_CONF=''
NGINX_CHANGED=0
fail() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }
cleanup() {
    local code=$?
    unset SB_KEY
    if [[ -n "$WORK" && -f "$WORK/curl-auth" ]]; then : > "$WORK/curl-auth"; fi
    if (( SUCCESS == 0 && NGINX_CHANGED == 1 )); then
        if [[ -n "$OLD_CONF" ]]; then
            cp "$OLD_CONF" "$CONF"
        else
            [[ ! -e "$CONF" ]] || mv "$CONF" "$WORK/nginx-incompleto.conf"
            [[ ! -L /etc/nginx/sites-enabled/apoiarcred-mvp.conf ]] || unlink /etc/nginx/sites-enabled/apoiarcred-mvp.conf
        fi
        nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
    fi
    if (( code != 0 )); then
        printf '\nInstalação interrompida na etapa: %s. Corrija o erro e execute novamente.\n' "$STAGE" >&2
        [[ -z "$WORK" ]] || printf 'Arquivos de diagnóstico/backups: %s\n' "$WORK" >&2
    fi
}
trap cleanup EXIT
[[ $EUID -eq 0 ]] || fail 'Execute com sudo bash instalar.sh ou como root.'
[[ -t 0 ]] || fail 'Execute o arquivo em um terminal interativo, não por pipe.'
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 24.04 ]] || fail 'Este instalador requer Ubuntu Server 24.04 LTS.'
[[ $(uname -m) == x86_64 ]] || fail 'Use VPS x86-64 (Intel/AMD).'
for file in dist/index.html dist/app.js dist/supabase.js dist/supabase-config.js vps/worker.py vps/robot.py vps/requirements.txt; do
    [[ -f "$SOURCE/$file" ]] || fail "Arquivo ausente: $file. Extraia o ZIP inteiro antes de executar."
done
exec 9>/run/lock/apoiarcred-instalar.lock
flock -n 9 || fail 'Já existe um instalador em execução.'
printf '\n=== ApoiarCred · Instalação do MVP ===\nSem Docker. Painel + Nginx + HTTPS + robô em serviço.\n\n'
read -r -p 'Subdomínio (ex.: consultas.apoiarcred.com.br): ' DOMAIN
DOMAIN=${DOMAIN,,}
[[ ${#DOMAIN} -le 253 && "$DOMAIN" != *..* && "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || fail 'Informe somente um domínio válido, sem https://, barra ou porta.'
read -r -p 'E-mail para o certificado SSL: ' SSL_EMAIL
[[ "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || fail 'E-mail inválido.'
printf '\nSupabase → Project Settings → API Keys. Use secret ou service_role.\nA chave será salva apenas em /opt/apoiarcred/.env e não aparece ao digitar.\n'
read -r -s -p 'Chave secreta do Supabase: ' SB_KEY
printf '\n'
[[ ${#SB_KEY} -ge 30 && "$SB_KEY" =~ ^[A-Za-z0-9_.=-]+$ ]] || fail 'Chave inválida.'
[[ "$SB_KEY" == sb_secret_* || "$SB_KEY" == eyJ* ]] || fail 'Informe a chave secret/service_role, não a publishable.'
printf '\nDNS necessário: tipo A | nome %s | valor IP público desta VPS.\n' "${DOMAIN%%.*}"
printf 'As portas TCP 80 e 443 devem estar liberadas no provedor.\n'
printf 'O HTTPS usa Let\x27s Encrypt: https://letsencrypt.org/repository/\n'
read -r -p 'Iniciar instalação e aceitar os termos do certificado? [s/N]: ' ANSWER
[[ "$ANSWER" =~ ^[sS]$ ]] || fail 'Instalação cancelada.'
# Não substituir o servidor web de outra aplicação.
if ss -ltnp '( sport = :80 or sport = :443 )' | tail -n +2 | grep -q .; then
    if ss -ltnp '( sport = :80 or sport = :443 )' | tail -n +2 | grep -v '"nginx"' | grep -q .; then
        fail '80/443 já estão em uso por outro serviço (ex.: Traefik/Apache). Use uma VPS livre ou libere essas portas antes.'
    fi
fi
WORK=$(mktemp -d /var/tmp/apoiarcred-install.XXXXXX)
chmod 700 "$WORK"
if [[ -e "$CONF" ]]; then
    cp "$CONF" "$WORK/nginx-anterior.conf"
    OLD_CONF="$WORK/nginx-anterior.conf"
fi
STAGE='instalação dos pacotes'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx python3-venv python3-pip certbot curl ca-certificates dnsutils
# Impedir dois virtual hosts com o mesmo nome.
while IFS= read -r existing; do
    resolved=$(readlink -f "$existing")
    [[ "$resolved" == "$CONF" ]] && continue
    if grep -E '^[[:space:]]*server_name[[:space:]]' "$existing" | grep -Fqw -- "$DOMAIN"; then
        fail "O domínio já está configurado em $existing. Não alterei esse site."
    fi
done < <(find -L /etc/nginx/sites-enabled -maxdepth 1 -type f 2>/dev/null)
STAGE='validação do Supabase'
# Nunca enviar a chave em argumento de processo ou log.
printf '%s\n' "header = \"apikey: $SB_KEY\"" "header = \"Authorization: Bearer $SB_KEY\"" > "$WORK/curl-auth"
chmod 600 "$WORK/curl-auth"
if ! curl --config "$WORK/curl-auth" --fail --silent --show-error --max-time 25 "$SB_URL/rest/v1/consulta_jobs?select=id&limit=0" > /dev/null; then
    fail 'Não foi possível acessar as tabelas deste projeto Supabase. Confira a chave e a conectividade.'
fi
# Apaga o conteúdo secreto temporário; a configuração final ficará no .env.
: > "$WORK/curl-auth"
STAGE='cópia do projeto'
if systemctl is-active --quiet apoiarcred-robo 2>/dev/null; then
    systemctl stop apoiarcred-robo
fi
install -d -m 755 "$APP" "$APP/vps" "$APP/dist"
if [[ "$SOURCE" != "$APP" ]]; then
    cp -a "$SOURCE/dist/." "$APP/dist/"
    cp -a "$SOURCE/vps/." "$APP/vps/"
fi
chmod -R a+rX "$APP/dist" "$APP/vps"
if [[ -f "$APP/.env" ]]; then
    cp "$APP/.env" "$WORK/env-anterior"
    chmod 600 "$WORK/env-anterior"
fi
(umask 077; printf 'SUPABASE_URL=%s\nSUPABASE_SERVICE_ROLE_KEY=%s\nROBOT_MODE=disabled\n' "$SB_URL" "$SB_KEY" > "$APP/.env")
chmod 600 "$APP/.env"
unset SB_KEY
# Configuração pública persistente, preservada pelo atualizador.
python3 "$SOURCE/scripts/configure_supabase.py" --app "$APP" --capture-public
STAGE='Python e Chromium (pode levar alguns minutos)' 
python3 -m venv "$APP/.venv"
"$APP/.venv/bin/pip" install -r "$APP/vps/requirements.txt"
PLAYWRIGHT_BROWSERS_PATH="$APP/browsers" "$APP/.venv/bin/playwright" install --with-deps chromium
chmod -R a+rX "$APP/browsers"
id apoiarcred >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/apoiarcred --shell /usr/sbin/nologin apoiarcred
STAGE='Nginx e verificação do DNS'
install -d -m 755 /var/www/apoiarcred-acme/.well-known/acme-challenge
write_http() {
    cat > "$CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /opt/apoiarcred/dist;
    index index.html;
    location /.well-known/acme-challenge/ { root /var/www/apoiarcred-acme; }
    location / { try_files \$uri \$uri/ =404; }
}
EOF
}
NGINX_CHANGED=1
write_http
ln -sfn "$CONF" /etc/nginx/sites-enabled/apoiarcred-mvp.conf
nginx -t
# UFW: abre só web se já estiver ativo; não habilita nem altera SSH.
if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
    ufw allow 80/tcp
    ufw allow 443/tcp
fi
systemctl enable --now nginx
systemctl reload nginx
MARKER="apoiarcred-$(date +%s)-$RANDOM"
printf '%s' "$MARKER" > /var/www/apoiarcred-acme/.well-known/acme-challenge/apoiarcred-check
RESPONSE=$(curl -fsS --max-time 20 "http://$DOMAIN/.well-known/acme-challenge/apoiarcred-check") || fail 'O subdomínio não alcançou esta VPS por HTTP. Confira registro A, AAAA e firewall, depois execute novamente.'
[[ "$RESPONSE" == "$MARKER" ]] || fail 'O subdomínio está respondendo por outro servidor. Corrija o DNS e execute novamente.'
STAGE='emissão do certificado HTTPS'
certbot certonly --webroot -w /var/www/apoiarcred-acme --cert-name "$DOMAIN" -d "$DOMAIN" --email "$SSL_EMAIL" --agree-tos --non-interactive --keep-until-expiring
cat > "$CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/apoiarcred-acme; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /opt/apoiarcred/dist;
    index index.html;
    server_tokens off;
    add_header X-Content-Type-Options nosniff always;
    add_header Cache-Control "no-store" always;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
nginx -t
systemctl reload nginx
install -d /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/apoiarcred-nginx <<'EOF'
#!/bin/sh
/usr/sbin/nginx -t && /bin/systemctl reload nginx
EOF
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/apoiarcred-nginx
systemctl enable --now certbot.timer
STAGE='instalação do serviço do robô'
[[ ! -f "$UNIT" ]] || cp "$UNIT" "$WORK/servico-anterior"
cat > "$UNIT" <<'EOF'
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
EOF
systemctl daemon-reload
systemctl enable apoiarcred-robo
systemctl restart apoiarcred-robo
systemctl is-active --quiet apoiarcred-robo
curl --fail --silent --show-error --max-time 20 "https://$DOMAIN/" > /dev/null
if [[ "$SOURCE" == /opt/apoiarcred-src && -f "$SOURCE/atualizar.sh" ]]; then
    cat > /usr/local/bin/apoiarcred-atualizar <<'EOF'
#!/bin/sh
exec /bin/bash /opt/apoiarcred-src/atualizar.sh "$@"
EOF
    chmod 755 /usr/local/bin/apoiarcred-atualizar
fi
SUCCESS=1
printf '\nInstalação concluída: https://%s\n' "$DOMAIN"
printf 'Entre em Configurações com um usuário do Supabase Auth e selecione Supabase · fila real.\n'
printf 'Robô em modo disabled: testa a fila sem consultar o banco. Homologue antes de ativar live.\n'
printf 'Logs: journalctl -u apoiarcred-robo -n 50 -f\n'
printf 'Backups de instalação: %s (acesso restrito a root).\n' "$WORK"


#!/usr/bin/env bash
set -Eeuo pipefail
APP=/opt/apoiarcred
REPO=/opt/apoiarcred-src
STAGE=preparação
trap 'printf "\nAtualização interrompida: %s. Confira o erro antes de reiniciar o robô.\n" "$STAGE" >&2' ERR
[[ $EUID -eq 0 ]] || { echo 'Execute como root.'; exit 1; }
# O launcher mantém a trava 9 durante todo o download e aplicação.
if ! { true >&9; } 2>/dev/null; then
    exec 9>/run/lock/apoiarcred-instalar.lock
fi
flock -n 9 || { echo 'Outra operação está em andamento.'; exit 1; }
cd "$REPO"
CHECK_ATTEMPTS=${APOIARCRED_CHECK_ATTEMPTS:-6}
CHECK_WAIT=${APOIARCRED_CHECK_WAIT:-20}

# Validar antes de parar qualquer serviço.
python3 - <<'PY'
import ast
from pathlib import Path
for p in sorted(Path('vps').glob('*.py')):
 ast.parse(p.read_text())
assert Path('dist/index.html').is_file()
PY
# Capturar a configuração da instalação antiga antes de copiar o frontend novo.
if [[ ! -f "$APP/supabase-public.json" ]]; then
    python3 "$REPO/scripts/configure_supabase.py" --app "$APP" --capture-public
fi

# 1. Banco: espera curta quando a falha é temporária (código 75), em vez de desistir na primeira.
STAGE='validação do banco'
CHECK_STATUS=0
for attempt in $(seq 1 "$CHECK_ATTEMPTS"); do
    if python3 "$REPO/scripts/configure_supabase.py" --app "$APP" --check-runtime; then
        CHECK_STATUS=0; break
    else
        CHECK_STATUS=$?
    fi
    [[ "$CHECK_STATUS" -eq 75 ]] || break
    if (( attempt < CHECK_ATTEMPTS )); then
        printf 'Supabase lento ou indisponível (tentativa %s de %s). Nova verificação em %ss...\n' "$attempt" "$CHECK_ATTEMPTS" "$CHECK_WAIT"
        sleep "$CHECK_WAIT"
    fi
done
if [[ "$CHECK_STATUS" -ne 0 ]]; then
    if [[ "$CHECK_STATUS" -ne 75 ]]; then
        echo 'Atualização bloqueada por configuração, permissões ou schema inválido.'
        exit "$CHECK_STATUS"
    fi
    # Sem banco não é possível devolver consultas à fila, então os robôs não são tocados.
    STAGE='publicação do painel durante indisponibilidade do banco'
    echo 'Supabase continua indisponível. Publicando somente painel e backend HTTP; robôs seguem como estão.'
    bash "$REPO/scripts/update-auth.sh"
    printf '\nATUALIZAÇÃO PARCIAL CONCLUÍDA: painel e backend HTTP.\n'
    echo 'Robôs NÃO foram atualizados. Repita a opção 1 quando o banco voltar a responder.'
    exit 0
fi

# 2. Parar robôs e devolver consultas em andamento (até 3 tentativas: a devolução usa o banco).
STAGE='interrupção e devolução das consultas à fila'
for attempt in 1 2 3; do
    if python3 "$REPO/scripts/stop-consultas.py" --app "$APP"; then break; fi
    if (( attempt == 3 )); then
        echo 'Robôs e API ficaram PARADOS porque a devolução à fila não foi confirmada.'
        echo 'Quando o banco responder, repita a opção 1 (ou a opção 6 e depois: systemctl start apoiarcred-robo apoiarcred-api).'
        exit 1
    fi
    echo 'Nova tentativa de devolver as consultas em 15 s...'
    sleep 15
done

# 3. Aplicar código. Qualquer falha daqui em diante restaura a versão anterior e religa os serviços.
STAGE='aplicação da atualização'
BACKUP=$(mktemp -d /var/tmp/apoiarcred-update.XXXXXX)
chmod 700 "$BACKUP"
cp -a "$APP/dist" "$APP/vps" "$BACKUP/"
printf 'Backup do código anterior: %s\n' "$BACKUP"
rollback() {
    local status=$?
    trap - ERR
    printf '\nFalha em: %s. Restaurando a versão anterior...\n' "$STAGE" >&2
    rm -rf "$APP/dist" "$APP/vps"
    cp -a "$BACKUP/dist" "$BACKUP/vps" "$APP/"
    systemctl daemon-reload || true
    python3 "$REPO/scripts/drain_queue.py" --app "$APP" --release || true
    systemctl restart apoiarcred-api apoiarcred-monitor apoiarcred-webhooks || true
    systemctl start apoiarcred-robo || true
    printf 'Versão anterior restaurada e serviços religados. Backup mantido em %s\n' "$BACKUP" >&2
    exit "$status"
}
trap rollback ERR
# O supabase-config.js do repositório não é o desta instalação: é gerado por --render-only.
tar -C dist --exclude=./supabase-config.js -cf - . | tar -C "$APP/dist" -xf -
cp -a vps/. "$APP/vps/"
python3 "$REPO/scripts/configure_supabase.py" --app "$APP" --render-only
chmod -R a+rX "$APP/dist" "$APP/vps"
STAGE='dependências Python'
"$APP/.venv/bin/pip" install -r "$APP/vps/requirements.txt"
STAGE='navegador dos robôs'
PLAYWRIGHT_BROWSERS_PATH="$APP/browsers" "$APP/.venv/bin/playwright" install --with-deps chromium
chmod -R a+rX "$APP/browsers"
STAGE='atualização dos serviços'
install -m 644 "$REPO/deploy/apoiarcred-robo.service" /etc/systemd/system/apoiarcred-robo.service
install -m 644 "$REPO/deploy/apoiarcred-monitor.service" /etc/systemd/system/apoiarcred-monitor.service
install -m 644 "$REPO/deploy/apoiarcred-api.service" /etc/systemd/system/apoiarcred-api.service
install -m 644 "$REPO/deploy/apoiarcred-webhooks.service" /etc/systemd/system/apoiarcred-webhooks.service
install -d -m 755 /etc/nginx/snippets /etc/nginx/conf.d
install -m 644 "$REPO/deploy/apoiarcred-api.nginx" /etc/nginx/snippets/apoiarcred-api.conf
install -m 644 "$REPO/deploy/apoiarcred-api-rate.nginx" /etc/nginx/conf.d/apoiarcred-api-rate.conf
python3 "$REPO/scripts/configure_api.py" --app "$APP"
systemctl daemon-reload
systemctl enable apoiarcred-webhooks apoiarcred-api apoiarcred-monitor
systemctl restart apoiarcred-webhooks
systemctl restart apoiarcred-monitor
systemctl is-active --quiet apoiarcred-webhooks
systemctl is-active --quiet apoiarcred-monitor
nginx -t
systemctl reload nginx
STAGE='retomada das consultas'
python3 "$REPO/scripts/drain_queue.py" --app "$APP" --release
systemctl start apoiarcred-robo apoiarcred-api
sleep 3
systemctl is-active --quiet apoiarcred-robo
systemctl is-active --quiet apoiarcred-api
trap - ERR
printf '\nAtualizado para o commit %s. .env, modo do robô e SSL preservados.\n' "$(git rev-parse --short HEAD)"
printf 'Atualizados: painel, robôs, API, monitor, webhooks e dependências.\n'
printf 'Abra a Central com Ctrl+F5 para carregar a versão nova.\n'

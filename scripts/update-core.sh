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
# Validar antes de parar o serviço.
python3 - <<'PY'
import ast
from pathlib import Path
for p in [Path('vps/worker.py'),Path('vps/robot.py')]:
 ast.parse(p.read_text())
assert Path('dist/index.html').is_file()
PY
# Capturar a configuração da instalação antiga antes de copiar o frontend novo.
if [[ ! -f "$APP/supabase-public.json" ]]; then
    python3 "$REPO/scripts/configure_supabase.py" --app "$APP" --capture-public
fi
STAGE='validação do banco'
python3 "$REPO/scripts/configure_supabase.py" --app "$APP" --check-runtime
STAGE='aplicação da atualização'  
BACKUP=$(mktemp -d /var/tmp/apoiarcred-update.XXXXXX)
chmod 700 "$BACKUP"
cp -a "$APP/dist" "$APP/vps" "$BACKUP/"
printf 'Backup do código anterior: %s\n' "$BACKUP"
WAS_ACTIVE=0
if systemctl is-active --quiet apoiarcred-robo; then
    WAS_ACTIVE=1
    systemctl stop apoiarcred-robo
fi
cp -a dist/. "$APP/dist/"
cp -a vps/. "$APP/vps/"
python3 "$REPO/scripts/configure_supabase.py" --app "$APP" --render-only
chmod -R a+rX "$APP/dist" "$APP/vps"
"$APP/.venv/bin/pip" install -r "$APP/vps/requirements.txt"
PLAYWRIGHT_BROWSERS_PATH="$APP/browsers" "$APP/.venv/bin/playwright" install --with-deps chromium
chmod -R a+rX "$APP/browsers"
STAGE='atualização do serviço'
install -m 644 "$REPO/deploy/apoiarcred-robo.service" /etc/systemd/system/apoiarcred-robo.service
systemctl daemon-reload
nginx -t
# Não ligar um worker que estava parado manualmente.
if (( WAS_ACTIVE )); then
    systemctl start apoiarcred-robo
    systemctl is-active --quiet apoiarcred-robo
fi
printf '\nAtualizado para o commit %s. .env, modo do robô e SSL preservados.\n' "$(git rev-parse --short HEAD)"
printf 'Atualizados: painel, robô, dependências e serviço. Menu e scripts vêm do mesmo repositório.\n'


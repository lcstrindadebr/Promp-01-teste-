#!/usr/bin/env bash
# Atualização sob demanda; sem ZIP, sem alterar .env ou certificados.
set -Eeuo pipefail
APP=/opt/apoiarcred
REPO=/opt/apoiarcred-src
BRANCH=apoiarcred-consultas-mvp
STAGE=preparação
trap 'printf "\nAtualização interrompida: %s. Confira o erro antes de reiniciar o robô.\n" "$STAGE" >&2' ERR
[[ $EUID -eq 0 ]] || { echo 'Execute como root ou com sudo.'; exit 1; }
exec 9>/run/lock/apoiarcred-instalar.lock
flock -n 9 || { echo 'Instalação ou atualização já em andamento.'; exit 1; }
[[ -d "$REPO/.git" && -f "$APP/.env" && -x "$APP/.venv/bin/python" ]] || { echo 'Faça primeiro a instalação pelo comando do README.'; exit 1; }
cd "$REPO"
[[ $(git branch --show-current) == "$BRANCH" ]] || { echo 'Branch diferente da esperada; não alterei o checkout.'; exit 1; }
[[ $(git remote get-url origin) == 'git@github.com:lcstrindadebr/Promp-01-teste-.git' ]] || { echo 'O remoto não é o repositório esperado.'; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo 'Há mudanças locais no código. Revise-as antes de atualizar.'; exit 1; }
STAGE='download do GitHub'
git pull --ff-only origin "$BRANCH"
# Validar antes de parar o serviço.
python3 - <<'PY'
import ast
from pathlib import Path
for p in [Path('vps/worker.py'),Path('vps/robot.py')]:
 ast.parse(p.read_text())
assert Path('dist/index.html').is_file()
PY
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
chmod -R a+rX "$APP/dist" "$APP/vps"
"$APP/.venv/bin/pip" install -r "$APP/vps/requirements.txt"
PLAYWRIGHT_BROWSERS_PATH="$APP/browsers" "$APP/.venv/bin/playwright" install --with-deps chromium
chmod -R a+rX "$APP/browsers"
nginx -t
# Não ligar um worker que estava parado manualmente.
if (( WAS_ACTIVE )); then
    systemctl start apoiarcred-robo
    systemctl is-active --quiet apoiarcred-robo
fi
printf '\nAtualizado para o commit %s. .env, modo do robô e SSL preservados.\n' "$(git rev-parse --short HEAD)"
printf 'Migrações de banco e mudanças de infraestrutura não são executadas automaticamente.\n'

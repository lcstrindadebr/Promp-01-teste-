#!/usr/bin/env bash
set -Eeuo pipefail
APP=/opt/apoiarcred
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $EUID -eq 0 ]] || { echo 'Execute como root.'; exit 1; }
if ! { true >&9; } 2>/dev/null; then exec 9>/run/lock/apoiarcred-instalar.lock; fi
flock -n 9 || { echo 'Outra atualização em andamento.'; exit 1; }
[[ -f "$APP/supabase-public.json" ]] || python3 "$REPO/scripts/configure_supabase.py" --app "$APP" --capture-public
python3 - "$REPO" <<'PY'
import ast, sys
from pathlib import Path
root=Path(sys.argv[1])
for name in ('vps/api.py','vps/auth_session.py'):
    ast.parse((root/name).read_text())
PY
nginx -t
BACKUP=$(mktemp -d /var/tmp/apoiarcred-auth.XXXXXX)
# Painel completo (HTML, JS, CSS, modelos) para que index.html nunca fique com arquivos de versões diferentes.
# supabase-config.js fica de fora: é o da instalação, não o do repositório.
mapfile -t PANEL < <(cd "$REPO" && find dist -type f ! -path dist/supabase-config.js | sort)
FILES=(vps/auth_session.py vps/api.py "${PANEL[@]}")
for file in "${FILES[@]}"; do
    mkdir -p "$BACKUP/$(dirname "$file")"
    if [[ -f "$APP/$file" ]]; then cp -a "$APP/$file" "$BACKUP/$file"; fi
done
WAS_ACTIVE=0
if systemctl is-active --quiet apoiarcred-api; then WAS_ACTIVE=1; fi
rollback() {
    trap - ERR
    for file in "${FILES[@]}"; do
        if [[ -f "$BACKUP/$file" ]]; then cp -a "$BACKUP/$file" "$APP/$file"; fi
    done
    if (( WAS_ACTIVE )); then systemctl restart apoiarcred-api; else systemctl stop apoiarcred-api; fi
    echo "Falha na publicação. Código anterior restaurado. Backup: $BACKUP"
    exit 1
}
trap rollback ERR
# Backend first. The previous frontend remains usable during this short restart.
for file in vps/auth_session.py vps/api.py; do
    install -m 644 "$REPO/$file" "$APP/$file.new"
    mv -f "$APP/$file.new" "$APP/$file"
done
systemctl restart apoiarcred-api
"$APP/.venv/bin/python" - <<'PY'
import json,time,urllib.request
for attempt in range(15):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8877/api/health',timeout=2) as response:
            assert json.load(response).get('session_gateway') is True
        break
    except Exception:
        if attempt==14:
            raise
        time.sleep(1)
PY
# index.html por último: quando ele mudar, os arquivos que referencia já estão no lugar.
for file in "${PANEL[@]}"; do
    [[ "$file" == dist/index.html ]] && continue
    install -D -m 644 "$REPO/$file" "$APP/$file.new"
    mv -f "$APP/$file.new" "$APP/$file"
done
install -m 644 "$REPO/dist/index.html" "$APP/dist/index.html.new"
mv -f "$APP/dist/index.html.new" "$APP/dist/index.html"
trap - ERR
printf '\nPainel (%s arquivos) e backend HTTP publicados. Backend verificado. Backup: %s\n' "${#PANEL[@]}" "$BACKUP"
echo 'Robôs não foram alterados. Abra a Central com Ctrl+F5.'

#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
APP=/opt/apoiarcred
[[ $EUID -eq 0 ]] || { echo 'Execute como root ou com sudo.'; exit 1; }
[[ -t 0 ]] || { echo 'Abra um terminal interativo para usar o menu.'; exit 1; }
EXISTING=0
if [[ -f "$APP/.env" && -f "$APP/vps/worker.py" && -x "$APP/.venv/bin/python" ]]; then EXISTING=1; fi
printf '\033[1;32m\n╔══════════════════════════════════════════╗\n║       APOIARCRED · INSTALADOR MVP        ║\n╚══════════════════════════════════════════╝\033[0m\n'
if (( EXISTING )); then
    printf '\nInstância encontrada: %s\n\n  1) Atualizar pelo GitHub\n  2) Trocar conexão/API do Supabase\n  3) Diagnosticar robô Digi+ (sem consulta de CPF)\n  4) Diagnosticar ambiente TJBA (sem login e sem CPF)\n  5) Configurar ou remover proxy TJBA\n  6) Interromper imediatamente e devolver consultas à fila\n  7) Aplicar somente a atualização de login\n  0) Sair\n\n' "$APP"
else
    printf '\nNenhuma instância completa encontrada.\n\n  1) Instalar nova instância\n  0) Sair\n\n'
fi
read -r -p 'Escolha uma opção: ' OPTION
case "$OPTION" in
    0) exit 0 ;;
    1)
        if (( EXISTING )); then exec bash "$SOURCE/atualizar.sh"; fi
        exec bash "$SOURCE/scripts/install-core.sh"
        ;;
    2)
        (( EXISTING )) || { echo 'Instale o sistema primeiro.'; exit 1; }
        exec 9>/run/lock/apoiarcred-instalar.lock
        flock -n 9 || { echo 'Outra operação está em andamento.'; exit 1; }
        printf '\nA troca não transfere dados nem usuários. O projeto de destino precisa do schema do MVP.\n'
        python3 "$SOURCE/scripts/configure_supabase.py" --app "$APP" --show-current
        read -r -p 'Continuar com a troca? [s/N]: ' CONFIRM
        [[ "$CONFIRM" =~ ^[sS]$ ]] || exit 0
        CURRENT_URL=$(python3 "$SOURCE/scripts/configure_supabase.py" --app "$APP" --show-url)
        read -r -p "URL do Supabase [$CURRENT_URL]: " SB_URL
        SB_URL=${SB_URL:-$CURRENT_URL}
        read -r -s -p 'Chave publishable (ou anon) do painel: ' PUBLIC_KEY; printf '\n'
        read -r -s -p 'Chave secret/service_role do robô: ' SECRET_KEY; printf '\n'
        ACTIVE_SERVICES=()
        for service in apoiarcred-robo apoiarcred-api apoiarcred-webhooks apoiarcred-monitor; do
            if systemctl is-active --quiet "$service"; then ACTIVE_SERVICES+=("$service"); fi
        done
        restore_services() {
            local result=$?
            trap - EXIT
            unset PUBLIC_KEY SECRET_KEY
            for service in "${ACTIVE_SERVICES[@]}"; do
                systemctl start "$service" || result=1
            done
            exit "$result"
        }
        trap restore_services EXIT
        for service in "${ACTIVE_SERVICES[@]}"; do systemctl stop "$service"; done
        if printf '%s\n%s\n%s\n' "$SB_URL" "$PUBLIC_KEY" "$SECRET_KEY" | python3 "$SOURCE/scripts/configure_supabase.py" --app "$APP"; then
            unset PUBLIC_KEY SECRET_KEY
            python3 "$SOURCE/scripts/configure_supabase.py" --app "$APP" --check-runtime
            for service in "${ACTIVE_SERVICES[@]}"; do
                systemctl start "$service"
                systemctl is-active --quiet "$service"
                printf 'Serviço atualizado: %s\n' "$service"
            done
            python3 "$SOURCE/scripts/configure_supabase.py" --app "$APP" --check-services
            trap - EXIT
            printf '\nConexão aplicada ao painel, API, robôs, monitor e webhooks: %s\n' "$SB_URL"
            printf 'Serviços anteriormente parados permanecem parados e usarão a nova configuração ao iniciar.\n'
            printf 'Recarregue o navegador e entre novamente.\n'
        else
            echo 'A configuração não foi aplicada. Confira as informações e tente novamente.'; exit 1
        fi
        ;;
    3)
        (( EXISTING )) || { echo 'Instale o sistema primeiro.'; exit 1; }
        [[ -f "$APP/vps/diagnose.py" ]] || { echo 'Atualize pela opção 1 para instalar o diagnóstico.'; exit 1; }
        systemd-run --quiet --wait --pipe --collect --uid=apoiarcred --property=WorkingDirectory="$APP/vps" --setenv=PLAYWRIGHT_BROWSERS_PATH="$APP/browsers" "$APP/.venv/bin/python" -u "$APP/vps/diagnose.py"
        ;;
    4)
        (( EXISTING )) || { echo 'Instale o sistema primeiro.'; exit 1; }
        [[ -f "$APP/vps/diagnose_tjba.py" ]] || { echo 'Atualize pela opção 1 para instalar o diagnóstico TJBA.'; exit 1; }
        systemd-run --quiet --wait --pipe --collect --uid=apoiarcred --property=WorkingDirectory="$APP/vps" --setenv=PLAYWRIGHT_BROWSERS_PATH="$APP/browsers" "$APP/.venv/bin/python" -u "$APP/vps/diagnose_tjba.py"
        ;;
    5)
        (( EXISTING )) || { echo 'Instale o sistema primeiro.'; exit 1; }
        [[ -f "$APP/vps/tjba_proxy.py" ]] || { echo 'Atualize pela opção 1 primeiro.'; exit 1; }
        exec 9>/run/lock/apoiarcred-instalar.lock
        flock -n 9 || { echo 'Outra operação está em andamento.'; exit 1; }
        "$APP/.venv/bin/python" "$APP/vps/tjba_proxy.py"
        if systemctl is-active --quiet apoiarcred-robo; then systemctl restart apoiarcred-robo; fi
        echo 'Configuração aplicada. Execute a opção 4 para validar o formulário pelo proxy.'
        ;;
    6)
        (( EXISTING )) || { echo 'Instale o sistema primeiro.'; exit 1; }
        exec 9>/run/lock/apoiarcred-instalar.lock
        flock -n 9 || { echo 'Outra operação está em andamento.'; exit 1; }
        exec python3 "$SOURCE/scripts/stop-consultas.py" --app "$APP"
        ;;
    7)
        (( EXISTING )) || { echo 'Instale o sistema primeiro.'; exit 1; }
        exec 9>/run/lock/apoiarcred-instalar.lock
        flock -n 9 || { echo 'Outra operação está em andamento.'; exit 1; }
        [[ $(git -C "$SOURCE" branch --show-current) == apoiarcred-consultas-mvp ]] ||
            { echo 'Use o checkout da branch apoiarcred-consultas-mvp.'; exit 1; }

        TARGET="$APP/dist/supabase.js"
        [[ -f "$TARGET" && ! -L "$TARGET" ]] ||
            { echo 'Arquivo de login da instalação não encontrado.'; exit 1; }
        TEMP=$(mktemp "$APP/dist/.supabase-js.XXXXXX")
        trap 'rm -f -- "$TEMP"' EXIT
        git -C "$SOURCE" show HEAD:dist/supabase.js > "$TEMP"
        [[ -s "$TEMP" ]] || { echo 'O Git não entregou o arquivo de login.'; exit 1; }
        if cmp -s "$TEMP" "$TARGET"; then
            echo 'A atualização de login já está aplicada.'
            exit 0
        fi
        BACKUP=$(mktemp -d /var/tmp/apoiarcred-login.XXXXXX)
        cp -a -- "$TARGET" "$BACKUP/"
        chown --reference="$TARGET" "$TEMP"
        chmod --reference="$TARGET" "$TEMP"
        mv -T -- "$TEMP" "$TARGET"
        printf 'Login atualizado para o commit %s. Backup: %s\n' "$(git -C "$SOURCE" rev-parse --short HEAD)" "$BACKUP"
        echo 'Robô e API continuam em execução se já estavam ativos. Recarregue a Central com Ctrl+F5.'
        ;;
    *) echo 'Opção inválida.'; exit 1 ;;
esac

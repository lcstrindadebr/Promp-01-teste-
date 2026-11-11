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
case "$(git remote get-url origin)" in
    git@github.com:lcstrindadebr/Promp-01-teste-.git|https://github.com/lcstrindadebr/Promp-01-teste-.git) ;;
    *) echo 'O remoto não é o repositório esperado.'; exit 1 ;;
esac
[[ -z $(git status --porcelain) ]] || { echo 'Há mudanças locais no código. Revise-as antes de atualizar.'; exit 1; }
STAGE='download do GitHub'
git pull --ff-only origin "$BRANCH"
# Executar a lógica NOVA recebida do GitHub, não o script antigo já carregado.
exec bash "$REPO/scripts/update-core.sh"

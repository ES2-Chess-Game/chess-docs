#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ ${SSH_ORIGINAL_COMMAND:-} != deploy-prd ]]; then
    echo "A chave de produção aceita somente deploy-prd." >&2
    exit 1
fi

base="$HOME/chess-deploy/prod"
install -d "$base/src"
exec 8>"$base/.actions.lock"
flock -w 600 8

buscar_prd() {
    local repo=$1 clone="$base/src/$1"
    if [[ ! -d "$clone/.git" ]]; then
        git clone --no-checkout --branch prd --single-branch \
            "https://github.com/ES2-Chess-Game/$repo.git" "$clone"
    fi
    git -C "$clone" fetch origin refs/heads/prd:refs/remotes/origin/prd
    git -C "$clone" rev-parse origin/prd
}

backend=$(buscar_prd chess-backend)
frontend=$(buscar_prd chess-frontend)
# As duas partes da versão jogável precisam ter sido aprovadas em prd.
while read -r repo commit; do
    if ! git -C "$base/src/$repo" merge-base --is-ancestor "$commit" origin/prd 2>/dev/null; then
        printf 'Aguardando a promoção de %s para prd.\n' "$repo"
        exit 0
    fi
done < "$HOME/chess-deploy/config/prd-minimo.txt"

expected=$(printf 'backend=%s\nfrontend=%s\n' "$backend" "$frontend")
if [[ -r "$base/current/commits.txt" && $(cat "$base/current/commits.txt") == "$expected" ]] &&
    curl --fail --silent --max-time 5 http://127.0.0.1:28080/api/avatares >/dev/null; then
    printf 'Produção já está atualizada.\n%s\n' "$expected"
    exit 0
fi

test -s "$base/backend.env"
export CHESS_DEPLOY_TARGET=prd
exec bash "$HOME/chess-deploy/config/publicar-hml.sh" "$backend" "$frontend"

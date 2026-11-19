#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ ${SSH_ORIGINAL_COMMAND:-} != deploy-hml ]]; then
    echo "A chave de deploy aceita somente deploy-hml." >&2
    exit 1
fi

base="$HOME/chess-deploy"
exec 8>"$base/.actions.lock"
flock -w 600 8

branch_hml() {
    git ls-remote --exit-code "https://github.com/ES2-Chess-Game/$1.git" refs/heads/hml | cut -f1
}

backend=$(branch_hml chess-backend)
frontend=$(branch_hml chess-frontend)
expected=$(printf 'backend=%s\nfrontend=%s\n' "$backend" "$frontend")
if [[ -r "$base/current/commits.txt" && $(cat "$base/current/commits.txt") == "$expected" ]] &&
    curl --fail --silent --max-time 5 http://127.0.0.1:18080/api/avatares >/dev/null; then
    printf 'Homologação já está atualizada.\n%s\n' "$expected"
    exit 0
fi

exec bash "$base/config/publicar-hml.sh" "$backend" "$frontend"

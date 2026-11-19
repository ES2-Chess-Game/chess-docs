#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $# != 2 || ! $1 =~ ^[0-9a-f]{40}$ || ! $2 =~ ^[0-9a-f]{40}$ ]]; then
    echo "Uso: $0 <commit hml do backend> <commit hml do frontend>" >&2
    exit 2
fi

backend_commit=$1
frontend_commit=$2
base="$HOME/chess-deploy"
config=$(cd -- "$(dirname -- "$0")" && pwd)
export JAVA_HOME="$base/runtime/java25"
export PATH="$JAVA_HOME/bin:$base/runtime/node24/bin:$PATH"

install -d "$base"/{src,releases,tmp} "$HOME/.config/systemd/user"
exec 9>"$base/.deploy.lock"
flock -n 9

build=$(mktemp -d "$base/tmp/build.XXXXXX")
trap 'rm -rf -- "$build"' EXIT

exportar() {
    local repo=$1 commit=$2 destino=$3
    local clone="$base/src/$repo"
    if [[ ! -d "$clone/.git" ]]; then
        git clone --no-checkout --branch hml --single-branch \
            "https://github.com/ES2-Chess-Game/$repo.git" "$clone"
    fi
    git -C "$clone" fetch origin refs/heads/hml:refs/remotes/origin/hml
    git -C "$clone" merge-base --is-ancestor "$commit" origin/hml
    mkdir "$destino"
    git -C "$clone" archive "$commit" | tar -xf - -C "$destino"
}

exportar chess-backend "$backend_commit" "$build/backend"
exportar chess-frontend "$frontend_commit" "$build/frontend"
(
    cd "$build/backend"
    bash gradlew --no-daemon bootJar
)
(
    cd "$build/frontend"
    # A versão atual de hml aponta para o backend na máquina do desenvolvedor.
    python3 - <<'PY'
from pathlib import Path

file = Path("src/pages/Game.tsx")
source = file.read_bytes()
old = b"'http://localhost:8080/api/partidas'"
new = b"'/api/partidas'"
if source.count(old) == 1:
    file.write_bytes(source.replace(old, new))
elif source.count(new) != 1:
    raise SystemExit("Confira o endereço da API antes de publicar este commit.")
PY
    npm ci
    npm run build
)

release=$(mktemp -d "$base/releases/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
install -m 600 "$build/backend"/build/libs/*.jar "$release/chess-backend.jar"
mv "$build/frontend/dist" "$release/web"
printf 'backend=%s\nfrontend=%s\n' "$backend_commit" "$frontend_commit" > "$release/commits.txt"

install -m 600 "$config/nginx.conf" "$base/nginx.conf"
install -m 600 "$config"/chess-{web,backend}.service "$HOME/.config/systemd/user/"
nginx -e stderr -t -p "$base/" -c nginx.conf
systemctl --user daemon-reload
systemctl --user enable chess-backend.service chess-web.service

ativar() {
    ln -sfn -- "$1" "$base/.current.next"
    mv -Tf -- "$base/.current.next" "$base/current"
}

anterior=$(readlink "$base/current" || :)
ativar "$release"
if systemctl --user restart chess-backend.service chess-web.service &&
    curl --fail --silent --show-error --retry 20 --retry-all-errors \
        --retry-delay 2 --max-time 3 http://127.0.0.1:18080/api/avatares >/dev/null; then
    printf 'Versão ativa em %s\n' "$release"
    exit 0
fi

if [[ -n "$anterior" ]]; then
    ativar "$anterior"
    systemctl --user restart chess-backend.service chess-web.service
else
    systemctl --user stop chess-web.service chess-backend.service
    rm -- "$base/current"
fi
echo "A nova versão não respondeu pela API. Confira o journal dos serviços." >&2
exit 1

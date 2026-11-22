#!/usr/bin/env bash
set -euo pipefail
umask 077

case ${CHESS_DEPLOY_TARGET:-hml} in
    hml)
        branch=hml
        base="$HOME/chess-deploy"
        web_service=chess-web
        backend_service=chess-backend
        nginx_config=nginx.conf
        web_port=18080
        ;;
    prd)
        branch=prd
        base="$HOME/chess-deploy/prod"
        web_service=chess-prd-web
        backend_service=chess-prd-backend
        nginx_config=nginx-prd.conf
        web_port=28080
        ;;
    *) echo "Ambiente inválido." >&2; exit 2 ;;
esac

if [[ $# != 2 || ! $1 =~ ^[0-9a-f]{40}$ || ! $2 =~ ^[0-9a-f]{40}$ ]]; then
    echo "Uso: $0 <commit $branch do backend> <commit $branch do frontend>" >&2
    exit 2
fi

backend_commit=$1
frontend_commit=$2
runtime="$HOME/chess-deploy/runtime"
config=$(cd -- "$(dirname -- "$0")" && pwd)
export JAVA_HOME="$runtime/java25"
export PATH="$JAVA_HOME/bin:$runtime/node24/bin:$PATH"

install -d "$base"/{src,releases,tmp} "$HOME/.config/systemd/user"
exec 9>"$base/.deploy.lock"
flock -n 9

build=$(mktemp -d "$base/tmp/build.XXXXXX")
trap 'rm -rf -- "$build"' EXIT

exportar() {
    local repo=$1 commit=$2 destino=$3
    local clone="$base/src/$repo"
    if [[ ! -d "$clone/.git" ]]; then
        git clone --no-checkout --branch "$branch" --single-branch \
            "https://github.com/ES2-Chess-Game/$repo.git" "$clone"
    fi
    git -C "$clone" fetch origin "refs/heads/$branch:refs/remotes/origin/$branch"
    git -C "$clone" merge-base --is-ancestor "$commit" "origin/$branch"
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
    # Versões anteriores usavam localhost; as atuais chamam a API pela mesma origem.
    python3 - <<'PY'
from pathlib import Path

paths = [Path("src/pages/Game.tsx"), Path("src/gameCapabilities.ts")]
sources = {path: path.read_bytes() for path in paths if path.is_file()}
old = b"'http://localhost:8080/api/partidas'"
new = b"'/api/partidas'"
legacy = sum(source.count(old) for source in sources.values())
relative = sum(source.count(new) for source in sources.values())

if legacy == 1 and relative == 0:
    for path, source in sources.items():
        if old in source:
            path.write_bytes(source.replace(old, new))
elif (legacy, relative) != (0, 1):
    raise SystemExit("Confira o endereço da API antes de publicar este commit.")
PY
    npm ci
    npm run build
)

release=$(mktemp -d "$base/releases/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
install -m 600 "$build/backend"/build/libs/*.jar "$release/chess-backend.jar"
mv "$build/frontend/dist" "$release/web"
printf 'backend=%s\nfrontend=%s\n' "$backend_commit" "$frontend_commit" > "$release/commits.txt"

install -m 600 "$config/$nginx_config" "$base/nginx.conf"
install -m 600 "$config/$web_service.service" "$config/$backend_service.service" "$HOME/.config/systemd/user/"
nginx -e stderr -t -p "$base/" -c nginx.conf
systemctl --user daemon-reload
systemctl --user enable "$backend_service.service" "$web_service.service"

ativar() {
    ln -sfn -- "$1" "$base/.current.next"
    mv -Tf -- "$base/.current.next" "$base/current"
}

anterior=$(readlink "$base/current" || :)
ativar "$release"
if systemctl --user restart "$backend_service.service" "$web_service.service" &&
    curl --fail --silent --show-error --retry 20 --retry-all-errors \
        --retry-delay 2 --max-time 3 "http://127.0.0.1:$web_port/api/avatares" >/dev/null &&
    curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:$web_port/" >/dev/null; then
    printf 'Versão ativa em %s\n' "$release"
    exit 0
fi

if [[ -n "$anterior" ]]; then
    ativar "$anterior"
    systemctl --user restart "$backend_service.service" "$web_service.service"
else
    systemctl --user stop "$web_service.service" "$backend_service.service"
    rm -- "$base/current"
fi
echo "A nova versão não respondeu pela API. Confira o journal dos serviços." >&2
exit 1

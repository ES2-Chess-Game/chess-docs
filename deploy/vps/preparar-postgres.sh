#!/usr/bin/env bash
set -euo pipefail
umask 077

base="$HOME/chess-deploy"
runtime="$base/runtime/postgres16"
database="$base/postgres"
bin="$runtime/usr/lib/postgresql/16/bin"
config=$(cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$runtime/usr/lib/x86_64-linux-gnu"

install -d -m 700 "$runtime/packages" "$database/socket" "$HOME/.config/systemd/user"
if [[ ! -x "$bin/pg_dump" || ! -e "$LD_LIBRARY_PATH/libpq.so.5" ]]; then
    (
        cd "$runtime/packages"
        apt-get download postgresql-16 postgresql-client-16 libpq5
        dpkg-deb -x postgresql-16_*.deb "$runtime"
        dpkg-deb -x postgresql-client-16_*.deb "$runtime"
        dpkg-deb -x libpq5_*.deb "$runtime"
    )
fi

if [[ ! -s "$database/data/PG_VERSION" ]]; then
    "$bin/initdb" -D "$database/data" -L "$runtime/usr/share/postgresql/16" \
        --auth-local=peer --auth-host=scram-sha-256 --username="$USER" \
        --locale=C.UTF-8 --encoding=UTF8 --data-checksums
fi

install -m 600 "$config"/chess-postgres{,-backup}.service \
    "$config/chess-postgres-backup.timer" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now chess-postgres.service

for attempt in {1..10}; do
    if "$bin/pg_isready" -h "$database/socket" -p 15432 -q; then
        break
    fi
    sleep 1
done

if [[ ! -e "$database/backend.env" && ! -e "$base/backend.env" ]]; then
    password=$(openssl rand -hex 32)
    "$bin/psql" -X -w -v ON_ERROR_STOP=1 -h "$database/socket" -p 15432 -d postgres <<SQL
SELECT 'CREATE ROLE chess_app LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'chess_app')
\gexec
ALTER ROLE chess_app PASSWORD '$password';
SELECT 'CREATE DATABASE chess OWNER chess_app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'chess')
\gexec
SQL
    PGPASSWORD="$password" "$bin/psql" -X -w -h 127.0.0.1 -p 15432 -d chess -U chess_app -c 'SELECT current_database()'
    printf 'SPRING_PROFILES_ACTIVE=prod\nCHESS_DB_URL=jdbc:postgresql://127.0.0.1:15432/chess\nCHESS_DB_USER=chess_app\nCHESS_DB_PASSWORD=%s\n' \
        "$password" > "$database/backend.env"
fi

systemctl --user enable --now chess-postgres-backup.timer
systemctl --user start chess-postgres-backup.service

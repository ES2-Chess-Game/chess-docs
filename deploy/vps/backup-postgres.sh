#!/usr/bin/env bash
set -euo pipefail
umask 077

base="$HOME/chess-deploy"
runtime="$base/runtime/postgres16"
export LD_LIBRARY_PATH="$runtime/usr/lib/x86_64-linux-gnu"
bin="$runtime/usr/lib/postgresql/16/bin"
backups="$base/postgres/backups"
install -d -m 700 "$backups"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
export PGHOST="$base/postgres/socket" PGPORT=15432
prod_exists=$("$bin/psql" -X -w -At -d postgres -c "SELECT 1 FROM pg_database WHERE datname = 'chess_prod'")
databases=(chess)
if [[ "$prod_exists" == 1 ]]; then
    databases+=(chess_prod)
fi
for db in "${databases[@]}"; do
    partial=$(mktemp "$backups/.$db-$timestamp.XXXXXX")
    trap 'rm -f -- "$partial"' EXIT
    "$bin/pg_dump" --no-password --dbname="$db" --format=custom --file="$partial"
    mv -T -- "$partial" "$backups/$db-$timestamp.dump"
    trap - EXIT
done

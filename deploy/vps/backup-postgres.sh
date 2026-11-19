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
partial=$(mktemp "$backups/.chess-$timestamp.XXXXXX")
trap 'rm -f -- "$partial"' EXIT

"$bin/pg_dump" --no-password --host="$base/postgres/socket" --port=15432 --dbname=chess \
    --format=custom --file="$partial"
mv -T -- "$partial" "$backups/chess-$timestamp.dump"

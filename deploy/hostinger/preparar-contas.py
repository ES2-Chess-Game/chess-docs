#!/usr/bin/env python3
import argparse
import json
import os
import re
from pathlib import Path


def replace_route(config, before, after):
    if config.count(after) == 1:
        return config
    if config.count(before) != 1:
        raise ValueError("Lista de rotas inesperada")
    return config.replace(before, after)


def caddy_config(config):
    before = "@game path /api/partidas /api/partidas/* /api/avatares"
    after = before + " /api/auth/cadastro /api/auth/login /api/auth/logout /api/auth/me /api/perfil"
    config = replace_route(config, before, after)
    block = re.search(r"(?ms)^\s*handle @game \{.*?^\t\t\}", config)
    if block is None or "header_up -Authorization" not in block[0]:
        raise ValueError("Bloco de API inesperado")
    api = re.sub(r"(?m)^[ \t]*header_up -Cookie[ \t]*\r?\n", "", block[0])
    return config[:block.start()] + api + config[block.end():]


def nginx_patch(config):
    before = r"location ~ ^/api/(partidas|avatares|auth)(/|$) {"
    after = r"location ~ ^/api/(partidas(/|$)|avatares(/|$)|auth/(cadastro|login|logout|me)$|perfil$) {"
    return json.dumps({"data": {"nginx.conf": replace_route(config, before, after)}}) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("caddy", "nginx"))
    parser.add_argument("source", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    transform = caddy_config if args.kind == "caddy" else nginx_patch
    try:
        candidate = transform(args.source.read_text())
        fd = os.open(args.candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as output:
            output.write(candidate)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()

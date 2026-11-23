# Contas no Clube 64

O Caddy mantém o Basic Auth na entrada do endereço de avaliação. Dentro do jogo, cada pessoa pode criar sua conta, escolher um avatar e recuperar suas partidas. O login do jogo usa um cookie de sessão JDBC. O proxy encaminha o cookie nas rotas da API do jogo e retira o cabeçalho de Basic Auth antes de chamar a aplicação.

| Credencial | Armazenamento |
| --- | --- |
| Senha de uma conta do Clube 64 | Hash BCrypt com salt individual em `users.password_hash` |
| Acesso ao endereço de avaliação | Hash Argon2id na configuração privada do Caddy |
| Conexão do backend ao PostgreSQL | Secret Kubernetes `chess-prd-db-login` |

A autenticação compara a senha informada com o hash BCrypt. A aplicação não precisa de chave de decifragem.

## Ativação

Homologue cadastro, login, edição de perfil e retomada. Depois da promoção dos dois PRs do backend, prepare os candidatos no host com acesso de operador. Execute na pasta deste documento e preserve as cópias para rollback.

```bash
set -euo pipefail
umask 077
caddy_main=/etc/grimoire-media/Caddyfile
caddy_site=/etc/grimoire-media/xadrez-es2.Caddyfile
work=$(mktemp -d)
k() { /usr/local/bin/k3s kubectl --context default -n chess-prd "$@"; }

cp -p "$caddy_site" "$work/caddy.original"
k get configmap chess-nginx -o jsonpath='{.data.nginx\.conf}' > "$work/nginx.original"
k get configmap chess-nginx -o json | python3 -c \
  'import json,sys; print(json.dumps({"data": json.load(sys.stdin)["data"]}))' > "$work/nginx.restore.json"

python3 preparar-contas.py caddy "$work/caddy.original" "$work/caddy.candidate"
python3 preparar-contas.py nginx "$work/nginx.original" "$work/nginx.patch.json"

caddy_test=$(mktemp /etc/grimoire-media/.Caddyfile-contas.XXXXXX)
sed "s|^[[:space:]]*import .*xadrez-es2\.Caddyfile[[:space:]]*$|import $work/caddy.candidate|" "$caddy_main" > "$caddy_test"
grep -Fq "import $work/caddy.candidate" "$caddy_test"
caddy validate --config "$caddy_test" --adapter caddyfile
unlink "$caddy_test"
k patch configmap chess-nginx --type merge --patch-file "$work/nginx.patch.json" --dry-run=server

k set env deployment/chess-backend SERVER_SERVLET_SESSION_COOKIE_SECURE=true
k rollout status deployment/chess-backend --timeout=120s
k patch configmap chess-nginx --type merge --patch-file "$work/nginx.patch.json"
k rollout restart deployment/chess-web
k rollout status deployment/chess-web --timeout=120s

install -m "$(stat -c '%a' "$caddy_site")" -o "$(stat -c '%u' "$caddy_site")" \
  -g "$(stat -c '%g' "$caddy_site")" "$work/caddy.candidate" "$caddy_site"
caddy validate --config "$caddy_main" --adapter caddyfile
caddy reload --config "$caddy_main" --adapter caddyfile
```

Promova o frontend e confirme:

- O domínio ainda pede a credencial de avaliação
- O login no jogo emite `SESSION` com `Secure`, `HttpOnly` e `SameSite=Lax`
- A conta recupera as partidas em outro navegador e o logout encerra a sessão
- Uma conta diferente recebe 404 para a partida salva de outro usuário
- `/api/auth/outros`, `/actuator` e `/healthz` continuam fechados no domínio

Para reverter as rotas, restaure `caddy.original` com as permissões originais, valide e recarregue o Caddy. Aplique `nginx.restore.json` no mesmo ConfigMap e reinicie o deployment `chess-web`. Use as revisões anteriores dos deployments se também for necessário reverter uma imagem. As colunas novas do PostgreSQL são aditivas e continuam compatíveis com o backend anterior.

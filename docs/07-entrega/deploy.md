# Deploy de homologação

A homologação na VPS usa os commits `99cb4cb` do backend e `ad4fb93` do frontend. O backend Spring Boot roda com Java 25. O Nginx da conta `chess` entrega o frontend e encaminha `/api/` para o backend pela interface local. Os dois serviços são gerenciados pelo systemd do usuário.

## Acessar o jogo

Com uma chave SSH autorizada na VPS, abra um túnel e mantenha o terminal aberto:

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -i ~/.ssh/id_ed25519_vps \
  -L 127.0.0.1:18080:127.0.0.1:18080 chess@72.60.4.150
```

Abra [http://127.0.0.1:18080](http://127.0.0.1:18080). Se a porta local estiver em uso, troque o primeiro `18080` do argumento `-L` e use a porta escolhida no navegador.

## Atualizar a homologação

A conta da VPS precisa de Nginx, Git, curl, Python 3 e systemd de usuário. Instale Temurin 25 em `~/chess-deploy/runtime/java25` e Node.js 24 em `~/chess-deploy/runtime/node24`. Use `loginctl enable-linger chess` para iniciar os serviços no boot e mantê-los ativos após o fim da sessão SSH.

A partir da raiz de `chess-docs`, copie os arquivos de deploy:

```bash
ssh -i ~/.ssh/id_ed25519_vps chess@72.60.4.150 \
  'install -d -m 700 "$HOME/chess-deploy/config"'
scp -i ~/.ssh/id_ed25519_vps deploy/vps/* \
  chess@72.60.4.150:chess-deploy/config/
```

Na VPS, informe os hashes completos a publicar, na ordem backend e frontend:

```bash
bash ~/chess-deploy/config/publicar-hml.sh <commit-backend> <commit-frontend>
cat ~/chess-deploy/current/commits.txt
systemctl --user status chess-backend chess-web
```

O script aceita commits presentes na história de `hml` dos respectivos repositórios. Ele compila o JAR com o Gradle Wrapper, gera os arquivos estáticos com Vite e ajusta o endereço da API no frontend de homologação para atender na mesma origem. Cada publicação guarda os dois commits em `commits.txt`. Se a API não responder após a troca, o script volta à entrega anterior quando ela existe.

## Limites da homologação

O acesso remoto usa o túnel SSH. Para servir o jogo publicamente, o administrador da VPS pode adicionar um host HTTPS ao Nginx principal, apontando para `127.0.0.1:18080`. O banco H2 e o estado das partidas ficam em memória e são reiniciados junto com a aplicação. As pendências de produção estão em [deploy do backend](https://github.com/ES2-Chess-Game/chess-backend/issues/37), [deploy do frontend](https://github.com/ES2-Chess-Game/chess-frontend/issues/15) e [Postgres](https://github.com/ES2-Chess-Game/chess-backend/issues/38).

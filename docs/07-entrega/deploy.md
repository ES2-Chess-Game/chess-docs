# Deploy de homologação

A primeira publicação de homologação na VPS usou os commits `99cb4cb` do backend e `ad4fb93` do frontend. O backend Spring Boot roda com Java 25. O Nginx da conta `chess` entrega o frontend e encaminha `/api/` para o backend pela interface local. Os dois serviços são gerenciados pelo systemd do usuário.

## Acessar o jogo

Com uma chave SSH autorizada na VPS, abra um túnel e mantenha o terminal aberto:

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -i ~/.ssh/id_ed25519_vps \
  -L 127.0.0.1:18080:127.0.0.1:18080 chess@72.60.4.150
```

Abra [http://127.0.0.1:18080](http://127.0.0.1:18080). Se a porta local estiver em uso, troque o primeiro `18080` do argumento `-L` e use a porta escolhida no navegador.

## Atualização pelo GitHub Actions

O CI de cada repositório de código chama o deploy depois do build em `hml`. A VPS lê os commits atuais dos dois repositórios e serializa as publicações. Quando os dois commits já estão ativos e a API está respondendo, a execução termina sem reiniciar os serviços.

O ambiente `homologacao` de cada repositório aceita a branch `hml` e guarda o segredo `VPS_SSH_KEY` e a variável `VPS_KNOWN_HOSTS`. Na VPS, a entrada correspondente em `~/.ssh/authorized_keys` usa `restrict` e executa `receber-hml.sh`, que aceita o comando `deploy-hml`. Use a chave administrativa da conta `chess` para atualizar os arquivos de configuração do deploy.

## Atualizar a homologação manualmente

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

## PostgreSQL e backup

O PostgreSQL 16 roda na conta `chess` e aceita conexões apenas na interface local, porta `15432`. O backend usa o perfil `prod` da aplicação para conectar a esse banco. Esse perfil seleciona o banco de dados e não altera a branch do deploy. O desenvolvimento local segue com H2.

Para preparar a instância em uma VPS Ubuntu 24.04 x86_64, copie os arquivos de deploy e rode `bash ~/chess-deploy/config/preparar-postgres.sh` na VPS. O script extrai os pacotes oficiais para a pasta do projeto, cria o banco, configura o serviço de usuário e agenda o backup diário. Ele deixa as credenciais em `~/chess-deploy/postgres/backend.env`. Depois de publicar um backend com o perfil PostgreSQL, mova esse arquivo para `~/chess-deploy/backend.env` e reinicie `chess-backend.service`.

Os backups ficam em `~/chess-deploy/postgres/backups`. Para gerar um backup avulso, rode `systemctl --user start chess-postgres-backup.service`. Os pacotes instalados no diretório do projeto precisam ser atualizados pelo responsável pela VPS. Contas e avatares usam PostgreSQL. As partidas desta versão continuam em memória.

## Produção

O deploy de `prd` tem chave, serviços e banco próprios. A aplicação de produção usa a porta local `28080` e o banco `chess_prod`; a homologação usa `18080` e o banco `chess`.

A VPS só inicia o deploy quando os commits mínimos de backend e frontend em [prd-minimo.txt](../../deploy/vps/prd-minimo.txt) estiverem no histórico de `prd` dos dois repositórios. Essa primeira promoção está em [backend #52](https://github.com/ES2-Chess-Game/chess-backend/pull/52) e [frontend #17](https://github.com/ES2-Chess-Game/chess-frontend/pull/17). Depois dos merges, o GitHub Actions usa o ambiente `producao` e chama `deploy-prd` após o build.

Para preparar o banco da produção, rode `bash ~/chess-deploy/config/preparar-postgres.sh prd` na VPS. O timer diário gera um arquivo de backup para cada banco. A produção começa com um banco próprio e vazio; o backend cadastra os avatares no primeiro boot.

## Endereço público

O acesso remoto ainda usa o túnel SSH. O administrador pode adicionar um host HTTPS ao Nginx principal para servir o jogo publicamente. Aponte o DNS do subdomínio para a VPS e use este trecho no bloco HTTPS depois do deploy de produção. Para publicar a homologação em um subdomínio próprio, use a porta `18080`:

```nginx
location / {
    proxy_pass http://127.0.0.1:28080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header Forwarded "";
}
```

Acompanhe a publicação pública e a promoção para produção nas issues de [deploy do backend](https://github.com/ES2-Chess-Game/chess-backend/issues/37) e [deploy do frontend](https://github.com/ES2-Chess-Game/chess-frontend/issues/15). A configuração do banco está vinculada à [issue de PostgreSQL](https://github.com/ES2-Chess-Game/chess-backend/issues/38).

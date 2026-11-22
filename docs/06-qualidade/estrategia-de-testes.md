# Estratégia de testes do Clube 64

O objetivo é verificar as regras e a comunicação entre as partes e, na homologação, confirmar com quem joga que a interface permite começar e terminar uma partida sem ajuda. A cobertura mede quanto código foi exercitado. O aceite exige uma pessoa usando o jogo.

Base da disciplina: Leonardo Murta, [Verificação, Validação e Testes](https://drive.google.com/file/d/1VN50oyj3aw49b0XMvwT6sobTP41YvaA0/view) e [Lista 6](https://drive.google.com/file/d/11aDUuiuF_KgIrTNNmsT4nq1l9FOCZ4XM/view).

## Ordem de execução

| Nível | Como verificar | Evidência |
| --- | --- | --- |
| Unidade | Os validadores, regras, fim de jogo e Minimax exercitam caminhos e fronteiras em posições controladas | JUnit e relatório JaCoCo do backend |
| Integração | O MockMvc exercita o contrato HTTP com controller, segurança e motor reais. Os testes de cadastro usam H2 | JUnit em `chess-backend` |
| Sistema | O Playwright abre o build do frontend e joga contra o backend real, sem substituir a API. O CI usa H2 e Chromium em desktop e celular emulado | Job `build` de `chess-frontend` |
| Fumaça na VPS | Abrir o jogo por HTTPS, criar uma partida e fazer um lance. Sem credenciais, o acesso deve ser recusado | Registro da revisão e dos resultados da verificação |
| Aceitação | Outro integrante ou o professor executa os cenários abaixo e registra o resultado | Checklist de homologação com observações |

A integração é incremental: regras isoladas, depois catálogo de casos HTTP, depois frontend com backend. A cada PR, as suítes anteriores são repetidas como regressão. O teste do navegador usa uma revisão fixada do backend para que mudanças em outro repositório não alterem o resultado sem revisão.

## Dados e resultados esperados

| Caso | Entrada e ação | Resultado esperado | Onde roda |
| --- | --- | --- | --- |
| INT-01 | Criar partida, jogar e2–e4 e consultar pelo mesmo identificador | Peão branco em e4 e vez das pretas | API |
| INT-02 | Coordenada de linha -1 ou 8, origem vazia, peça fora do turno ou destino com peça aliada | HTTP 400 com mensagem de regra. Coordenada fora do tabuleiro preserva a partida | API |
| INT-03 | Consultar um identificador inexistente | HTTP 404 com mensagem de erro | API |
| SYS-01 | Escolher o modo local e jogar f3, e5, g4, Dh4 | Xeque-mate, vitória das pretas e bloqueio de novos lances | API e navegador |
| SYS-02 | Escolher o nível básico e jogar e2–e4 | O Minimax altera o tabuleiro, registra seu lance e devolve o turno às brancas | API e navegador |
| SYS-03 | Tentar e2–e5 e depois e2–e4 | Mensagem no lance ilegal, posição preservada e próximo lance aceito | Navegador |
| SYS-04 | Entrar no tabuleiro pelo teclado e jogar e2–e4 com setas e Enter | Foco visível, lance realizado e página sem rolagem horizontal | Navegador |

## Executar

- Backend: `./gradlew build`. O relatório fica em `build/reports/jacoco/test/html/index.html`.
- Frontend: suba o backend com Java 25 em `127.0.0.1:8080`. No frontend, use `npm ci`, `npx playwright install chromium`, `npm run build` e `npm run test:e2e`. O Playwright inicia a prévia e o Vite encaminha a API ao backend.
- A prévia automatizada usa banco descartável. A infraestrutura de produção é verificada em separado, pelo HTTPS da VPS.

## Aceitação da entrega

| Caso | Dado | Quando | Então |
| --- | --- | --- | --- |
| ACE-01 | Duas pessoas no mesmo dispositivo | Abrem o modo local e fazem o primeiro lance | Conseguem identificar de quem é a vez e continuar sem ajuda |
| ACE-02 | Uma pessoa quer praticar | Abre o nível básico, tenta um lance inválido e depois faz um lance legal | Entende a correção e localiza a resposta da máquina no histórico |
| ACE-03 | Uma pessoa joga em um celular | Abre uma partida e seleciona uma peça | Lê o estado, alcança o tabuleiro e joga sem precisar arrastar a tela para o lado |

Para cada cenário, anote a revisão ou link da entrega, o dispositivo, o resultado observado e qualquer dificuldade. O aceite é a decisão de quem jogou. Os testes automatizados não preenchem esse resultado. Cadastro pela interface, perfil, retomada e outros níveis da IA devem entrar no roteiro à medida que estiverem disponíveis.

Acompanhe os itens pendentes nas issues de [integração](https://github.com/ES2-Chess-Game/chess-backend/issues/15), [regressão](https://github.com/ES2-Chess-Game/chess-backend/issues/46), [sistema](https://github.com/ES2-Chess-Game/chess-backend/issues/47) e [aceitação](https://github.com/ES2-Chess-Game/chess-backend/issues/48).

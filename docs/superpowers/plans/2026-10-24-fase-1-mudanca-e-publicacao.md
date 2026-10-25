# Fase 1 — Mudança de pasta, padronização de docs e publicação · Plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Os 7 repos pessoais vivem em `~/Documents/personal-projects/`, todos com README no modelo único, `CHANGELOG.md`, LICENSE e git limpo; Hub, Dose, Pauta, Deck e NeyHub publicados como repos públicos depois de uma varredura de segredos e dados de trabalho.

**Architecture:** Operações de arquivo, git e GitHub, mais as limpezas de dados de trabalho no Pauta. Os apps que rodam a partir de `~/Documents/<app>/build/` são fechados, movidos, recompilados no lugar novo e reabertos.

**Tech Stack:** zsh, git, `git filter-repo` (instalado em `/opt/homebrew/bin`), `gh` CLI, `scripts/build.sh` de cada app.

**Spec:** `~/Documents/personal-projects/neyhub/docs/superpowers/specs/2026-10-24-neyhub-design.md` (§3, §7.6–7.7, §8, §10 Fase 1, decisões 6, 15, 17, 18)

## Global Constraints

- Pasta final: `~/Documents/personal-projects/{neyhub,aero,capture,hub,dose,pauta,deck,neyzap}`. `conecta-matcon` e o app de trabalho **não** se movem.
- `radar` vira `pauta` (pasta local e nome do repo no GitHub). Bundle ID continua `local.pauta`.
- Bundle IDs (`local.*`) e pastas de dados em `~/Library/Application Support/*` não mudam.
- Repos novos: `yagoramires/{hub,dose,pauta,deck,neyhub}`, todos **públicos**.
- **Nada é publicado sem a varredura limpa E OK explícito do Yago naquela hora.**
- Nunca `git push --force` em repo já público (aero, capture, neyzap), exceto a limpeza da coautoria na Task 6 Step 4, e só com OK explícito do Yago.
- **NeyZap:** nunca `pkill`, nunca `build.sh --run` (o de uso real é `/Applications/NeyZap.app`; regra de zero ban e reinício suave). Só `scripts/build.sh` sem `--run`.
- Termos de trabalho e padrões de segredo ficam **fora de qualquer repo**, em `~/Documents/personal-projects/.scan/work-terms.txt` e `.scan/secrets.txt` (já criados). Nenhum arquivo versionado cita esses termos literalmente.
- Todos os comandos rodam a partir de `~/Documents/personal-projects` (`cd` explícito em cada passo).
- Textos de README/CHANGELOG em pt-BR; CHANGELOG no formato Keep a Changelog.
- Licença MIT, `Copyright (c) 2026 Yago Ramires`.
- Commits **sem** linha `Co-Authored-By` do Claude (pedido do Yago, 2026-10-25): só a conta do Yago aparece. Commits antigos também são limpos (Task 3 Step 7 e Task 6 Step 4).

## Review Focus

- Itens de login registrados pelo caminho antigo — Task 1 Step 6 confere que nenhuma URL antiga sobrou.
- Dado de trabalho ou segredo só no **histórico** do git, ou dentro de **imagem** (git grep não lê PNG) — Task 4 Steps 2 e 5.
- Binário/asset de terceiros indo a público (Deck `re/`, logos no Hub) — Task 2 Step 1 e Task 4 Step 4.
- `.build/` com caminhos absolutos antigos — Task 1 Step 4 apaga `.build`.
- Assinatura caindo para ad-hoc sem ninguém perceber (Hub, Dose, Pauta, Deck só avisam) — Task 1 Step 5 imprime por app.

---

### Task 1: Mover as pastas e reabrir os apps no lugar novo

**Files:**
- Move: `~/Documents/{aero,capture,hub,dose,deck,neyzap}` → `~/Documents/personal-projects/<mesmo nome>`; `~/Documents/radar` → `~/Documents/personal-projects/pauta`

- [ ] **Step 1: Registrar o que está rodando e o que abre no login**

Run: `ps -axo pid,comm | grep -E "Documents/(aero|capture|neyzap|hub|dose|radar|deck)/" > .scan/running.txt` e, em background, `sfltool dumpbtm > .scan/btm-antes.txt` (leva minutos).
Expected: em 2026-10-24 rodavam Aero, Capture, Deck, Dose, Hub, Pauta de `build/`; itens de login: Aero, Deck, Dose, Pauta e um `Radar.app` antigo.

- [ ] **Step 2: Repos limpos e tags locais completas**

Run: `cd ~/Documents && for d in aero capture neyzap hub dose radar deck; do echo "$d $(git -C $d status --porcelain 2>/dev/null | wc -l)"; done` — Expected: todos `0` (deck sem git: ignorar). Se não, parar e perguntar.
Run: `for d in aero capture neyzap; do git -C ~/Documents/$d fetch --tags; done` — Expected: `git -C ~/Documents/aero tag` inclui `v0.4.1`; capture tem `v0.1.0 v0.2.0`; neyzap inclui `v0.3.1`.

- [ ] **Step 3: Fechar (menos o NeyZap) e mover**

Run: `pkill -x Aero; pkill -x Capture; pkill -x Deck; pkill -x Dose; pkill -x Hub; pkill -x Pauta; cd ~/Documents && mv aero capture hub dose deck neyzap personal-projects/ && mv radar personal-projects/pauta`
Expected: `ls ~/Documents/personal-projects` → `aero capture deck dose hub neyhub neyzap pauta`.

- [ ] **Step 4: Rebuild limpo**

Run: `cd ~/Documents/personal-projects && for d in aero capture hub dose deck pauta; do (cd $d && rm -rf .build && scripts/build.sh --run) || echo "FALHOU $d"; done; (cd neyzap && rm -rf .build && scripts/build.sh)`
Expected: nenhum `FALHOU`; ícones de Aero, Capture, Hub, Dose, Deck, Pauta de volta na barra; NeyZap **não** abre.

- [ ] **Step 5: Assinatura por app**

Run: `cd ~/Documents/personal-projects && for a in */build/*.app; do echo "$a"; codesign -dv "$a" 2>&1 | grep -E 'Authority|Signature=adhoc'; done`
Expected: `Authority=Aero Local Signing` em todos (NeyZap: `NeyZap Local Signing`); nenhum `Signature=adhoc`. Conferir também que o Aero ainda encaixa uma janela com ⌘→ e o Capture ainda tira print (prova que as permissões sobreviveram).

- [ ] **Step 6: Itens de login pelo caminho novo**

- Aero (`AppDelegate.swift:259`), Deck (`Views.swift:134`), Dose (`Views/ItemsView.swift:38`): desligar e religar "Abrir ao iniciar" no próprio app.
- Pauta (só registra na primeira vez, `AppDelegate.swift:59-61`): `pkill -x Pauta; defaults delete local.pauta loginItemOffered; open pauta/build/Pauta.app`.
- `Radar.app` antigo: o Yago remove em Ajustes > Geral > Itens de Início (pedir).
- Não usar `sfltool resetbtm`.
Run (background): `sfltool dumpbtm > .scan/btm-depois.txt`
Expected: `grep -E "URL: .*Documents/(aero|deck|dose|radar)/" .scan/btm-depois.txt` → nada; `grep -E "URL: .*personal-projects/.*/(Aero|Deck|Dose|Pauta).app" .scan/btm-depois.txt` → 4 linhas.

---

### Task 2: Git, .gitignore e licença onde faltam

**Files:**
- Create: `deck/.git`, ajustar `deck/.gitignore`; `{hub,pauta,deck}/LICENSE`; `{hub,deck}/scripts/setup-signing.sh` (cópia de `aero/scripts/setup-signing.sh`)

- [ ] **Step 1: Deck — decidir o `.gitignore` ANTES de qualquer `git add`**

Conteúdo de `deck/re/` (7 MB): `PROTOCOL.md`, `decode.py`, `probe.swift` (do Yago — entram) e `sdlib.arm64`, `probe` (binário), `lamp/` (plugin da Mirabox com imagens), `fw/`, `keys*.log`, `current-layout.png` (terceiros/dumps — não entram). Acrescentar ao `.gitignore`: `re/*` + `!re/PROTOCOL.md` + `!re/decode.py` + `!re/probe.swift`.
Run: `cd ~/Documents/personal-projects/deck && git init -b main && git add -A && git ls-files | grep '^re/'`
Expected: exatamente `re/PROTOCOL.md`, `re/decode.py`, `re/probe.swift`.

- [ ] **Step 2: LICENSE e setup-signing**

Run: `cd ~/Documents/personal-projects && for d in hub pauta deck; do cp aero/LICENSE $d/LICENSE; done; for d in hub deck; do cp aero/scripts/setup-signing.sh $d/scripts/; done`
No `hub/scripts/build.sh` e `deck/scripts/build.sh`, apontar a mensagem de "sem certificado" para `scripts/setup-signing.sh` local.

- [ ] **Step 3: Commits**

```bash
cd ~/Documents/personal-projects
git -C deck add -A && git -C deck commit -m "chore: primeiro commit do Deck"
for d in hub pauta; do git -C $d add LICENSE && git -C $d commit -m "chore: licença MIT"; done
git -C hub add scripts && git -C hub commit -m "chore: setup-signing local"
```

---

### Task 3: Limpar dados de trabalho e varrer segredos (hub, dose, pauta, deck, neyhub)

**Files:**
- Create: `neyhub/.gitignore` (`.build/ build/ dist/ .superpowers/`), `neyhub/LICENSE`; `git init -b main` no `neyhub` (para a varredura funcionar)
- Modify (pauta): `Sources/Pauta/Connect/Connect.swift:28` (`defaultJiraSite`), `Sources/Pauta/Credentials.swift:9` (`jiraProject`), `SettingsView.swift:111,114`, `ConnectView.swift`, `README.md:56`, fixtures em `Snapshots.swift`/`SelfTest.swift`, docs versionados em `docs/superpowers/`; asserts em `SelfTest.swift:235,637`

- [ ] **Step 1: Varredura da árvore**

Run (para `d` em hub dose pauta deck neyhub): `cd ~/Documents/personal-projects/$d && git grep -nIE -f ../.scan/work-terms.txt -f ../.scan/secrets.txt | grep -v 'noreply@anthropic.com' > ../.scan/tree-$d.txt; wc -l ../.scan/tree-$d.txt`
Expected: lista completa em arquivo (sem `head`). Placeholder óbvio (`xoxb-…`, `SEU_TOKEN`) e o e-mail do próprio Yago no LICENSE/README são aceitáveis.

- [ ] **Step 2: Varredura do histórico**

Run: `git log -p --all | grep -nIE -f ../.scan/work-terms.txt -f ../.scan/secrets.txt | grep -v 'noreply@anthropic.com' > ../.scan/hist-$d.txt` e `git log --all --format='%h %ae %s' -G"$(paste -sd'|' ../.scan/work-terms.txt ../.scan/secrets.txt)" > ../.scan/commits-$d.txt`
Expected: em 2026-10-24 já se sabe: pauta tem 13 dos 38 commits com termos de trabalho; hub tem 23 dos 25 commits com um segundo e-mail do Yago como autor (os demais repos usam o e-mail principal do `git config user.email`).

- [ ] **Step 3: Limpar a árvore do Pauta**

`defaultJiraSite = ""` e `jiraProject = ""` (vazios, não fictícios — ninguém deve se conectar a um site inventado; o `credentials.json` do Yago grava todos os campos, então nada dele se perde). Telas que mostravam esses padrões passam a mostrar um placeholder neutro ("https://… (endereço do seu Jira)"). Fixtures e docs: repos → `acme/web-app`, `acme/infra`; projeto → `ACME`; pessoas/canais → fictícios. Atualizar os asserts do selftest.
Run: `cd ~/Documents/personal-projects/pauta && swift build && .build/debug/Pauta --selftest` → Expected: `selftest ok`. Rodar de novo o Step 1 → Expected: `tree-pauta.txt` sem nenhum termo de `work-terms.txt`. Abrir o Pauta real → continua conectado com as credenciais de sempre.
Commit: `git commit -am "chore: remove dados de trabalho dos padrões e exemplos"`.

- [ ] **Step 4: Conteúdo de terceiros no Hub**

`hub/Resources/AppLogos/*.png` (logos de Netflix, Disney+, Globoplay, Spotify, Twitch…): acrescentar ao `hub/LICENSE` uma ressalva no formato da do NeyZap ("Vale para o código. Os logos em Resources/AppLogos são marcas dos respectivos donos…"). `TuyaClient.swift:9` (`clientId` do Home Assistant, público no código do HA): manter e comentar a origem numa linha. Commit `docs: ressalva de marcas de terceiros`.

- [ ] **Step 5: Imagens no olho**

Run: `cd ~/Documents/personal-projects && for d in hub dose pauta deck; do git -C $d ls-files | grep -iE '\.(png|jpe?g|gif)$' | sed "s|^|$d/|"; done`
Expected: o Yago (ou o executor, abrindo cada uma) confirma que nenhuma mostra dado de trabalho, nome de cômodo/aparelho real ou pessoa.

- [ ] **Step 6: PARAR — decisões do Yago antes de publicar**

Mostrar ao Yago os arquivos `.scan/*-$d.txt` resumidos (repo, commit, tipo — **sem imprimir valor de segredo**) e obter as respostas já combinadas no checkpoint do plano (ver "Decisões pendentes" no fim). Segredo real achado → também **revogar** na origem. Executar a escolha:
- reescrever histórico: `git filter-repo --replace-text ../.scan/replace-<d>.txt` (arquivo fora do repo, `termo==>fictício`) e/ou `--mailmap ../.scan/mailmap.txt`;
- ou publicar com um commit só: `git checkout --orphan pub && git add -A && git commit -m "Primeira versão pública" && git branch -D main && git branch -m main`.
Expected: Steps 1 e 2 rodados de novo → zero termos de trabalho e zero segredos na árvore e no histórico.

- [ ] **Step 7: Tirar a coautoria do Claude do histórico (hub, dose)**

O Pauta já sai com um commit só e o Deck nasce sem a linha. Arquivo fora do repo `../.scan/strip-coauthor.py` com o callback do filter-repo: `return re.sub(rb"\n*Co-Authored-By: Claude[^\n]*", b"", message).rstrip() + b"\n"`.
Run: `cd ~/Documents/personal-projects/$d && git filter-repo --force --message-callback "$(cat ../.scan/strip-coauthor.py)"` (no hub, junto com o `--mailmap` da decisão 2, num único `filter-repo`).
Expected: `git log --all --format=%B | grep -ci 'co-authored-by: claude'` → `0`; `git log --format='%an <%ae>' | sort -u` → só a conta do Yago.

---

### Task 4: README no modelo único e CHANGELOG nos 7 apps

**Files:**
- Create: `neyhub/docs/templates/README-modelo.md`
- Modify/Create: `<app>/README.md`, `<app>/CHANGELOG.md` para aero, capture, hub, dose, pauta, deck, neyzap

- [ ] **Step 1: Modelo** — `# <Nome>` + uma linha · print · e **9 seções** `##`, nesta ordem: Instalar · Permissões · Como usar · Atalhos · Modos de exibição · Atualizações · Build local · Patch notes · Licença. "Instalar": hoje é **build local** (`scripts/setup-signing.sh` uma vez, depois `scripts/build.sh --run`); Aero/Capture/NeyZap também têm o `.zip` do release. Sem `.dmg` nem NeyHub ainda — uma linha honesta: "Instalador `.dmg` e instalação pelo NeyHub chegam na próxima versão." Aviso do Gatekeeper ("botão direito → Abrir") só onde há download.
- [ ] **Step 2: README de cada app** — conteúdo do README atual + código (atalhos de `Hotkeys.swift`, permissões do `Info.plist`/código). Seção que ainda não se aplica: uma linha honesta. NeyZap sem menção ao NeyHub. Prints gerados **agora** (depois da limpeza da Task 3) com `--snapshots` onde existir; conferir no olho.
Expected: `grep -c "^## " <app>/README.md` → `9` em todos.
- [ ] **Step 3: CHANGELOG** — uma seção `## [x.y.z] - AAAA-MM-DD` por tag (aero `v0.1.0…v0.4.1`, capture `v0.1.0 v0.2.0`, neyzap `…v0.3.1`), resumindo `git log <tag anterior>..<tag>` e `gh release view <tag> -R yagoramires/<app>`. Sem tag (hub, dose, pauta, deck): uma seção com o `CFBundleShortVersionString` atual e a data do último commit.
Expected: versão do topo == `CFBundleShortVersionString` de `Resources/Info.plist` em todos (hoje: aero 0.4.1, capture 0.2.0, neyzap 0.3.1).
- [ ] **Step 4: Commit** — `cd ~/Documents/personal-projects && for d in aero capture hub dose pauta deck neyzap; do git -C $d add README.md CHANGELOG.md docs 2>/dev/null; git -C $d commit -m "docs: README no modelo e CHANGELOG"; done`
- [ ] **Step 5:** Rodar a varredura da Task 3 Step 1 de novo nos 5 repos a publicar (os READMEs novos podem ter trazido termo de trabalho) → Expected: limpa.

---

### Task 5: Atualizar memórias com os caminhos novos

- [ ] **Step 1:** `grep -lE "Documents/(aero|capture|hub|dose|deck|radar|neyzap)" ~/.claude/projects/-Users-yagoramires-Documents/memory/*.md` e trocar pelos caminhos em `personal-projects` (`radar` → `pauta`), inclusive no `MEMORY.md`.
Expected: o mesmo grep não acha nada.

---

### Task 6: Publicar (checkpoint com o Yago)

- [ ] **Step 1: NeyHub** — `cd ~/Documents/personal-projects/neyhub && git add -A && git commit -m "docs: design e plano do NeyHub"` (o `git init`, `.gitignore` e LICENSE vieram da Task 3; README "em construção" no modelo vem agora, no mesmo commit).
- [ ] **Step 2:** Mostrar ao Yago o resultado final da varredura dos 5 repos e pedir **OK explícito**. Sem OK, parar.
- [ ] **Step 3: Criar e subir**

```bash
cd ~/Documents/personal-projects
for d in hub dose pauta deck neyhub; do (cd $d && gh repo create yagoramires/$d --public --source . --push); done
for d in aero capture neyzap; do git -C $d push; done
```
Expected: `gh repo view yagoramires/<d> --json visibility -q .visibility` → `PUBLIC` nos 5; `git -C <d> status -sb` sem `ahead` nos 8.

- [ ] **Step 4: Repos já públicos (aero, capture, neyzap) — só com OK explícito**

Todos os commits têm a coautoria do Claude (aero 10, capture 2, neyzap 26). Limpar exige reescrever o histórico e `git push --force` (inclusive tags: `git push --force --tags`); os releases do GitHub ficam presos ao nome da tag e continuam. Hoje os 3 têm 0 forks e 0 estrelas. Só com OK do Yago: mesmo `filter-repo --message-callback` da Task 3 Step 7, re-adicionar o `origin` (o filter-repo remove), `git push --force origin main` e `git push --force --tags`.
Expected: `gh api repos/yagoramires/<r>/commits -q '.[].commit.message' | grep -ci 'co-authored-by: claude'` → `0`; `gh release list -R yagoramires/<r>` igual ao de antes.

---

## Decisões do Yago (2026-10-25)

1. **Histórico do Pauta:** publicar com **um commit só** (opção b do Step 6 — `git checkout --orphan pub …`). Antes, guardar o histórico completo local: `git -C pauta branch historico-local main` (não vai pro GitHub; nunca dar push nessa branch).
2. **E-mail de autor no Hub:** unificar para o e-mail principal (`git config --global user.email`) com `git filter-repo --force --mailmap ../.scan/mailmap.txt` (o `--force` é necessário porque não é um clone novo; o hub não tem remote, então nada se perde) (arquivo fora do repo, uma linha `Yago Ramires <principal> <segundo>`). Conferir: `git -C hub log --format=%ae | sort -u` → só o principal.
3. **Execução:** subagent-driven-development.

# NeyHub — design

Data: 2026-10-24 · Autor: Yago Ramires (decisões) + Claude (redação e as escolhas marcadas como **[escolha do Claude]**)

## 1. Intenção

O Yago tem 7 apps Mac próprios, todos de barra de menus, espalhados em `~/Documents`. A barra de menus está lotada, cada app pede permissões do macOS por conta própria (e pede de novo com frequência), metade não tem instalador nem atualização, e nenhum tem patch notes.

O NeyHub junta tudo num lugar só: uma **loja** com a suíte de apps, onde ele instala/desinstala cada um, **usa a tela de cada app dentro do NeyHub** e decide o que aparece na barra de menus. Ao mesmo tempo, cada app continua sendo um **repositório público separado** que pode ser baixado e usado **fora** do NeyHub.

## 2. Objetivos, não-objetivos, anti-objetivos

**Objetivos**
- NeyHub: app Mac com loja (instalar, desinstalar, atualizar com patch note), tela de cada app instalado embutida na janela, modo de exibição por app, tela única de Permissões, switch "Acordado".
- Cada app com: tela de app completa (nova) + menu da barra de menus, modo de exibição escolhível, `.dmg` instalador, verificação de atualização, `CHANGELOG.md`, README padronizado, repo público.
- Todos os repos pessoais em `~/Documents/personal-projects/` (decisão 17).
- Permissão concedida uma vez vale pra sempre — inclusive depois de atualizar.

**Não-objetivos**
- `conecta-matcon` e o app de trabalho (projetos web) ficam fora do NeyHub e fora da pasta nova.
- **NeyZap** fica fora do NeyHub (decisão 15). A suíte do NeyHub são 6 apps: Aero, Capture, Hub, Dose, Pauta, Deck.
- Notarização/Developer ID da Apple (ver §11, risco R1).
- Sandbox / App Store / ExtensionKit.

**Anti-objetivos** (se acontecer, falhou mesmo "funcionando")
- Ficar pedindo permissão de novo a cada build ou atualização.
- Visual com cara de Ajustes do macOS / padrão Apple genérico.
- Avulso deixar de funcionar ou virar "versão de segunda" em relação ao plugin.
- Perder configurações/dados que o usuário já tem nos apps hoje.

## 3. Estado atual (levantado em 2026-10-24)

| App | Pasta hoje | Repo GitHub | Linhas Swift | Bundle ID | Update/release hoje |
|---|---|---|---|---|---|
| Aero (encaixe de janelas) | `aero` | yagoramires/aero (público) | 1.840 | `local.aero` | Updater + releases zip (v0.4.1) |
| Capture (prints/gravação) | `capture` | yagoramires/capture (público) | 1.093 | `local.capture` | Updater + releases zip (v0.2.0) |
| NeyZap (WhatsApp) | `neyzap` | yagoramires/neyzap (público) | 3.037 | `local.neyzap` | Updater + releases zip/dmg (v0.3.1); app com janela, não LSUIElement |
| Hub (IoT Tuya/SmartThings) | `hub` | só local (25 commits) | 5.216 | `local.hub` | nada; macOS 15+ |
| Dose (remédios) | `dose` | só local (5 commits) | 2.028 | `local.dose` | nada |
| Pauta (Slack+GitHub+Jira) | `radar` | só local (38 commits) | 4.866 | `local.pauta` | nada |
| Deck (fifine AmpliGame D6) | `deck` | **sem git** | 1.359 | `local.deck` | nada |

Comum a todos: SwiftPM com um único `executableTarget`, macOS 14+ (Hub 15+), build por `scripts/build.sh` só com Command Line Tools (sem Xcode; a macro `@State` quebra nesse build — os apps usam o contorno `@ViewState`, ver Dose/Hub). Assinatura: todos com o certificado autoassinado "Aero Local Signing", exceto NeyZap ("NeyZap Local Signing"); fallback ad-hoc (`-`) se o certificado não existir. Licença MIT (Aero, Capture, NeyZap, Dose); Hub, Pauta e Deck sem LICENSE.

Observação: no momento do levantamento, `pmset -g` mostra `SleepDisabled 1` (o Mac já está sem dormir).

## 4. Decisões do Yago

1. Um app NeyHub tipo loja; o usuário escolhe o que usar.
2. Repos continuam separados; cada app pode ser baixado fora do NeyHub.
3. "Instalar" = **baixar** do GitHub (não vem tudo embutido no NeyHub).
4. A tela do app aparece **dentro** da janela do NeyHub (não em janela separada).
5. Aceita as consequências: permissões ficam no NeyHub (o avulso tem as dele à parte); todos os plugins rodam no processo do NeyHub (um travamento derruba o NeyHub).
6. Hub, Dose, Pauta e Deck viram repos **públicos** no GitHub.
7. Instaladores, verificação de atualização, patch notes e READMEs estruturados pra todos.
8. Permissões: "aceitou uma vez, aceitou pra sempre".
9. Switch "Acordado" (não dormir com a tampa fechada) que **só desliga quando ele mandar**.
10. Visual: direção **Grafite** (mockup A): escuro, denso, um acento neon (verde-lima `#c6ff3d` no mockup), sidebar.
11. Cada app ganha uma **tela de app** de verdade além do menu; modo por app: só tela, só barra de menus, ou os dois.
12. **Tudo no tema do NeyHub** — inclusive os avulsos.
13. **Aero e Capture não ganham tela de app** — são funções de barra de menus. Para eles o modo é só "barra de menus: mostrar / esconder"; configurações e patch notes ficam no card deles na Loja. Os outros 4 (Hub, Dose, Pauta, Deck) seguem a decisão 11.
14. **Esconder o ícone nunca desliga o app.** Em qualquer app, no NeyHub ou avulso, ocultar o ícone da barra de menus mantém o app funcionando (Aero continua encaixando, Capture continua nos atalhos). **[escolha do Claude]** No avulso com ícone oculto e sem tela, abrir o app de novo (Finder/Spotlight) mostra uma janela de configurações, para o usuário não ficar sem caminho de volta.
15. **NeyZap fica fora do NeyHub** — é um app à parte, não de produtividade. Não vira plugin, não entra na Loja nem no catálogo. Não muda de tema nem de certificado; muda só de pasta (decisão 17) e ganha README no modelo + `CHANGELOG.md` como os demais.
16. **Acordado e o "Acesso remoto" do app de trabalho ficam cada um com a sua regra** (sudoers e comportamento próprios). Conflito aceito e documentado (R7).
17. **Pasta `~/Documents/personal-projects/`** com `neyhub`, os 6 apps e o `neyzap`, todos lado a lado. `conecta-matcon` e o app de trabalho não entram.
18. **Sem repo `neykit` separado:** o código comum (NeyKit) mora dentro do repo `neyhub`. Total de 8 repos: `neyhub`, os 6 apps e `neyzap`.
19. **Atualizações automáticas:** baixam sozinhas; aplicam no próximo reinício (com botão "Reiniciar agora"); nunca reinicia sozinho no meio do uso; mostra o patch note depois.

## 5. Arquitetura

### 5.1 Cada repo: miolo + duas cascas

Cada app é reorganizado no próprio `Package.swift`:
- **Miolo** (library target, ex. `AeroCore`): toda a lógica, a tela de app e o menu.
- **Avulso** (executable `Aero` → `Aero.app`): casca fina que sobe o miolo, cria a janela/ícone do Dock e/ou o item da barra conforme o modo.
- **Plugin** (biblioteca dinâmica + recursos, carregada pelo NeyHub em tempo de execução): casca fina que entrega ao NeyHub a tela de app e o menu do miolo.

O mesmo release no GitHub publica: `Aero-X.Y.Z.dmg` (instalar avulso), `Aero-X.Y.Z.zip` (atualização do avulso) e o pacote do plugin. Corpo do release = seção da versão no `CHANGELOG.md`.

### 5.2 Contrato plugin ↔ NeyHub

O NeyHub carrega o plugin (`dlopen`/`Bundle.load`) e fala com ele por um contrato pequeno e **versionado**. O que o contrato precisa cobrir:
- identidade: id (o bundle ID atual, ex. `local.aero`), nome, versão, versão do contrato;
- a tela de app (um `NSViewController`/view SwiftUI) para a área principal do NeyHub — **opcional** (Aero e Capture não têm);
- o painel de configurações exibido no card da Loja;
- o menu da barra de menus (o NeyHub cria/remove o `NSStatusItem` conforme o modo);
- ciclo de vida: iniciar (ao abrir o NeyHub, se instalado) e parar;
- permissões que o app precisa (lista), para a tela de Permissões do NeyHub;
- onde o app guarda dados/configurações (ver 5.4).

Requisito duro: o contrato **não pode depender de identidade de tipo Swift entre imagens diferentes** (um `protocol` Swift linkado estaticamente no host e no plugin gera dois tipos distintos e o `as?` falha). Caminhos aceitáveis: ponto de entrada C (`@_cdecl`) + protocolo `@objc`/seletores, ou um framework de contrato dinâmico único. Escolha do mecanismo: **builder**, desde que prove com um teste que um plugin compilado separadamente carrega e responde.

NeyHub recusa plugin com versão de contrato incompatível e mostra "precisa atualizar o NeyHub" ou "precisa atualizar o app".

### 5.3 Código compartilhado — NeyKit (dentro do repo `neyhub`, decisão 18)

> Revisão do plano (2026-10-25): dividido em `NeyKit` (só tipos-valor + contrato, linkado pelos plugins) e `NeyKitApp` (classes das cascas: Updater, Novidades, HubCheck). Classe Swift não genérica linkada no host e no plugin duplica no runtime ObjC (verificado).

Uma biblioteca `NeyKit` publicada como *library product* do próprio pacote `neyhub` (os apps dependem de `github.com/yagoramires/neyhub` por versão e usam só o produto `NeyKit`; versão da biblioteca = versão do NeyHub), com o que hoje seria copiado 6 vezes: tema Grafite (cores, tipografia, componentes base), Updater do avulso (generalizar o que Aero/Capture/NeyZap já têm), gerenciador de modo de exibição, helper de permissões, contrato do plugin. Cuidado (risco R3): classes `NSObject` duplicadas em várias imagens carregadas no mesmo processo geram conflito no runtime ObjC — o builder decide entre linkar NeyKit dinamicamente ou mantê-lo sem classes ObjC expostas.

### 5.4 Dados e configurações compartilhados entre avulso e plugin

> Revisão do plano (2026-10-25): apps que já guardam arquivos num caminho fixo (ex.: Dose em `Application Support/Dose/`) **mantêm o caminho atual** — avulso e plugin já leem o mesmo arquivo e evita migração. A regra de pasta por bundle id vale para apps novos.

Dentro do NeyHub o plugin roda no processo do NeyHub, então `UserDefaults.standard`, `Application Support` "do app" e o Chaveiro apontariam para o NeyHub. Regra: todo app passa a ler/gravar configurações em `UserDefaults(suiteName: "<bundle id do app>")`, arquivos em `~/Library/Application Support/<bundle id do app>/`. Segredos **não** vão pro Chaveiro: com certificado autoassinado ele pede senha a cada build — Hub e Pauta já saíram dele de propósito e usam `credentials.json` com permissão 0600 (`Credentials.swift`); esse é o padrão para todos **[escolha do Claude, apontada na revisão]**. Assim avulso e plugin enxergam os mesmos dados, e **nada do que o usuário já tem hoje se perde** (migrar o que estiver em outro lugar).

### 5.5 Avulso e plugin ao mesmo tempo

Não rodam juntos (dois Aeros brigariam pelas janelas, dois Captures pelos atalhos). O NeyHub detecta o avulso aberto pelo bundle ID (`NSRunningApplication`) e oferece fechá-lo antes de iniciar o plugin. **[escolha do Claude]** O avulso faz a checagem inversa: se o NeyHub estiver rodando com aquele plugin ativo, avisa e oferece abrir no NeyHub.

## 6. NeyHub — telas e comportamento

Visual Grafite (referência: mockup A em `docs/design/mockup-direcao-visual.html`; tokens no NeyKit). O NeyHub declara no próprio Info.plist o que os plugins precisam (ex.: URL scheme `hubmac://` do Hub). Nada de controles com cara de Ajustes do macOS.

**Sidebar:** marca "neyhub", Loja, Permissões, seção "Instalados" (apps cujo modo inclui "tela"), e no rodapé o switch **Acordado** sempre visível (verde quando ligado).

**Loja:** catálogo de apps em cards. Cada card: ícone, nome, descrição curta, versão instalada/disponível, e ação **Instalar / Abrir / Atualizar**. Abrir o card mostra detalhe: README resumido, patch notes (corpo dos releases), modo de exibição (Tela · Barra de menus · Os dois), Desinstalar.
- Catálogo: **[escolha do Claude]** `catalog.json` no repo `neyhub` (branch main, lido via raw.githubusercontent), com cópia embutida como fallback offline. Adicionar app novo não exige atualizar o NeyHub.
- Atualização **automática** (decisão 19): NeyHub consulta periodicamente o release mais recente de cada app instalado e dele mesmo (API pública do GitHub, sem token; espaçar consultas pra não bater no limite de 60/h) e **baixa em segundo plano**. Como código carregado não descarrega, a versão nova entra no próximo reinício do NeyHub; há um botão "Reiniciar agora". O NeyHub **nunca reinicia sozinho** no meio do uso. Após atualizar, mostra o patch note do que mudou.
- O próprio NeyHub segue a mesma regra, pelos releases do repo `neyhub`.

**Tela de app:** clicar num instalado mostra a tela de app dele na área principal, com o modo de exibição acessível no topo.

**Modo de exibição dentro do NeyHub** **[escolha do Claude]**: "Tela" = aparece na sidebar; "Barra de menus" = o NeyHub cria o ícone do app na barra; "Os dois" = ambos. Configurações sempre acessíveis pelo card na Loja, mesmo em "só barra de menus".

**Permissões:** uma tela lista tudo o que os apps instalados precisam (Acessibilidade, Gravação de Tela, Notificações, Chaveiro…), com estado (concedida / falta) e botão que abre o painel exato dos Ajustes. Nenhum plugin pede permissão no meio do uso: quando precisa e não tem, mostra estado "precisa de permissão" com link pra essa tela.

**Ciclo de vida** **[escolha do Claude]**: NeyHub abre no login (`SMAppService`) e continua rodando ao fechar a janela (os apps, ex. Aero, precisam ficar ativos); sair de verdade só por Sair. Ícone no Dock enquanto a janela está aberta.

**Acordado:**
- Liga/desliga `pmset -a disablesleep 1|0`. Na primeira vez, instala (pedindo senha uma única vez, via prompt de administrador) uma regra em `/etc/sudoers.d/neyhub` que libera **só** esses dois comandos, sem senha, para o usuário atual. Mesmo padrão já usado em outro projeto do Yago.
- Só desliga quando o usuário mandar. Fechar/sair do NeyHub **não** desliga.
- O estado mostrado vem sempre do sistema (`pmset -g`), não de um valor salvo — se alguém mudar por fora, o switch reflete.
- **[escolha do Claude]** opção nas configurações do NeyHub de mostrar o Acordado também como ícone na barra de menus (padrão: desligado).

## 7. Padronização de cada app

Para cada um dos 6 (sem NeyZap):
1. Reorganizar em miolo + avulso + plugin (§5.1) e adotar NeyKit e a regra de dados (§5.4).
2. **Tela de app** nova no tema Grafite — **só para Hub, Dose, Pauta e Deck** (decisão 13): tudo que o menu faz hoje + o que não cabe num menu (ex.: Dose — agenda e histórico; Hub — cômodos e dispositivos). **Antes de construir, mockup de cada tela para o Yago aprovar.** Aero e Capture: sem tela de app; o plugin expõe só o menu e as configurações que aparecem no card da Loja.
3. Menu da barra de menus refeito no tema Grafite (mais enxuto).
4. Avulso com os três modos (exceto Aero/Capture, que só mostram/escondem o ícone): "Tela" = ícone no Dock + janela; "Barra de menus" = como hoje (LSUIElement); "Os dois". Troca sem reinstalar.
5. Updater (avulso) no padrão NeyKit, lendo releases do próprio repo: baixa sozinho em segundo plano e aplica ao fechar/abrir o app (decisão 19).
6. `CHANGELOG.md` (formato Keep a Changelog, em pt-BR), começando com a versão atual reconstruída do histórico git.
7. README no modelo único (§8).
8. `scripts/release.sh`: build → assinar → `.dmg` + `.zip` + plugin → release no GitHub com o trecho do CHANGELOG. Release feito **localmente** (a chave de assinatura só existe neste Mac).
9. Assinatura com a identidade única (§9).
10. Hub, Pauta, Deck ganham LICENSE MIT (como os demais). Deck ganha `git init`.
11. **NeyZap** recebe só os itens 6 (CHANGELOG) e 7 (README); o resto não se aplica.

## 8. Modelo de README

Mesmo esqueleto em todos, em pt-BR: nome + uma linha do que faz · print/gif · **Instalar** (pelo NeyHub, ou `.dmg` avulso + aviso do Gatekeeper, ver R1) · Permissões que pede e por quê · Como usar · Atalhos · Modos de exibição · Atualizações · Build local (`scripts/build.sh`, `setup-signing.sh`) · Patch notes (link pro CHANGELOG) · Licença.

## 9. Permissões "uma vez, pra sempre"

O que já se sabe: todos assinam com certificado fixo, o que em tese preserva as permissões entre builds. Mesmo assim o Yago é interrompido com frequência. Hipóteses a **investigar e medir** antes de corrigir (builder):
- 6 apps separados pedindo cada um a sua (o NeyHub resolve: plugins herdam as permissões do NeyHub);
- fallback ad-hoc silencioso quando o certificado não está no Chaveiro (o build deve **falhar**, não cair pra ad-hoc);
- prompts do Chaveiro a cada build/atualização para itens guardados pelo app (já contornado em Hub e Pauta com arquivo 0600; conferir os demais);
- reconfirmação periódica de Gravação de Tela imposta pelo próprio macOS — provavelmente não eliminável, só reduzível; documentar.

Identidade única **[escolha do Claude]**: reaproveitar o certificado "Aero Local Signing" já existente para todos os 6 + NeyHub (já é o que eles usam) em vez de criar um novo — trocar de certificado faria todos perderem as permissões uma última vez. O nome do certificado não aparece pro usuário.

Bundle IDs atuais (`local.*`) **não mudam** (o macOS amarra permissões a eles). NeyHub: `local.neyhub`.

Critério de pronto: depois de conceder, rodar build novo + atualização via NeyHub + reiniciar o Mac, e nenhum pedido reaparece (exceto o periódico do macOS, se confirmado).

## 10. Pasta, repos e fases

Estrutura final:
```
~/Documents/personal-projects/
  neyhub/  aero/  capture/  hub/  dose/  pauta/  deck/
# + neyzap/ (fora do NeyHub, mas na mesma pasta — decisão 17)
```
`radar` é renomeada para `pauta` (local e no GitHub, se publicado com esse nome) **[escolha do Claude]**.

**Fase 1 — mudança e publicação**
- Mover as 7 pastas (os 6 apps + `neyzap`; os repos estão limpos) para `~/Documents/personal-projects/`. Depois: limpar e refazer os builds (`.build` guarda caminhos absolutos), conferir itens de login/atalhos apontando pro caminho antigo, atualizar as memórias do Claude que citam `~/Documents/<app>`.
- `git init` no Deck.
- Varredura de segredos e dados de trabalho em Hub, Dose, Pauta, Deck **antes** de publicar: tokens, chaves, IDs de workspace, e os dados de trabalho que aparecem no Pauta (fixtures, padrões de site/projeto) — trocar por dados fictícios, inclusive no histórico se aparecerem em commits antigos. `slack-manifest.yml` revisado.
- Criar repos públicos `hub`, `dose`, `pauta`, `deck`, `neyhub` em `yagoramires/` e fazer push. (Publicar é irreversível na prática — só depois da varredura limpa e do OK do Yago.)

**Fase 2 — NeyKit + contrato + NeyHub esqueleto**
Tema Grafite, contrato do plugin com prova de carregamento, NeyHub com sidebar, Loja lendo o catálogo, instalar/desinstalar/atualizar, Permissões, Acordado. Pilotos: Aero (plugin só de barra de menus) e Dose (plugin com tela de app), para provar os dois formatos.

**Fase 3 — os outros 6 apps**
Um por vez: mockup da tela de app (pula para Capture) → aprovação → miolo/cascas → tela + menu → release com dmg/zip/plugin. Ordem sugerida: Capture, Deck, Pauta, Hub (do mais simples ao maior; Aero e Dose já saem da fase 2).

## 11. Riscos

- **R1 — Gatekeeper para quem baixa avulso.** Sem Developer ID/notarização (US$ 99/ano), o `.dmg` baixado por outra pessoa abre com aviso de "desenvolvedor não identificado" e exige "Abrir mesmo assim". Documentar no README. Downloads feitos pelo próprio NeyHub (URLSession) não ganham quarentena.
- **R2 — Recursos do plugin.** `Bundle.module` do SwiftPM procura recursos perto do executável principal; dentro de uma dylib carregada pelo NeyHub isso pode falhar. O pacote do plugin precisa levar os recursos e o código precisa achá-los.
- **R3 — Classes duplicadas.** Ver §5.3.
- **R4 — Um processo só.** Um plugin que trava derruba todos. Aceito pelo Yago; mitigar com testes e logs por plugin.
- **R5 — Dados existentes.** A mudança para suite/pasta fixa por app (§5.4) não pode perder o que está salvo hoje — migrar e testar com dados reais.
- **R6 — Acordado esquecido ligado** esquenta e drena a bateria na mochila. Mitigação escolhida pelo Yago: só indicador bem visível; nada desliga sozinho.
- **R7 — Acordado × Acesso remoto do app de trabalho.** Os dois mexem no mesmo `pmset disablesleep`, cada um com sua regra (decisão 16). Encerrar o acesso remoto religa o sono e desfaz o Acordado sem aviso. Mitigação: o switch do Acordado lê o estado real do sistema (§6), então mostra a mudança; documentar no README do NeyHub.

## 12. Deixado para o builder

Mecanismo exato do contrato (§5.2), forma do pacote do plugin, dinâmica vs estática do NeyKit, layout fino das telas do NeyHub dentro da direção Grafite, intervalo de checagem de atualizações, formato do `catalog.json`, como extrair a seção do CHANGELOG no release.

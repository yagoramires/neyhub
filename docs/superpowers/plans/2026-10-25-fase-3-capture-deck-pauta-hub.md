# Fase 3 — Capture, Deck, Pauta e Hub no NeyHub · Plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** os quatro apps que faltam viram plugins do NeyHub, cada um nos dois formatos (avulso e plugin), com o visual Grafite. Deck, Pauta e Hub ganham tela de app. Enquanto um app não fica pronto, ele aparece na Loja como "Em breve".

**Architecture:** cada app segue o padrão dos pilotos da Fase 2, Aero e Dose (repos `aero` e `dose`, branch `neyhub`, que servem de código de referência):

- `<App>Core`: biblioteca com o app inteiro, recebendo `defaults`, `hosted` e `version` no `init`;
- `<App>`: casca avulsa, com HubCheck, Updater, WhatsNew e Presence;
- `<App>Plugin`: dylib com `@_cdecl("neyhub_plugin_v1")`.

O NeyHub ganha três coisas que estes apps pedem e os pilotos não pediam:

- um selo "Em breve" no catálogo;
- recursos (fontes, imagens) empacotados dentro do `.neyplugin`;
- encaminhamento de URL de retorno de OAuth (`hubmac://`) para o plugin dono.

**Tech Stack:** Swift 6.4 (modo de linguagem 5), SwiftPM, AppKit + SwiftUI, IOKit HID (Deck), Network.framework (Hub), apenas Command Line Tools.

**Spec:** `~/Documents/personal-projects/neyhub/docs/superpowers/specs/2026-10-24-neyhub-design.md`. Seções que valem aqui: §5, §6, §7 e a Fase 3 de §10 (ordem: Capture, Deck, Pauta, Hub; um app por vez; mockup aprovado antes de cada tela de app).

**Pré-requisito:** Fase 2 nas branches `neyhub` de `neyhub`, `aero` e `dose`. Ledger: `neyhub/.superpowers/sdd/2026-10-24-fase-2-neykit-neyhub-pilotos/progress.md`. Esta fase empilha em cima dela. A Fase 3 trabalha em branch `neyhub` em cada repo e não depende de a Fase 2 já estar publicada, porque usa `NEYHUB_PATH`.

## Global Constraints

Valem todas as Global Constraints do plano da Fase 2 (`2026-10-24-fase-2-neykit-neyhub-pilotos.md`). Destaques:

- sem `@State` e sem XCTest;
- nenhuma classe não genérica no NeyKit;
- plugin nunca linka NeyKitApp;
- assinatura "Aero Local Signing" com o leaf fixo;
- contrato v1;
- assets `<Nome>-<v>.{dmg,zip,neyplugin}`;
- `AppDefaults.forApp(id)`;
- commits sem `Co-Authored-By`;
- push, tag e release só com OK do Yago.

Além disso:

- **Bundle IDs** não mudam: `local.capture`, `local.deck`, `local.pauta`, `local.hub`.
- **Dados ficam onde estão**, com o mesmo desvio declarado do Dose:
  - Deck: `~/Library/Application Support/Deck/` (`config.json`, `icons/`);
  - Pauta: `~/Library/Application Support/Pauta/`, com `credentials.json` 0600;
  - Hub: `~/Library/Application Support/Hub/`, com `credentials.json` 0600;
  - Capture: sem arquivo próprio.

  Os `UserDefaults` não precisam de migração: `AppDefaults.forApp("local.<app>")` lê, no NeyHub, o mesmo domínio que o avulso vê como `.standard`.
- **Hospedado nunca:**
  - chama `SMAppService`, `NSApp.terminate` ou `setActivationPolicy`;
  - usa `NSApp.activate(ignoringOtherApps:)`;
  - lê `Bundle.main` para versão ou recursos;
  - define `UNUserNotificationCenter.delegate` ou chama `setNotificationCategories`;
  - chama `requestAuthorization`, `AXIsProcessTrustedWithOptions(prompt)` ou `CGRequestScreenCaptureAccess`. Quando falta permissão, chama `host.openPermissions()`.
- **Identificadores de notificação** com prefixo `local.<app>.`. As categorias vêm de `notificationCategories()`.
- **Builds e testes de aero, dose, capture, deck, pauta e hub rodam só num espelho no scratchpad.** Os apps em uso do Yago rodam de `<repo>/build/<App>.app`, e os scripts apagam essa pasta. O `build/` do neyhub é livre.
- **Hub exige macOS 15** (`LSMinimumSystemVersion` 15.0). O NeyHub continua em macOS 14. Num Mac 14, o plugin do Hub falha ao carregar e o card mostra "Precisa do macOS 15" (não "Não deu pra carregar").
- **Classes `NSObject` com nomes únicos por app**, com prefixo (`DeckAppDelegate`, `HubOAuth`, `PautaNotifier`...). Elas viram classes ObjC no mesmo processo.
- **Versões novas:** Capture 0.3.0, Deck 0.2.0, Pauta 0.2.0, Hub 0.2.0.
- **Mockup aprovado pelo Yago** antes de construir cada tela de app (Deck, Pauta, Hub) e o popover Grafite do Capture.

## Review Focus

1. **Deck hospedado e desinstalado** com o D6 conectado → o dispositivo HID tem que ser liberado no `stop()`. Com dono preso, o avulso não consegue mais abrir o D6. Esperado: depois do `stop()`, `IOHIDDeviceClose` foi chamado, o timer de 2 s parou e nenhum callback dispara. Teste na Task 3.
2. **Gravação do Capture em andamento** quando o plugin para (desinstalar, ou conflito com o avulso) → o vídeo não pode se perder. Esperado: o `stop()` encerra o `screencapture` com SIGINT (como o `⌃⌘Esc`), espera ele sair e o arquivo existe. Teste na Task 2.
3. **Retorno do OAuth do Hub** (`hubmac://callback`) com o Hub hospedado, avulso ou nenhum dos dois:
   - NeyHub recebe a URL e o Hub está carregado: entrega ao plugin;
   - nenhum plugin aceita: mostra "Nenhum app esperava este login" e não perde a URL em silêncio.

   Teste na Task 1 (roteamento) e na Task 6.
4. **Toque numa notificação do Pauta depois de reiniciar o NeyHub** → abre o link certo do Slack. Esperado: o link sai de um mapa persistido em `Application Support/Pauta/avisos.json`, com no máximo 200 entradas. Sem o id no mapa, abre o Slack. Teste na Task 4.
5. **Recurso do Hub ausente no plugin** (fonte ou logo que não foi empacotado) → nada de crash nem tela vazia. Esperado: cai na fonte do sistema e no ícone genérico, e registra no log. Teste na Task 6.

---

## Estrutura de arquivos (por app, igual aos pilotos)

```
<app>/Package.swift                 .executable(<App>) + .library(<App>Plugin, .dynamic); dependência NEYHUB_PATH
<app>/Sources/<App>Core/            app inteiro: <App>App (init(defaults:hosted:version:resources:)), views, SelfTest, Snapshots
<app>/Sources/<App>/                main.swift + AppDelegate.swift (casca: flags de CLI, HubCheck, Updater, WhatsNew, Presence)
<app>/Sources/<App>Plugin/          <App>PluginEntry.swift
<app>/Resources/plugin.json         id, name, hasScreen, permissions, binary
<app>/Resources/Bundle/             (opcional) recursos copiados no .app E no .neyplugin
<app>/scripts/{build,selftest,release}.sh   release.sh = templates/release-app.sh (só NAME/PLUGIN_PRODUCT mudam)
<app>/Info.plist                    + NeyHubAware = true
```

---

### Task 1: NeyHub — "Em breve", recursos de plugin e URL de retorno

**Files:**
- Modify: `neyhub/Sources/NeyHub/Catalog.swift`, `Views/StoreView.swift`, `catalog.json` e `Resources/catalog.json`.
- Modify: `Sources/NeyKit/Plugin.swift`, `Sources/NeyKit/Permission.swift`.
- Create: `Sources/NeyKit/PluginLocation.swift`.
- Modify: `Sources/NeyHub/AppDelegate.swift`, `HostBridge.swift`, `Resources/Info.plist`, `templates/release-app.sh` (e as cópias em `aero` e `dose`), `scripts/selftest.sh`, `SelfTest.swift`.

**Interfaces:**
- Produz:
  - `CatalogEntry.soon: Bool`: opcional no JSON; ausente = `false`.
  - `PluginLocation.folder(dso: UnsafeRawPointer) -> URL?`: a pasta do `.neyplugin`, via `dladdr`.
  - `PluginLocation.version(dso:) -> String`.
  - `PluginLocation.resources(dso:) -> URL?`: a subpasta `Resources/`.
  - `Permission.microphone`: título "Microfone", `settingsURL` `…?Privacy_Microphone`, `isGranted` via `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`.
  - `@objc optional func handleURL(_ url: URL) -> Bool` em `NeyPlugin`.
  - `PluginHost.route(_ url: URL, model:) -> Bool`.

- [ ] **Step 1: Testes.** Escrever no `SelfTest.swift` e no `NeyKitSelfTest`:
  - `Catalog.decode` aceita uma entrada sem `soon` (vira `false`) e uma com `"soon": true`;
  - card com `soon` não oferece "Instalar" (testar pela função que decide a ação do card; extrair uma função pura se ainda não existir);
  - `Permission(rawValue: "microphone")?.title == "Microfone"`;
  - `route(URL(string: "hubmac://callback?code=x")!)` entrega ao fixture que responde `true` e devolve `true`;
  - `route` sem nenhum aceitante devolve `false`;
  - `PluginLocation.version(dso:)` no fixture HelloPlugin devolve `"1.0.0"`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implementar.**
  - O card "Em breve" usa `GPill` apagado com o texto "Em breve", sem ação.
  - O catálogo ganha Capture, Deck, Pauta e Hub com `soon: true`. Resumos:
    - Capture: "Prints e gravação de tela pela barra de menus";
    - Deck: "Controle do fifine AmpliGame D6";
    - Pauta: "Slack, GitHub e Jira num lugar só";
    - Hub: "Casa conectada: Tuya, SmartThings e Android TV".
  - Info.plist do NeyHub:
    - `CFBundleURLTypes` com o esquema `hubmac` (nome `local.hub.oauth`);
    - `NSMicrophoneUsageDescription`: "Para o Capture gravar o áudio do microfone junto com a tela.";
    - `NSLocalNetworkUsageDescription`: "Para o Hub achar a Android TV na rede."
  - `application(_:open:)` chama `route`. Quando nenhum plugin aceita, mostra o alerta Grafite "Nenhum app esperava este login".
  - Template de release: se `Resources/Bundle/` existe, copiar o conteúdo para `<App>.app/Contents/Resources/` e para `<Nome>.neyplugin/Resources/`. Recopiar o template em `aero` e `dose` (o `cmp` do selftest confere).
  - Os pilotos passam a usar `PluginLocation.version` no lugar do `dladdr` próprio. É um commit em cada repo.
- [ ] **Step 4:** `scripts/selftest.sh` ok no neyhub, e selftest ok de aero e dose no espelho.
- [ ] **Step 5: Commits.** neyhub: `feat: Loja com "Em breve", recursos no plugin e retorno de login`. aero e dose: `refactor: versão do plugin pelo PluginLocation do NeyKit`.

### Task 2: Capture (só barra de menus)

**Files (repo `capture`):**
- Package.swift.
- Mover `Sources/Capture/{Log,Screencapture,AreaPicker}.swift` e a lógica do `AppDelegate.swift` para `Sources/CaptureCore/` (`CaptureApp.swift`).
- Apagar `Sources/Capture/Updater.swift`.
- Criar:
  - `Sources/Capture/{main,AppDelegate}.swift`;
  - `Sources/CapturePlugin/CapturePluginEntry.swift`;
  - `Sources/CaptureCore/{PopoverView,SettingsView,SelfTest,Snapshots}.swift`;
  - `Resources/plugin.json` (`local.capture`, `Capture`, `hasScreen:false`, `["screenRecording","microphone"]`, `libCapturePlugin.dylib`);
  - `scripts/{selftest,release}.sh`.
- Modificar: `scripts/build.sh`, `README.md`, `CHANGELOG.md` (`## [0.3.0]`), Info.plist (0.3.0, `NeyHubAware`).

**Interfaces:** `public final class CaptureApp` com `init(defaults:hosted:version:)`, `start()`, `stop()`, `setMenuBarVisible(_:)` (autosaveName `local.capture`), `makeSettings() -> NSViewController`, `onOpenPermissions`, `static selfTest()`, `static runSnapshots(into:)`. O plugin devolve `makeScreen() == nil`.

- [ ] **Step 1: Mockup do popover Grafite.** Fazer em `neyhub/docs/design/mockup-capture.html`, com os mesmos itens do menu de hoje:
  - Print, Copiar e Gravar, com o atalho nativo ao lado de cada um;
  - "Painel de captura (`⇧⌘5`)";
  - Opções.

  **O Yago aprova antes do Step 4.**
- [ ] **Step 2: Testes** (`Capture --selftest`):
  - hospedado não grava em `.standard` (defaults injetado);
  - `PopoverState` hospedado sem Sair, sem login e sem linha de atualização; avulso com os três;
  - `stop()` com um `screencapture` falso rodando (um `/bin/sleep 30` no lugar, via seam `Recorder.launch`) manda SIGINT e espera a saída (Review Focus 2);
  - sem permissão de Gravação de Tela, hospedado chama `onOpenPermissions` e não `CGRequestScreenCaptureAccess` (seam).
- [ ] **Step 3:** FAIL. Depois, reorganizar: mover sem reescrever, porque a captura tem que ficar idêntica.
- [ ] **Step 4:** Popover Grafite do mockup aprovado. "Esconder ícone" não desliga nada: os atalhos nativos do macOS continuam valendo (decisão 14).
- [ ] **Step 5:** Selftest ok no espelho, `release.sh --dry-run` com exatamente `Capture-0.3.0.{dmg,zip,neyplugin}`, `NeyHub --validate-manifest` ok. Passos manuais anotados no relatório.
- [ ] **Step 6:** Catálogo do neyhub: Capture sem `soon`. Commit capture: `feat: Capture no NeyHub (miolo + avulso + plugin)`. Commit neyhub: `feat: Capture disponível na Loja`.

### Task 3: Deck — miolo, avulso e plugin

**Files (repo `deck`):**
- Mover `Sources/Deck/{Model,D6,Log,Render,Views,Actions}.swift` e a lógica do `AppDelegate` para `Sources/DeckCore/` (`DeckApp.swift`). Apagar o `ViewState` local; usar o do NeyKit.
- Criar:
  - `Sources/Deck/{main,AppDelegate}.swift`: a casca fica com `--selftest`, `--icon` e `--snapshots`;
  - `Sources/DeckPlugin/DeckPluginEntry.swift`;
  - `Resources/plugin.json` (`local.deck`, `Deck`, `hasScreen:true`, `["accessibility"]`, `libDeckPlugin.dylib`);
  - `scripts/{selftest,release}.sh`.
- Modificar: `build.sh`, README, CHANGELOG (`## [0.2.0]`), Info.plist (0.2.0, `NeyHubAware`).
- A pasta `re/` fica fora de todos os alvos.

**Interfaces:** `public final class DeckApp`, com a mesma forma do `DoseApp`: `init(defaults:hosted:version:)`, `start`, `stop`, `setMenuBarVisible` (`local.deck`), `makeScreen()` (placeholder até a Task 4), `makeSettings()`, `static selfTest()`, `static runSnapshots(into:)`.

- [ ] **Step 1: Testes** (`Deck --selftest`). Manter os atuais e acrescentar:
  - `D6` com um dispositivo falso (seam `HIDPort`): `stop()` fecha o dispositivo, invalida o timer de 2 s e callbacks depois do `stop` não fazem nada (Review Focus 1);
  - hospedado não chama `AXIsProcessTrustedWithOptions` com prompt;
  - `PopoverState` hospedado sem Sair e sem login;
  - `Store` lê um `config.json` de exemplo numa pasta temporária.
- [ ] **Step 2:** FAIL → reorganizar. Fechar o app oficial da fifine continua igual. Ações que postam teclas usam a Acessibilidade do NeyHub quando hospedado.
- [ ] **Step 3:** Popover restilizado com os tokens Grafite. É a mesma navegação, então não precisa de mockup.
- [ ] **Step 4:** Varredura `.scan/secrets.txt` (`git grep -f`) na branch: zero. Selftest ok no espelho, dry-run com `Deck-0.2.0.{dmg,zip,neyplugin}`, manifest ok. Commit: `feat: Deck no NeyHub (miolo + avulso + plugin)`.

### Task 4: Deck — tela de app

- [ ] **Step 1: Mockup** `neyhub/docs/design/mockup-deck.html`:
  - a grade das 15 teclas do D6 em tamanho real, com a página atual;
  - o editor de tecla ao lado (ação, ícone, rótulo);
  - a troca de página;
  - o estado do dispositivo (conectado ou não);
  - o import do perfil do app oficial.

  **O Yago aprova.**
- [ ] **Step 2:** `Sources/DeckCore/Views/ScreenView.swift` conforme o mockup, reaproveitando `KeyTile` e `KeyEditor`; snapshots `screen*.png`. Teste: editar uma tecla na tela grava o `config.json` temporário pelo mesmo caminho do popover.
- [ ] **Step 3:** Selftest e dry-run ok. Catálogo: Deck sem `soon`. Commits: `feat: tela do Deck` e, no neyhub, `feat: Deck disponível na Loja`.

### Task 5: Pauta — miolo, avulso, plugin e tela

**Files (repo `pauta`):**
- Mover tudo de `Sources/Pauta/` (menos `main.swift`) para `Sources/PautaCore/`. O `AppDelegate` vira `PautaApp.swift`.
- Criar:
  - `Sources/Pauta/{main,AppDelegate}.swift`: a casca fica com `--selftest`, `--snapshots`, `--check` e `--dump`;
  - `Sources/PautaPlugin/PautaPluginEntry.swift`;
  - `Resources/plugin.json` (`local.pauta`, `Pauta`, `hasScreen:true`, `["notifications"]`, `libPautaPlugin.dylib`);
  - `scripts/{selftest,release}.sh`.
- Modificar: `build.sh`, README, CHANGELOG (`## [0.2.0]`), Info.plist.
- **Nunca** ler, mesclar ou empurrar a branch `historico-local`. O hook `pre-push` continua.

**Interfaces:** `public final class PautaApp`, com a forma do `DoseApp`, mais:
- `notificationCategories() -> Set<UNNotificationCategory>`;
- `handleNotification(identifier:actionIdentifier:)`;
- o `Notifier` com seam de central (padrão do `Notifier` do Dose).

- [ ] **Step 1: Testes.** Manter as 841 linhas atuais e acrescentar:
  - notificações com prefixo `local.pauta.`;
  - hospedado não define delegate nem pede autorização;
  - `handleNotification` sem prefixo é ignorado;
  - o mapa `avisos.json` (id → permalink, no máximo 200, os mais antigos saem primeiro) sobrevive a recriar o `PautaApp` e abre o link certo (Review Focus 4);
  - o selftest nunca escreve no `Application Support/Pauta` real (`AppPaths` injetável).
- [ ] **Step 2:** FAIL → reorganizar. A captura de token pela área de transferência continua igual.
- [ ] **Step 3: Mockup da tela** `neyhub/docs/design/mockup-pauta.html`: Slack, GitHub e Jira lado a lado ou em abas, com o que o popover mostra e o que não cabe nele. **O Yago aprova.**
- [ ] **Step 4:** `ScreenView` conforme o mockup e snapshots. Antes do commit, varredura de dados de trabalho com `~/Documents/personal-projects/.scan/work-terms.txt` e `secrets.txt` (`git grep -f`) na branch: zero ocorrências.
- [ ] **Step 5:** Selftest e dry-run ok. Catálogo: Pauta sem `soon`. Commits: `feat: Pauta no NeyHub (miolo + avulso + plugin + tela)` e, no neyhub, `feat: Pauta disponível na Loja`.

### Task 6: Hub — miolo, avulso, plugin e tela

**Files (repo `hub`):**
- Mover tudo de `Sources/Hub/` (menos `main.swift` e `DebugCLI.swift`) para `Sources/HubCore/`. O `AppDelegate` vira `HubApp.swift`.
- Mover `Resources/{AppLogos,Fonts}` para `Resources/Bundle/`.
- Criar:
  - `Sources/Hub/{main,AppDelegate}.swift`: a casca fica com o `DebugCLI` inteiro;
  - `Sources/HubPlugin/HubPluginEntry.swift`;
  - `Resources/plugin.json` (`local.hub`, `Hub`, `hasScreen:true`, `[]`, `libHubPlugin.dylib`);
  - `scripts/{selftest,release}.sh`.
- Modificar: `build.sh`, README, CHANGELOG (`## [0.2.0]`), Info.plist (0.2.0, `NeyHubAware`; mantém `hubmac`, `NSLocalNetworkUsageDescription` e o mínimo de macOS 15).

**Interfaces:**
- `public final class HubApp`: `init(defaults:hosted:version:resources: URL?)`, `start`, `stop`, `setMenuBarVisible` (`local.hub`), `makeScreen()`, `makeSettings()`, `handleURL(_ url: URL) -> Bool` (aceita só `hubmac://`), `static selfTest()`, `static render(…)`.
- `Theme.registerFonts(from: URL?)` e `AppLogo` passam a ler de `resources` em vez de `Bundle.main`.
- `@Local` é trocado pelo `@ViewState` do NeyKit.

- [ ] **Step 1: Testes.** Manter os atuais (o `✓ selftest` passa a imprimir `selftest ok`) e acrescentar:
  - `handleURL` com `hubmac://callback?code=…&state=<certo>` aceita; com `state` errado recusa; `https://…` devolve `false`;
  - `resources == nil` não quebra (fonte do sistema e ícone genérico; Review Focus 5);
  - hospedado sem Sair e sem login;
  - o `Credentials` aponta para pasta injetável no teste.
  - Teste no neyhub: `route` entrega `hubmac://` ao Hub carregado.
- [ ] **Step 2:** FAIL → reorganizar.
  - Os timers de 10 s e 12 h, o `NWBrowser` e as conexões param no `stop()`.
  - A migração antiga do Chaveiro (`SecItemCopyMatching`) só roda no avulso. Hospedado não lê o Chaveiro.
  - O tema próprio do Hub (`Theme.swift`) passa a usar os tokens do Grafite do NeyKit. Fontes e cores extras do Hub ficam como `extension Grafite` no HubCore.
- [ ] **Step 3: Mockup da tela** `neyhub/docs/design/mockup-hub.html`: cômodos e dispositivos em grade, detalhe do dispositivo ao lado, controle da TV e plano do alimentador. **O Yago aprova.**
- [ ] **Step 4:** `ScreenView` conforme o mockup e `--render screen`. Varredura de segredos (`.scan/secrets.txt`) na branch: zero.
- [ ] **Step 5:** Selftest e dry-run ok, com o `.neyplugin` contendo `Resources/Fonts` e `Resources/AppLogos`. Catálogo: Hub sem `soon`. Commits: `feat: Hub no NeyHub (miolo + avulso + plugin + tela)` e, no neyhub, `feat: Hub disponível na Loja`.

### Task 7: Publicação da Fase 3 (cada passo com OK do Yago)

Depois da publicação da Fase 2 (Task 15 do plano anterior). Vale o mesmo procedimento:

- trabalhar num clone limpo, nunca no checkout em que os apps em uso rodam;
- `--verify-tag`;
- push antes do `gh release`.

- [ ] **Step 1:** Por app, nesta ordem (Capture, Deck, Pauta, Hub):
  1. merge de `neyhub` na `main`;
  2. trocar a dependência pela URL `https://github.com/yagoramires/neyhub.git` (a versão publicada que tiver `PluginLocation` e `handleURL`);
  3. `swift build` limpo;
  4. push;
  5. `scripts/release.sh --publish` com `NEYHUB_CONFIRM_PUBLISH=yes`.
- [ ] **Step 2:** Conferir no JSON real da API: exatamente um `.zip` por release. O Capture 0.2.0 instalado oferece e instala o 0.3.0.
- [ ] **Step 3:** `catalog.json` na `main` do neyhub sem nenhum `soon`. Ponta a ponta pela Loja: instalar os quatro, conceder Gravação de Tela, Microfone e Acessibilidade uma vez só, fazer o login do Hub pelo NeyHub e reiniciar o Mac. Nenhum pedido de permissão de novo.

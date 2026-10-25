# Fase 2 — NeyKit, NeyHub e pilotos (Aero + Dose) · Plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** NeyHub v0.1.0 funcionando — loja que instala/atualiza plugins do GitHub, mostra a tela dos apps dentro da janela, controla o ícone de cada um na barra de menus, tela única de Permissões e switch Acordado — com Aero (só barra de menus) e Dose (com tela de app) publicados nos dois formatos (avulso + plugin).

**Architecture:** O repo `neyhub` é um pacote SwiftPM com três produtos: `NeyKit` (só tipos-valor + o contrato; é o que os plugins linkam), `NeyKitApp` (classes de casca: Updater, Novidades, HubCheck; só cascas avulsas e o NeyHub) e o app `NeyHub`. Cada app vira `<App>Core` + `<App>` (avulso) + `<App>Plugin` (dylib). O NeyHub carrega o dylib com `dlopen`, pega o objeto pelo símbolo C `neyhub_plugin_v1` e fala com ele só por protocolos `@objc`.

**Tech Stack:** Swift 6.4 (modo de linguagem 5), SwiftPM, AppKit + SwiftUI, só Command Line Tools, `gh`, `hdiutil`, `codesign`.

**Spec:** `~/Documents/personal-projects/neyhub/docs/superpowers/specs/2026-10-24-neyhub-design.md` — §5, §6, §7 (Aero e Dose), §9 e a Fase 2 de §10.

**Pré-requisito:** Fase 1 concluída (pastas em `personal-projects`, `yagoramires/neyhub` público, CHANGELOG e README no modelo já existem nos apps).

**Verificado em experimento (revisão de 2026-10-25):** `as? NeyPlugin` funciona com o `@objc protocol` do NeyKit linkado estaticamente no host e no dylib; `.library(type: .dynamic)` compila universal só com CLT (`swift build -c release --arch arm64 --arch x86_64 --product X` → `.build/out/Products/Release/libX.dylib`); `SecStaticCodeCheckValidity` com `certificate leaf = H"c8fc…"` aceita dylib universal assinada, recusa ad-hoc (-67050) e adulterada (-67061); `UserDefaults(suiteName: <bundle id do próprio app>)` devolve **nil**; toda classe Swift **não genérica** de um alvo vira classe ObjC e duplica ("is implemented in both") se o alvo for linkado no host e no plugin.

## Global Constraints

- macOS 14+, `swift-tools-version:6.0`, `swiftSettings: [.swiftLanguageMode(.v5)]`.
- **Proibido `@State`** (usar `@ViewState`, struct, vem do Dose `Views/Root.swift:133`). **Proibido Swift Testing/XCTest.** Testes = `--selftest` (padrão `pauta/Sources/Pauta/SelfTest.swift`), `precondition`, imprime `selftest ok`.
- **NeyKit não tem nenhuma `class` não genérica** (nem `NSObject`, nem `ObservableObject`). Classes vão para `NeyKitApp` (nunca linkado por plugin) ou para o módulo do próprio app. `scripts/selftest.sh` **falha** se o stderr tiver `is implemented in both`.
- Bundle IDs: `local.neyhub`, `local.aero`, `local.dose` — não mudam.
- Assinatura: "Aero Local Signing". Plugins são aceitos pelo requisito fixo `certificate leaf = H"c8fc5847339bf8a7c29ab0c5d1fcdaf5897ec092"`; updates de app pelo requisito `identifier "<id>" and certificate leaf = H"c8fc…"`. Build **falha** sem a identidade (`security find-identity -p codesigning | grep -q "Aero Local Signing"`), nada de fallback ad-hoc.
- Tema Grafite: fundo `#121315`, sidebar `#17181b`, borda `#24262a`, card `#1a1b1f`, borda de card `#25272c`, texto `#d8d9dc`, texto forte `#ffffff`, apagado `#6e7179`, rótulo `#5d6068`, acento `#c6ff3d`, tinta sobre acento `#111111`, Acordado `#1c2410`/`#3c5214`. Raio de card 10, janela 14. Textos em pt-BR.
- Contrato de plugin **v1**, símbolo `neyhub_plugin_v1`. O entry de um mesmo id **nunca** é chamado duas vezes no mesmo processo.
- Assets de release: `<Nome>-<v>.dmg`, `<Nome>-<v>.zip` (app), `<Nome>-<v>.neyplugin` (zip do plugin; extensão **não** é `.zip`).
- Pastas do NeyHub: `~/Library/Application Support/NeyHub/{Plugins,Staged,Incoming,Remove}`, `catalog.json` (cache), `active.json` (ids iniciados nesta sessão).
- Dados dos apps ficam onde já estão (Dose: `~/Library/Application Support/Dose/dados.json`). **Desvio declarado do spec §5.4**, que pedia pasta por bundle id: manter o caminho atual evita migração e risco de perda; avulso e plugin já leem o mesmo arquivo.
- Padrões de app (`UserDefaults`) sempre por `AppDefaults.forApp(id)`; nunca `UserDefaults(suiteName: id)!` direto.
- Checagem de atualização: 5 s depois de abrir e a cada 6 h; API pública do GitHub; `User-Agent: <Nome>/<v>`.
- O NeyHub nunca reinicia sozinho; fechar a janela não encerra; sair não desliga o Acordado.
- Desenvolvimento entre repos: `Package.swift` dos apps usa `.package(path: ProcessInfo.processInfo.environment["NEYHUB_PATH"] ?? "../neyhub")` até a Task 15; repos dos apps trabalham no checkout principal (sem worktree); se o `neyhub` estiver numa worktree, exportar `NEYHUB_PATH`.
- Commits **sem** linha `Co-Authored-By` do Claude (pedido do Yago). **Push, tag e release só na Task 15, com OK do Yago.**

## Review Focus

1. **Avulso e plugin do mesmo app rodando juntos** (ex.: Dose 0.1.0 avulso é item de login e abre depois do NeyHub) → dois processos gravando `dados.json`, doses marcadas somem, lembretes em dobro. Esperado: o NeyHub detecta o avulso **a qualquer momento** e oferece fechar; o avulso novo, se o app já roda no NeyHub, tira o próprio item de login e sai — Tasks 9, 12, 13.
2. **Atualização de plugin que não pode entrar** (contrato novo, assinatura errada, download corrompido) → o plugin que funcionava tem que continuar funcionando. Esperado: validação antes de preparar; troca com `replaceItemAt` — Task 8.
3. **Updaters já instalados** (Aero 0.4.1, Capture 0.2.0) pegam o primeiro asset `.zip`. Esperado: o release tem **exatamente um** `.zip`, conferido no `dist/` e no JSON real da API depois de publicar — Tasks 6 e 15.
4. **Sem internet ao abrir.** Esperado: catálogo do cache ou embutido, plugins instalados carregam, nada espera rede — Task 8.
5. **Acordado mudado por fora** (outro app religa o sono, `sudo pmset` no Terminal). Esperado: o switch e o ícone opcional mostram o estado real ao aparecer — Task 11.

---

## Estrutura de arquivos

```
neyhub/
  Package.swift                    produtos: NeyKit, NeyKitApp (libraries), NeyHub (executable)
  catalog.json
  Sources/NeyKit/                  SÓ tipos-valor e protocolos
    ViewState.swift  Theme.swift  AppDefaults.swift  Presence.swift
    Plugin.swift (NeyPlugin, NeyHost, PluginManifest)  PluginSignature.swift
    Release.swift  Permission.swift  NeyKitSelfTest.swift
  Sources/NeyKitApp/               classes das cascas (nunca em plugin)
    Updater.swift  WhatsNew.swift  HubCheck.swift  NeyKitAppSelfTest.swift
  Sources/NeyHub/
    main.swift  AppDelegate.swift  MainWindow.swift  HostBridge.swift
    Catalog.swift  PluginStore.swift  PluginHost.swift  Awake.swift  Notifications.swift
    Views/Sidebar.swift  StoreView.swift  AppDetailView.swift  PermissionsView.swift  AwakeSwitch.swift
    SelfTest.swift  Snapshots.swift
  Resources/Info.plist  AppIcon.icns  catalog.json
  Fixtures/HelloPlugin/
  scripts/build.sh  release.sh  selftest.sh  setup-signing.sh  changelog-section.sh
  templates/release-app.sh
```

---

### Task 1: Esqueleto do pacote, @ViewState e selftest dentro do .app

**Files:** Create `Package.swift`, `Sources/NeyKit/ViewState.swift`, `Sources/NeyKit/NeyKitSelfTest.swift`, `Sources/NeyKitApp/NeyKitAppSelfTest.swift`, `Sources/NeyHub/{main,SelfTest}.swift`, `Resources/Info.plist` (`local.neyhub`, 0.1.0), `scripts/{build,selftest,setup-signing}.sh` (setup-signing copiado do aero).

**Interfaces:**
- Produces: `public struct ViewState<Value>: DynamicProperty` (API do Dose, tudo `public`); `public enum NeyKitSelfTest { public static func run() }`; `public enum NeyKitAppSelfTest { public static func run() }`; `NeyHub --selftest [--fixture <pasta>]` → `selftest ok`.
- `scripts/selftest.sh`: `scripts/build.sh debug` (gera `build/NeyHub.app` assinado) → monta fixtures (Task 3) → roda `build/NeyHub.app/Contents/MacOS/NeyHub --selftest --fixture …` **de dentro do .app** (para `Bundle.main.bundleIdentifier == "local.neyhub"`), com stderr em arquivo → falha se o stderr contém `is implemented in both` → limpa `~/Library/Preferences/neyhub.selftest.*` e `$TMPDIR/nh-*`.

- [ ] **Step 1:** Package com `products: [.library(name: "NeyKit"), .library(name: "NeyKitApp"), .executable(name: "NeyHub")]`; `NeyKitApp` depende de `NeyKit`; `NeyHub` de ambos.
- [ ] **Step 2:** Teste em `NeyKitSelfTest`: nenhum (só o esqueleto). Em `SelfTest` do NeyHub: `precondition(Bundle.main.bundleIdentifier == "local.neyhub")` (garante que o teste roda no .app).
- [ ] **Step 3:** `build.sh` no padrão `aero/scripts/build.sh`, **sem fallback ad-hoc** (checa com `find-identity`, não `find-certificate`).
- [ ] **Step 4:** Run `scripts/selftest.sh` → `selftest ok`; `codesign -dv build/NeyHub.app 2>&1 | grep Authority` → `Aero Local Signing`.
- [ ] **Step 5:** Commit `feat: esqueleto do NeyHub e NeyKit`.

---

### Task 2: Tema Grafite

**Files:** Create `Sources/NeyKit/Theme.swift`, `Sources/NeyHub/Snapshots.swift`.

**Interfaces:**
- Produces: `public enum Grafite` (cores dos Global Constraints como `static let …: Color`: `bg, sidebar, border, card, cardBorder, text, strong, muted, label, accent, onAccent, awakeBg, awakeBorder`) + `public static func color(hex: String) -> Color?`; views (structs) `GCard<Content>`, `GPill(title:style:action:)` com `style: .primary | .ghost`, `GSwitch(isOn: Binding<Bool>)` desenhado à mão (cápsula 26×15, bolinha 11), `GSectionLabel(_:)`; `extension View { func grafiteWindow() -> some View }`. `NeyHub --snapshots <pasta>` via `ImageRenderer` (padrão `dose/Sources/Dose/Snapshots.swift`).

- [ ] **Step 1: Teste:** `color(hex: "#c6ff3d") != nil`, `color(hex: "c6ff3d") != nil`, `color(hex: "#zzz") == nil`, `color(hex: "#12345") == nil`.
- [ ] **Step 2:** FAIL (não compila). **Step 3:** implementar; nenhuma `class`. **Step 4:** `selftest ok`; `--snapshots /tmp/nh` → `components.png` igual ao mockup A. **Step 5:** Commit `feat(neykit): tema Grafite`.

---

### Task 3: Contrato v1, assinatura e prova de carregamento

**Files:** Create `Sources/NeyKit/{Plugin,PluginSignature}.swift`, `Sources/NeyHub/{PluginHost,HostBridge}.swift` (só `load` + ponte), `Fixtures/HelloPlugin/{Package.swift,Sources/HelloPlugin/Hello.swift}`.

**Interfaces:**
- Produces:
```swift
public let neyPluginContractVersion = 1

@objc public protocol NeyHost: NSObjectProtocol {
    func openPermissions()                 // leva o NeyHub para a tela de Permissões
    func log(_ message: String)
}

@objc public protocol NeyPlugin: NSObjectProtocol {
    var contractVersion: Int { get }
    func start(host: NeyHost)              // começa o trabalho de fundo; chamado uma vez por processo
    func stop()                            // tira ícone, event taps, atalhos, timers (desinstalar)
    func setMenuBarVisible(_ visible: Bool)// false REMOVE o NSStatusItem; true cria com autosaveName = id
    func makeScreen() -> NSViewController? // nil = só barra (Aero, Capture)
    func makeSettings() -> NSViewController
    @objc optional func notificationCategories() -> Set<UNNotificationCategory>
    @objc optional func handleNotification(identifier: String, actionIdentifier: String)
}

public struct PluginManifest: Codable, Equatable {
    public let id: String, name: String, version: String, contract: Int, hasScreen: Bool
    public let permissions: [String]       // Task 10 troca por [Permission]
    public let binary: String              // só nome de arquivo: sem "/" e sem ".."
    public var isValid: Bool { get }       // binary é nome simples, id/nome não vazios
}

public enum PluginSignature {
    // shortcut: certificado fixo no código; se o "Aero Local Signing" for recriado, atualizar aqui e republicar os plugins.
    public static let trustedLeaf = #"certificate leaf = H"c8fc5847339bf8a7c29ab0c5d1fcdaf5897ec092""#
    public static func isTrustedPlugin(_ binary: URL) -> Bool          // requisito trustedLeaf
    public static func isTrustedApp(_ app: URL, id: String) -> Bool    // identifier "<id>" and trustedLeaf
}

// NeyHub
enum LoadError: Error, Equatable { case manifest, signature, contractTooNew(Int), contractTooOld(Int), symbol, notAPlugin, alreadyLoaded }
struct LoadedPlugin { let manifest: PluginManifest; let plugin: NeyPlugin; let folder: URL }
enum PluginHost { static func load(folder: URL) -> Result<LoadedPlugin, LoadError> }   // guarda ids carregados; 2ª vez → .alreadyLoaded
final class HostBridge: NSObject, NeyHost { … }   // classe do módulo NeyHub (nome único)
```
- Pasta: `<Nome>.neyplugin/{manifest.json, <binary>, icon.icns}`. Entry: `@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer` → `Unmanaged.passRetained(obj).toOpaque()`; a classe do objeto mora no módulo do plugin.
- Fixture `Package.swift`: `let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()`; dependência `.package(path: root.path)` e `.product(name: "NeyKit", package: root.lastPathComponent.lowercased())` (funciona em worktree). Produto `.library(name: "HelloPlugin", type: .dynamic)`. Linka **só** `NeyKit`.

- [ ] **Step 1: Testes.** `NeyKitSelfTest`: manifest JSON decodifica; `binary: "../x"` e `"a/b"` → `isValid == false`. `SelfTest --fixture` (pastas montadas pelo `selftest.sh`: `good` assinada, `adhoc` com `codesign -s -`, `tampered` = `good` com 1 byte alterado no dylib, `future` com `contract: 2`):
```swift
guard case .success(let p) = PluginHost.load(folder: good) else { preconditionFailure("good") }
precondition(p.plugin.contractVersion == 1 && p.plugin.makeScreen() != nil)
precondition(PluginHost.load(folder: good).failure == .alreadyLoaded)
precondition(PluginHost.load(folder: adhoc).failure == .signature)
precondition(PluginHost.load(folder: tampered).failure == .signature)
precondition(PluginHost.load(folder: future).failure == .contractTooNew(2))
```
(`Result.failure` = helper de teste que devolve o erro ou nil.) Carregar `adhoc`/`tampered`/`future` **não** pode chamar `dlopen`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar `load`: manifest → `isValid` → contrato → `isTrustedPlugin` → `dlopen(RTLD_NOW)` → `dlsym` → `as? NeyPlugin`. **Step 4:** `scripts/selftest.sh` → `selftest ok` e sem `is implemented in both`. **Step 5:** Commit `feat(neykit): contrato de plugin v1 com prova de carregamento`.

---

### Task 4: Release, AppDefaults e Presence

**Files:** Create `Sources/NeyKit/{Release,AppDefaults,Presence}.swift`.

**Interfaces:**
```swift
public struct Release: Equatable {
    public let version: String, notes: String, page: URL, assets: [String: URL]
    public static func parse(_ data: Data) -> Release?        // "v0.5.0" → "0.5.0"; body → notes
    public func asset(_ name: String) -> URL?
    public static func isNewer(_ a: String, than b: String) -> Bool
    public static func latestURL(repo: String) -> URL
}
public enum AppDefaults { public static func forApp(_ id: String) -> UserDefaults }   // .standard se Bundle.main.bundleIdentifier == id
public struct Presence: Equatable {
    public var screen: Bool, menuBar: Bool
    public static func load(_ d: UserDefaults, hasScreen: Bool) -> Presence   // padrão hasScreen ? (true,true) : (false,true)
    public func save(_ d: UserDefaults)                                      // "presence.screen", "presence.menuBar"
    public func normalized(hasScreen: Bool) -> Presence                      // hasScreen && nenhum → menuBar = true; !hasScreen → screen = false
}
```
- [ ] **Step 1: Testes** (`NeyKitSelfTest`; suites temporárias removidas no fim com `removePersistentDomain`):
```swift
let r = Release.parse(Data(#"{"tag_name":"v0.5.0","html_url":"https://github.com/yagoramires/aero/releases/tag/v0.5.0","body":"### Corrigido\n- x","assets":[{"name":"Aero-0.5.0.neyplugin","browser_download_url":"https://e/p"},{"name":"Aero-0.5.0.zip","browser_download_url":"https://e/z"}]}"#.utf8))!
precondition(r.version == "0.5.0" && r.notes.hasPrefix("### Corrigido") && r.asset("Aero-0.5.0.zip")?.absoluteString == "https://e/z")
precondition(Release.isNewer("0.10.0", than: "0.9.9") && !Release.isNewer("1.0", than: "1.0.0"))
precondition(Presence(screen: false, menuBar: false).normalized(hasScreen: true) == .init(screen: false, menuBar: true))
precondition(Presence(screen: true, menuBar: false).normalized(hasScreen: false) == .init(screen: false, menuBar: false))
// save/load round-trip numa suite temporária
precondition(AppDefaults.forApp("local.neyhub") === UserDefaults.standard)   // roda dentro do .app: não pode virar suite nil
precondition(AppDefaults.forApp("local.aero") !== UserDefaults.standard)
```
- [ ] **Step 2–4:** FAIL → implementar (parse a partir de `aero/Sources/Aero/Updater.swift:73-82`) → `selftest ok`. **Step 5:** Commit `feat(neykit): release, defaults e presença`.

---

### Task 5: NeyKitApp — Updater automático, Novidades, HubCheck

**Files:** Create `Sources/NeyKitApp/{Updater,WhatsNew,HubCheck}.swift`.

**Interfaces:**
```swift
public final class Updater {
    public init(name: String, repo: String, id: String)
    public func start()                 // 5 s + a cada 6 h: <Nome>-<v>.zip → descompacta em temp → isTrustedApp(id:) → ~/Library/Application Support/<id>/Update/{<Nome>.app, notes.md, version}
    public var staged: String? { get }
    public var onChange: (() -> Void)?
    public func applyStaged() -> Bool   // em applicationWillTerminate; só se isSafeToApply; replaceItemAt(Bundle.main.bundleURL)
    public func relaunchNow()           // applyStaged + sh -c "sleep 1; open …" + terminate
    public static func isSafeToApply(staged: String, current: String) -> Bool
    public static func notesAfterUpdate(id: String, current: String) -> String?   // uma vez; usa AppDefaults.forApp(id) ("lastRunVersion")
}
public enum WhatsNew { public static func show(name: String, version: String, notes: String) }   // janela Grafite, markdown
public enum HubCheck {
    public static func isHosted(id: String) -> Bool   // NeyHub rodando (local.neyhub) && id ∈ ~/Library/Application Support/NeyHub/active.json
    public static func leaveForHub(name: String)      // SMAppService.mainApp.unregister(); alerta "O <Nome> já roda no NeyHub" [Abrir NeyHub][Sair]; termina
}
```
- Sem perguntar; falha de rede/assinatura só loga e tenta no próximo ciclo. Requisito de update **com** `identifier` (um `.app` qualquer com o mesmo certificado não passa).
- [ ] **Step 1: Testes** (`NeyKitAppSelfTest`): `isSafeToApply("0.5.0","0.4.1")`, `!isSafeToApply("0.4.1","0.4.1")`; `notesAfterUpdate` devolve o texto uma vez e depois nil (id temporário; limpar pasta e domínio); `notesAfterUpdate(id: "local.neyhub", …)` dentro do .app não quebra; `HubCheck.isHosted` com `active.json` temporário (injetar caminho num `internal static var activeURL`).
- [ ] **Step 2–4:** FAIL → implementar (reaproveitar `unpack`/`replaceItemAt` de `aero/Sources/Aero/Updater.swift`) → `selftest ok`. **Step 5:** Commit `feat(neykitapp): updater automático, novidades e hub check`.

---

### Task 6: Scripts de release e manifest do plugin

**Files:** Create `scripts/changelog-section.sh`, `templates/release-app.sh`, `scripts/release.sh` (NeyHub); Modify `Sources/NeyHub/main.swift` (`--validate-manifest <arquivo>`).

**Interfaces:**
- `changelog-section.sh <v> <CHANGELOG.md>` imprime o corpo da seção `## [<v>]`; sai 1 se não existe.
- Cada app tem `Resources/plugin.json` (`id`, `name`, `hasScreen`, `permissions`, `binary`); o script copia para o `.neyplugin` adicionando `version` (do `Info.plist`) e `contract: 1`, e valida com `NeyHub --validate-manifest` (decodifica `PluginManifest`, `isValid`).
- `release-app.sh` (lê `NAME`, `PLUGIN_PRODUCT` do topo; vazio no NeyHub): seção do CHANGELOG existe → build universal do app e do plugin → `build/<Nome>.app` e `build/<Nome>.neyplugin/` → assina tudo (falha sem identidade) → `dist/<Nome>-<v>.dmg` (`hdiutil create`, .app + link `/Applications`) → `dist/<Nome>-<v>.zip` → `dist/<Nome>-<v>.neyplugin` → **checa `ls dist/<Nome>-<v>*.zip | wc -l` == 1** → `gh release create v<v> … --notes-file`. `--dry-run` para antes do `gh`.
- [ ] **Step 1: Teste** (no `selftest.sh`): CHANGELOG temporário com 0.2.0 e 0.1.0 → `changelog-section.sh 0.2.0` == `### Corrigido\n- b`; versão inexistente sai ≠0; `--validate-manifest` aceita um manifest bom e recusa `binary: "../x"`.
- [ ] **Step 2–4:** FAIL → implementar → `selftest ok`; `scripts/release.sh --dry-run` → `dist/NeyHub-0.1.0.{dmg,zip}`, `hdiutil verify` ok. **Step 5:** Commit `build: release com dmg, zip, plugin e patch notes`.

---

### Task 7: Janela do NeyHub

**Files:** Create `Sources/NeyHub/{AppDelegate,MainWindow}.swift`, `Views/Sidebar.swift`.

**Interfaces:** `enum Route: Hashable { case store, permissions, app(String) }`; `final class HubModel: ObservableObject { @Published var route: Route; @Published var loaded: [LoadedPlugin]; @Published var problems: [String: String] }` (classe no módulo NeyHub, ok).
- Login: `SMAppService.mainApp.register()` na primeira vez (`loginItemOffered`); `applicationShouldTerminateAfterLastWindowClosed → false`; `.regular` com janela, `.accessory` sem; `applicationShouldHandleReopen` mostra a janela. Sidebar do mockup A (marca, Loja, Permissões, "Instalados" com plugins `presence.screen`, rodapé do Acordado).
- [ ] **Step 1:** snapshot `window-empty.png`. **Step 2:** implementar. **Step 3:** comparar com o mockup; `scripts/build.sh --run` → fechar janela, `pgrep -x NeyHub` continua; abrir pelo Finder reabre. **Step 4:** Commit `feat: janela e sidebar do NeyHub`.

---

### Task 8: Catálogo e PluginStore

**Files:** Create `catalog.json`, `Resources/catalog.json`, `Sources/NeyHub/{Catalog,PluginStore}.swift`, `Views/{StoreView,AppDetailView}.swift`.

**Interfaces:**
```swift
struct CatalogEntry: Codable, Equatable { let id, name, repo, summary: String; let hasScreen: Bool }
enum Catalog {
    static let remote = URL(string: "https://raw.githubusercontent.com/yagoramires/neyhub/main/catalog.json")!
    static func decode(_ data: Data) -> [CatalogEntry]?
    static func load(cache: URL, bundled: URL) -> [CatalogEntry]      // sem rede
    static func refresh(cache: URL) async -> [CatalogEntry]?
}
enum StageError: Error, Equatable { case download, manifest, contract(Int), signature }
final class PluginStore {
    init(root: URL)
    func installedFolders() -> [URL]                                       // Plugins/*.neyplugin menos os ids em Remove/
    func validate(folder: URL) -> Result<PluginManifest, StageError>       // manifest.isValid, contract == 1, isTrustedPlugin
    func install(_ e: CatalogEntry) async throws -> URL                    // baixa em Incoming/ → validate → move para Plugins/
    func stageUpdate(_ e: CatalogEntry, release: Release) async throws     // Incoming/ → validate → Staged/ (incompatível = não prepara, erro no card)
    func needsUpdate(installed: PluginManifest, latest: Release) -> Bool
    func markForRemoval(id: String)
    func applyPending()                                                    // ANTES de carregar: Staged/* → Plugins/* com replaceItemAt; apaga ids de Remove/
}
```
- `catalog.json` com Aero e Dose (texto da versão anterior do plano: `local.aero`/`yagoramires/aero`/"Encaixe de janelas estilo Windows"/`hasScreen:false`; `local.dose`/`yagoramires/dose`/"Remédios e suplementos do dia"/`hasScreen:true`).
- UI: mockup A; detalhe com resumo, patch notes (`/releases?per_page=10`), modo, `makeSettings()`, Desinstalar; faixa "Atualizações prontas — Reiniciar agora".
- [ ] **Step 1: Testes** (diretório temporário; cada pasta de teste com `manifest.json`): `decode` → 2 entradas; `load` sem cache → embutido; cache `"{"` → embutido; `Remove/local.aero` + `Plugins/Aero.neyplugin` → `applyPending` apaga; **sobrescrita**: `Plugins/Aero.neyplugin` (versão 0.5.0) + `Staged/Aero.neyplugin` (0.5.1) → `applyPending` → manifest em `Plugins/` diz 0.5.1 e `Staged/` vazio; `validate` de pasta com `contract: 2` → `.contract(2)`; `needsUpdate(0.5.0, 0.5.1) == true`, `(0.5.0, 0.5.0) == false`.
- [ ] **Step 2–4:** FAIL → implementar (abertura nunca espera rede: `load` e depois `refresh` em background) → `selftest ok`; snapshot `store.png`. **Step 5:** Commit `feat: loja com catálogo, instalação e atualização de plugins`.

---

### Task 9: PluginHost — iniciar, tela embutida, presença, conflito, desinstalar

**Files:** Modify `PluginHost.swift`, `AppDelegate.swift`, `MainWindow.swift`, `Views/AppDetailView.swift`.

**Interfaces:**
```swift
extension PluginHost {
    static func startAll(_ model: HubModel, store: PluginStore, host: HostBridge)
    static func conflict(id: String) -> NSRunningApplication?
    static func apply(_ p: Presence, to: LoadedPlugin, model: HubModel)
    static func uninstall(_ p: LoadedPlugin, store: PluginStore, model: HubModel)   // plugin.stop() já; markForRemoval; tira da sidebar
    static func problemText(_ e: LoadError) -> String
}
```
- Textos: `.signature` "Assinatura não confere — reinstale pela Loja"; `.contractTooNew` "Precisa atualizar o NeyHub"; `.contractTooOld` "Precisa atualizar o app"; `.alreadyLoaded` "Reinicie o NeyHub para reinstalar"; outros "Não deu pra carregar".
- Início: `applyPending` → `load` cada pasta → se `conflict(id)`: alerta Grafite "O <Nome> avulso está aberto. Fechar e usar pelo NeyHub?" (Fechar → `terminate()` e espera; Agora não → card "Pausado: avulso aberto", **não** inicia) → `start(host:)` → `apply(Presence.load(AppDefaults.forApp(id), hasScreen:))` → grava `active.json` com os ids iniciados (e apaga ao sair).
- **Durante o uso:** observar `NSWorkspace.didLaunchApplicationNotification`; se o bundle id lançado está em `active.json`, mesmo alerta (Review Focus 1).
- Tela: `NSViewControllerRepresentable` com `makeScreen()`, criado uma vez por id. Topo: "Tela · Barra de menus · Os dois" (ou só "Mostrar na barra de menus" se `!hasScreen`).
- [ ] **Step 1: Testes** (`--fixture`): `problemText(.contractTooNew(2)) == "Precisa atualizar o NeyHub"`; fixture `good` + `apply(.init(screen: false, menuBar: true))` → sem item na sidebar; `uninstall` chama `stop()` (o fixture conta chamadas num contador exposto pela tela) e cria `Remove/local.hello`; `conflict(id: "local.inexistente") == nil`.
- [ ] **Step 2–4:** FAIL → implementar → `scripts/selftest.sh` ok; fixture instalado à mão → aparece na sidebar e "Olá do plugin" dentro da janela. **Step 5:** Commit `feat: plugins rodando dentro do NeyHub`.

---

### Task 10: Permissões e notificações

**Files:** Create `Sources/NeyKit/Permission.swift`, `Sources/NeyHub/{Notifications.swift,Views/PermissionsView.swift}`; Modify `Plugin.swift` (`permissions: [Permission]`).

**Interfaces:**
```swift
public enum Permission: String, Codable, CaseIterable {
    case accessibility, screenRecording, notifications
    public var title: String      // "Acessibilidade", "Gravação de Tela", "Notificações"
    public var settingsURL: URL   // x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility | ?Privacy_ScreenCapture | x-apple.systempreferences:com.apple.Notifications-Settings.extension
    public func isGranted() async -> Bool
    public func request()
}
```
- `Notifications.swift`: o NeyHub é o **único** `UNUserNotificationCenter.delegate`; junta `notificationCategories()` de todos os plugins num só `setNotificationCategories`; resposta com identificador `<id>.<resto>` vai para `handleNotification` do plugin dono.
- Tela: união das permissões dos manifests; por linha título, apps que usam, estado, `GPill` "Conceder" (`request()` e depois `settingsURL`); reconsulta ao aparecer e a cada 2 s visível; ponto na sidebar se falta algo. Plugin hospedado **nunca** chama `request()` — mostra "Precisa de permissão" e chama `host.openPermissions()`.
- [ ] **Step 1: Testes:** `Permission(rawValue: "screenRecording")?.title == "Gravação de Tela"`; todo `settingsURL.scheme == "x-apple.systempreferences"`; roteamento: identificador `"local.dose.lembrete.42"` → plugin `local.dose`.
- [ ] **Step 2–4:** FAIL → implementar → `selftest ok` + `permissions.png`. **Step 5:** Commit `feat: permissões e notificações centralizadas`.

---

### Task 11: Acordado

**Files:** Create `Sources/NeyHub/Awake.swift`, `Views/AwakeSwitch.swift`.

**Interfaces:**
```swift
enum Awake {
    static func parse(pmset: String) -> Bool?
    static func sudoersLine(user: String) -> String?     // nil se user não casa ^[A-Za-z0-9._-]+$
    static func installScript(user: String) -> String?   // script único rodado como root
    static func isEnabled() -> Bool
    static func set(_ on: Bool) throws                   // sudo -n /usr/bin/pmset -a disablesleep 1|0; se pedir senha → installRule() e tenta 1 vez
    static func installRule() throws                     // osascript "do shell script <installScript> with administrator privileges"
}
```
- Linha: `<user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1`.
- `installScript`: tudo como root num só script — `t=$(mktemp)` (de root), `printf '%s\n' '<linha>' > "$t"`, `visudo -cf "$t"`, `install -m 0440 -o root -g wheel "$t" /etc/sudoers.d/neyhub`, `rm -f "$t"`. Nada gravado pelo usuário entre checar e instalar.
- Estado lido do sistema ao abrir a janela, ao acordar (`didWakeNotification`), a cada 10 s visível e **ao abrir o menu** do ícone opcional. Nada em `applicationWillTerminate` mexe no sono. Ícone opcional "Mostrar Acordado na barra de menus" (padrão desligado).
- [ ] **Step 1: Testes:** `parse(" SleepDisabled\t\t1\n") == true`, `"… 0"` → false, ausente → nil; `sudoersLine("yagoramires")` == linha exata; `sudoersLine("x ALL=(ALL) ALL #") == nil`; `installScript("x;rm") == nil`; `installScript("yagoramires")` contém `mktemp`, `visudo -cf` e `install -m 0440 -o root -g wheel` nessa ordem.
- [ ] **Step 2–4:** FAIL → implementar → `selftest ok`. Manual: ligar (senha só na 1ª vez) → `pmset -g | grep SleepDisabled` = 1; sair do NeyHub → continua 1; `sudo pmset -a disablesleep 0` → reabrir → desligado; `ls -l /etc/sudoers.d/neyhub` → `-r--r----- root wheel`. **Step 5:** Commit `feat: switch Acordado`.

---

### Task 12: Piloto Aero (só barra de menus)

**Files (repo `aero`):** Modify `Package.swift`; mover `Sources/Aero/{DragSnapper,Geometry,Hotkeys,Log,SnapAssist,Window,WindowManager}.swift` → `Sources/AeroCore/`; lógica do `AppDelegate.swift` → `Sources/AeroCore/AeroApp.swift`; Delete `Sources/Aero/Updater.swift`; Create `Sources/Aero/{main,AppDelegate}.swift` (casca), `Sources/AeroPlugin/AeroPluginEntry.swift`, `Sources/AeroCore/{SettingsView,SelfTest}.swift`, `Resources/plugin.json` (`local.aero`, `Aero`, `hasScreen:false`, `["accessibility"]`, `libAeroPlugin.dylib`), `scripts/release.sh`; Modify `scripts/build.sh` (sem ad-hoc, `find-identity`), `README.md`, `CHANGELOG.md` (`## [0.5.0]`), `Info.plist` (0.5.0).

**Interfaces:**
```swift
public final class AeroApp {
    public init(defaults: UserDefaults, hosted: Bool, version: String)
    public func start(); public func stop()
    public func setMenuBarVisible(_ visible: Bool)     // remove/cria o NSStatusItem (autosaveName "local.aero")
    public func makeSettings() -> NSViewController
    public static func selfTest()
}
```
- `Package.swift`: produtos `.executable(name: "Aero")` (`Aero` → `AeroCore` + `NeyKitApp`), `.library(name: "AeroPlugin", type: .dynamic)` (`AeroPlugin` → `AeroCore`); `AeroCore` → `NeyKit` + Carbon. Dependência pelo `NEYHUB_PATH` (Global Constraints).
- Hospedado: todo `UserDefaults.standard` vira `defaults` (`WindowManager.swift:202,206`, debug bridge); sem `AXIsProcessTrustedWithOptions(prompt: true)` (só polling); **sem** "Abrir ao iniciar sessão" no menu (mexeria no login do NeyHub); versão vem do `init` (`Log.swift:30` e o item "Aero <v>" deixam de usar `Updater.currentVersion`/`Bundle.main`); `Hotkeys.swift:27-35`: handler confere a assinatura `'Aero'` do `EventHotKeyID` e devolve `eventNotHandledErr` para atalhos que não são dele; `stop()` desregistra atalhos, para o event tap do arrasto, remove o ícone.
- Menu: popover Grafite com os itens atuais (menos "procurar atualização"). **Mockup para o Yago aprovar antes de construir popover e configurações.**
- Casca avulsa: `HubCheck.isHosted(id: "local.aero")` → `HubCheck.leaveForHub(name: "Aero")`. Senão: `AeroApp(defaults: .standard, hosted: false, version:)`, `Presence`, `Updater(name: "Aero", repo: "yagoramires/aero", id: "local.aero").start()`, `applyStaged()` ao sair, `WhatsNew`, reabrir com ícone escondido → janela com `makeSettings()`.
- [ ] **Step 1: Teste** (`Aero --selftest` = `NeyKitSelfTest.run()` + `AeroApp.selfTest()`): `WindowManager` com `defaults` injetado — chamar `save`/`load` diretamente (expor `internal` para o teste) com uma entrada falsa → aparece na suite temporária e não em `.standard`; handler de atalho com `signature != 'Aero'` devolve `eventNotHandledErr`.
- [ ] **Step 2–3:** FAIL → reorganizar (encaixe idêntico ao atual) e implementar.
- [ ] **Step 4:** `selftest ok`; avulso: arrasto e ⌘+setas; ícone escondido → encaixe continua; reabrir pelo Finder → configurações.
- [ ] **Step 5:** Plugin: `scripts/release.sh --dry-run` → `dist/Aero-0.5.0.{dmg,zip,neyplugin}` e um só `.zip`; descompactar o `.neyplugin` em `Plugins/`, fechar o avulso, abrir NeyHub → Aero ativo, sem item na sidebar, configurações no card, Acessibilidade pela tela de Permissões; abrir o avulso com o NeyHub rodando → ele tira o próprio item de login e sai; desinstalar → encaixe para na hora.
- [ ] **Step 6:** Commit `feat: Aero no NeyHub (miolo + avulso + plugin)` (sem push — Task 15).

---

### Task 13: Piloto Dose (com tela de app)

**Files (repo `dose`):** Modify `Package.swift`; mover `Sources/Dose/{Format,Log,Model,Reminders,Store,Snapshots}.swift` e `Views/` → `Sources/DoseCore/` (apagar a `ViewState` local, usar a do NeyKit); lógica do `AppDelegate.swift` → `Sources/DoseCore/DoseApp.swift`; Create `Sources/Dose/{main,AppDelegate}.swift`, `Sources/DosePlugin/DosePluginEntry.swift`, `Sources/DoseCore/{Views/ScreenView,SettingsView,SelfTest}.swift`, `Resources/plugin.json` (`local.dose`, `Dose`, `hasScreen:true`, `["notifications"]`, `libDosePlugin.dylib`), `scripts/release.sh`; Modify `scripts/build.sh`, `README.md`, `CHANGELOG.md`, `Info.plist`.

**Interfaces:**
```swift
public final class DoseApp {
    public init(defaults: UserDefaults, hosted: Bool, version: String)
    public func start(); public func stop()
    public func setMenuBarVisible(_ visible: Bool)     // autosaveName "local.dose"
    public func makeScreen() -> NSViewController
    public func makeSettings() -> NSViewController
    public func notificationCategories() -> Set<UNNotificationCategory>
    public func handleNotification(identifier: String, actionIdentifier: String)
    public static func runSnapshots(into: URL)          // a casca chama em --snapshots
    public static func selfTest()
}
```
- `Store.defaultURL` não muda. Hospedado: `loginItemOffered` e o toggle "Abrir ao iniciar" (`ItemsView.swift:38`) somem; `Reminders.refreshPermission` **não** chama `requestAuthorization` (só consulta; falta → `host.openPermissions()`); `center.delegate` e `setNotificationCategories` **não** são tocados pelo Dose hospedado (o NeyHub faz, Task 10); identificadores de notificação com prefixo `local.dose.`.
- **Tela de app:** mockup Grafite (agenda do dia + histórico + itens, a partir de `TodayView`/`HistoryView`/`ItemsView`/`LogView`) **aprovado pelo Yago antes de construir**. Popover refeito no Grafite, mesma navegação.
- Avulso: 3 modos via `Presence` sem reiniciar; mesma casca da Task 12 (`HubCheck`, `Updater(name: "Dose", repo: "yagoramires/dose", id: "local.dose")`, `applyStaged`, `WhatsNew`).
- [ ] **Step 1: Teste** (`Dose --selftest`): hospedado não grava `loginItemOffered` em `.standard`; `Store(url:)` de um `dados.json` de exemplo carrega N itens; `handleNotification` com identificador sem prefixo `local.dose.` é ignorado.
- [ ] **Step 2–3:** FAIL → reorganizar/implementar (popover atual idêntico; `--snapshots` continua).
- [ ] **Step 4:** `selftest ok`; `--snapshots` → `screen.png` = mockup aprovado; 3 modos; notificação de teste chega.
- [ ] **Step 5: Migração do Dose 0.1.0 em uso** (é item de login e não conhece o NeyHub): fechar o avulso; desligar "Abrir ao iniciar" nele (ou instalar o avulso novo, que sai sozinho quando hospedado); conferir `sfltool dumpbtm | grep local.dose` sem entrada habilitada; **cópia de segurança** `cp ~/Library/Application\ Support/Dose/dados.json ~/Library/Application\ Support/Dose/dados.backup-$(date +%F).json`.
- [ ] **Step 6:** Plugin pelo NeyHub: Dose na sidebar, tela dentro da janela, itens reais aparecem, lembrete chega como NeyHub; marcar uma dose → `dados.json` atualizado; reiniciar NeyHub → dose continua marcada.
- [ ] **Step 7:** Commit `feat: Dose no NeyHub (miolo + avulso + plugin)` (sem push).

---

### Task 14: Atualizações automáticas do NeyHub e dos plugins

**Files:** Modify `AppDelegate.swift`, `PluginStore.swift`, `README.md`, `CHANGELOG.md` do NeyHub.

- Updater do próprio NeyHub (`Updater(name: "NeyHub", repo: "yagoramires/neyhub", id: "local.neyhub")`); a cada 6 h, para cada plugin instalado: `latest` → `needsUpdate` → `stageUpdate`. "Reiniciar agora" = `applyStaged` + relaunch (plugins entram pelo `applyPending` no início). Pós-update: `WhatsNew` com as notas do NeyHub e de cada plugin atualizado.
- [ ] **Step 1: Teste:** fluxo de update com servidor falso (`URLProtocol` de teste): release 0.5.1 com `.neyplugin` de `contract: 2` → `stageUpdate` falha com `.contract(2)` e `Plugins/Aero.neyplugin` 0.5.0 continua intacto.
- [ ] **Step 2–4:** FAIL → implementar → `selftest ok`. **Step 5:** Commit `feat: atualizações automáticas`.

---

### Task 15: Publicação (ordem fixa, cada passo com OK do Yago)

- [ ] **Step 1:** NeyHub: `CHANGELOG` 0.1.0, `git tag v0.1.0`, `git push --tags`, `scripts/release.sh` (só NeyHub; `catalog.json` em `main`).
- [ ] **Step 2:** Aero e Dose: trocar a dependência para `.package(url: "https://github.com/yagoramires/neyhub.git", from: "0.1.0")`, `swift build` limpo, commit, `git push`, `scripts/release.sh`.
- [ ] **Step 3:** Conferir no JSON real: `gh api repos/yagoramires/aero/releases/latest -q '[.assets[].name | select(endswith(".zip"))] | length'` → `1` (idem dose) — Review Focus 3. Instalar `Aero-0.4.1.zip` antigo num lugar temporário e confirmar que ele oferece e instala o 0.5.0.
- [ ] **Step 4: Ponta a ponta** apagando `~/Library/Application Support/NeyHub`: baixar `NeyHub-0.1.0.dmg` → instalar → Loja com Aero e Dose → instalar → Aero encaixa, Dose na sidebar com dados reais → esconder ícone do Aero → continua → permissões concedidas uma vez → rebuild + reinício do Mac → nenhum pedido de novo.
- [ ] **Step 5: Medição do §9:** durante a ponta a ponta e uma semana de uso, anotar em `docs/permissoes.md` cada pedido de permissão/Chaveiro/"item em segundo plano" que aparecer (quando, qual app, o que disparou). Isso alimenta a Fase 3.

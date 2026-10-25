import AppKit
import CryptoKit
import NeyKit
import NeyKitApp
import UserNotifications

/// `NeyHub --selftest [--fixture <pasta>]` roda tudo e imprime "selftest ok". Precisa rodar de dentro do .app.
enum SelfTest {
    @MainActor static func run(fixture: URL?) {
        precondition(Bundle.main.bundleIdentifier == "local.neyhub", "selftest fora do .app")
        NeyKitSelfTest.run()
        NeyKitAppSelfTest.run()
        signature()
        catalog()
        store()
        notifications()
        awake()
        lifecycle()
        if let fixture { plugins(fixture); storeInstall(fixture); storeUpdates(fixture) } else { FileHandle.standardError.write(Data("sem --fixture: pulando carga de plugins\n".utf8)) }
    }

    static func awake() {
        precondition(Awake.parse(pmset: " SleepDisabled\t\t1\n") == true)
        precondition(Awake.parse(pmset: " SleepDisabled\t\t0\n") == false)
        precondition(Awake.parse(pmset: " sleep 1\n displaysleep 10\n") == nil)
        let line = "yagoramires ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        precondition(Awake.sudoersLine(user: "yagoramires") == line)
        precondition(Awake.sudoersLine(user: "x ALL=(ALL) ALL #") == nil && Awake.sudoersLine(user: "") == nil)
        precondition(Awake.installScript(user: "x;rm") == nil)
        let script = Awake.installScript(user: "yagoramires")!
        let at = ["/usr/bin/mktemp /private/tmp/neyhub.XXXXXX", "visudo -cf", "install -m 0440 -o root -g wheel"].map { script.range(of: $0)?.lowerBound }
        precondition(!at.contains { $0 == nil } && at[0]! < at[1]! && at[1]! < at[2]!)
        precondition(script.contains("'\(line)'"))
        // O literal do AppleScript não pode ter aspa sem escape (senão o script de root vira outro comando).
        let src = Awake.appleScript(for: script)
        let head = "do shell script \"", tail = "\" with administrator privileges"
        precondition(src.hasPrefix(head) && src.hasSuffix(tail))
        let literal = src.dropFirst(head.count).dropLast(tail.count)
        var escaped = false
        for c in literal {
            precondition(escaped || c != "\"", "aspa sem escape")
            escaped = !escaped && c == "\\"
        }
        precondition(!escaped)
    }

    @MainActor static func notifications() {
        let ids = ["local.dose", "local.aero", "local.dosex"]
        precondition(Notifications.owner(of: "local.dose.lembrete.42", among: ids) == "local.dose")
        precondition(Notifications.owner(of: "local.dosex.1", among: ids) == "local.dosex")
        precondition(Notifications.owner(of: "local.dose", among: ids) == nil)       // sem "." + resto
        precondition(Notifications.owner(of: "local.doser.1", among: ids) == nil)    // prefixo sem ponto não casa
        precondition(Notifications.owner(of: "x.local.dose.1", among: ids) == nil)
        precondition(Notifications.owner(of: "local.dose.a", among: ["local", "local.dose"]) == "local.dose") // o mais longo vence

        let a = UNNotificationCategory(identifier: "lembrete", actions: [], intentIdentifiers: [])
        let b = UNNotificationCategory(identifier: "lembrete", actions: [], intentIdentifiers: [], options: [.customDismissAction])
        let c = UNNotificationCategory(identifier: "outra", actions: [], intentIdentifiers: [])
        let merged = Notifications.merge([("local.dose", [a]), ("local.aero", [b, c])])
        precondition(merged.map(\.identifier).sorted() == ["lembrete", "outra"])
        precondition(merged.first { $0.identifier == "lembrete" }?.options == [])    // colisão: o primeiro plugin ganha

        let model = HubModel(store: PluginStore(root: temp("perm")))
        func manifest(_ id: String, _ perms: String) -> PluginManifest {
            try! JSONDecoder().decode(PluginManifest.self, from: Data(
                #"{"id":"\#(id)","name":"\#(id)","version":"1.0.0","contract":1,"hasScreen":false,"permissions":\#(perms),"binary":"l.dylib"}"#.utf8))
        }
        model.installed["a"] = manifest("a", #"["notifications","accessibility"]"#)
        model.installed["b"] = manifest("b", #"["accessibility"]"#)
        let users = model.permissionUsers
        precondition(users.map(\.permission) == [.accessibility, .notifications] && users[0].apps == ["a", "b"] && users[1].apps == ["a"])
        precondition(!model.missingPermission)                                       // ainda não consultado
        model.granted = [.accessibility: true, .notifications: true]
        precondition(!model.missingPermission)
        model.granted[.notifications] = false
        precondition(model.missingPermission)
        model.granted[.notifications] = nil; model.installed["a"] = nil; model.granted[.screenRecording] = false
        precondition(!model.missingPermission)                                       // negada, mas ninguém usa

        let bridge = HostBridge()
        var opened = 0
        bridge.onOpenPermissions = { opened += 1 }
        bridge.openPermissions()
        precondition(opened == 1)
    }

    static func signature() {
        precondition(PluginSignature.isTrustedApp(Bundle.main.bundleURL, id: "local.neyhub"))
        precondition(!PluginSignature.isTrustedApp(Bundle.main.bundleURL, id: "local.aero"))
        precondition(!PluginSignature.isTrustedApp(Bundle.main.bundleURL, id: #"x" or anchor apple"#))
    }

    /// Pastas montadas pelo scripts/selftest.sh: good (assinada), adhoc, tampered, future (contract 2).
    @MainActor static func plugins(_ dir: URL) {
        func folder(_ name: String) -> URL { dir.appendingPathComponent("\(name)/Hello.neyplugin") }
        let good = folder("good")
        let (model, root) = installFromStore(dir)
        let p = model.loaded[0]
        precondition(p.plugin.contractVersion == 1 && p.plugin.makeScreen() != nil)
        precondition(PluginHost.dlopenCount == 1)
        precondition(PluginHost.load(folder: good).failure == .alreadyLoaded && PluginHost.load(folder: p.folder).failure == .alreadyLoaded)
        precondition(PluginHost.load(folder: folder("adhoc")).failure == .signature)
        precondition(PluginHost.load(folder: folder("tampered")).failure == .signature)
        precondition(PluginHost.load(folder: folder("future")).failure == .contractTooNew(2))
        precondition(PluginHost.load(folder: dir.appendingPathComponent("nada.neyplugin")).failure == .manifest)
        precondition(PluginHost.dlopenCount == 1, "dlopen chamado para plugin rejeitado")

        // Mesmo arquivo (hardlink) sob outro id: recusado antes do dlopen, senão o entry rodaria de novo.
        let fm = FileManager.default
        let other = temp("link").appendingPathComponent("Outro.neyplugin")
        try! fm.createDirectory(at: other, withIntermediateDirectories: true)
        try! Data(#"{"id":"local.outro","name":"Outro","version":"1.0.0","contract":1,"hasScreen":true,"permissions":[],"binary":"libHelloPlugin.dylib"}"#.utf8)
            .write(to: other.appendingPathComponent("manifest.json"))
        try! fm.linkItem(at: p.folder.appendingPathComponent("libHelloPlugin.dylib"), to: other.appendingPathComponent("libHelloPlugin.dylib"))
        precondition(PluginHost.load(folder: other).failure == .alreadyLoaded && PluginHost.dlopenCount == 1)

        hosting(p, model: model, root: root)
    }

    /// Presença, tela embutida e desinstalar com o plugin já iniciado pela Loja (start/stop uma vez só).
    @MainActor static func hosting(_ p: LoadedPlugin, model: HubModel, root: URL) {
        let fm = FileManager.default
        precondition(PluginHost.problemText(.contractTooNew(2)) == "Precisa atualizar o NeyHub")
        precondition(PluginHost.problemText(.signature) == "Assinatura não confere — reinstale pela Loja")
        precondition(PluginHost.problemText(.contractTooOld(0)) == "Precisa atualizar o app")
        precondition(PluginHost.problemText(.alreadyLoaded) == "Reinicie o NeyHub para reinstalar")
        precondition(PluginHost.problemText(.symbol) == "Não deu pra carregar")
        precondition(PluginHost.conflict(id: "local.inexistente") == nil)
        // Avulso com NeyHubAware resolve o conflito sozinho (HubCheck): o NeyHub não empilha o alerta dele.
        func fakeApp(_ info: [String: Any]) -> URL {
            let app = temp("aware").appendingPathComponent("A.app")
            try! fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            precondition(NSDictionary(dictionary: info).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true))
            return app
        }
        precondition(PluginHost.handlesConflictItself(fakeApp(["CFBundleIdentifier": "local.x", "NeyHubAware": true])))
        precondition(!PluginHost.handlesConflictItself(fakeApp(["CFBundleIdentifier": "local.x"])))
        precondition(!PluginHost.handlesConflictItself(fakeApp(["CFBundleIdentifier": "local.x", "NeyHubAware": "yes"])))
        precondition(!PluginHost.handlesConflictItself(nil))

        defer { try? fm.removeItem(at: root) }
        let store = model.store, host = model.host
        func count(_ key: String) -> Int? { (p.plugin as AnyObject).value(forKey: key) as? Int }
        func active() -> [String]? { try? JSONDecoder().decode([String].self, from: Data(contentsOf: root.appendingPathComponent("active.json"))) }

        // Sem tela: pedir tela não liga a tela nem põe na sidebar (ícone escondido é permitido: o app segue rodando).
        let noScreen = HubModel(store: store)
        let m = p.manifest
        let barManifest = try! JSONDecoder().decode(PluginManifest.self, from: Data(
            #"{"id":"\#(m.id)","name":"\#(m.name)","version":"1.0.0","contract":1,"hasScreen":false,"permissions":[],"binary":"\#(m.binary)"}"#.utf8))
        let bar = LoadedPlugin(manifest: barManifest, plugin: p.plugin, folder: p.folder)
        noScreen.loaded = [bar]
        PluginHost.apply(.init(screen: true, menuBar: false), to: bar, model: noScreen)
        precondition(noScreen.presences[m.id] == Presence(screen: false, menuBar: false) && noScreen.sidebarApps.isEmpty)
        precondition(count("menuBarCalls") == 2)

        PluginHost.apply(.init(screen: false, menuBar: true), to: p, model: model)
        precondition(model.sidebarApps.isEmpty, "só barra de menus não vai para a sidebar")
        precondition(count("menuBarCalls") == 3)
        PluginHost.apply(.init(screen: true, menuBar: true), to: p, model: model)
        precondition(model.sidebarApps.map(\.manifest.id) == ["local.hello"])
        let screen = model.screen(for: p)
        precondition(screen != nil && model.screen(for: p) === screen, "tela recriada")

        // Plugin pede a própria tela (NeyHost.showScreen): com tela vai para ela; sem tela, para o card na Loja.
        var asked: [String] = []
        host.onShowScreen = { asked.append($0); model.showScreen($0) }
        model.route = .permissions
        (host as NeyHost).showScreen?(id: "local.hello")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05)) // a ponte entrega na fila principal
        precondition(asked == ["local.hello"] && model.route == .app("local.hello"), "showScreen não levou à tela")
        model.route = .permissions
        model.showScreen("local.ninguem")
        precondition(model.route == .permissions && model.detail == nil, "id desconhecido mudou a rota")
        noScreen.route = .permissions
        noScreen.showScreen(m.id)
        precondition(noScreen.route == .store && noScreen.detail == m.id, "sem tela devia abrir o card")

        model.route = .app("local.hello")
        PluginHost.uninstall(p, store: store, model: model)
        precondition(count("stopCount") == 1)
        precondition(fm.fileExists(atPath: root.appendingPathComponent("Remove/local.hello").path))
        precondition(model.loaded.isEmpty && model.sidebarApps.isEmpty && model.route == .store)
        precondition(active() == [], "active.json não tirou o desinstalado")
        // Desinstalar de novo (já fora de `loaded`): não chama stop() outra vez e limpa o "Pausado" do card.
        model.problems["local.hello"] = PluginHost.paused
        model.uninstall("local.hello")
        precondition(count("stopCount") == 1 && model.problems["local.hello"] == nil)
    }
}

extension SelfTest {
    /// Instalar pela Loja carrega e inicia na hora (primeira e única carga do fixture neste processo).
    @MainActor static func installFromStore(_ fixture: URL) -> (HubModel, URL) {
        let root = temp("loja"), assets = temp("loja-assets")
        let zip = zipFixture(fixture, "good", into: assets, as: "Hello-1.0.0.neyplugin")
        let latest = assets.appendingPathComponent("latest.json")
        try! Data(#"{"tag_name":"v1.0.0","html_url":"https://e","assets":[{"name":"Hello-1.0.0.neyplugin","browser_download_url":"\#(zip.absoluteString)"}]}"#.utf8).write(to: latest)
        let store = PluginStore(root: root)
        store.latestURL = { _ in latest }
        let model = HubModel(store: store)
        var registered = 0
        model.registerCategories = { registered += 1 }
        let hello = CatalogEntry(id: "local.hello", name: "Hello", repo: "x/hello", summary: "", hasScreen: true)
        model.install(hello)
        let deadline = Date().addingTimeInterval(10)
        while model.busy.contains(hello.id), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        precondition(model.loaded.map(\.manifest.id) == ["local.hello"], "instalar pela Loja não iniciou o plugin: \(model.problems)")
        // Ponte host↔plugin atravessa as duas imagens; contadores lidos por KVC (a classe mora no plugin).
        let plugin = model.loaded[0].plugin as AnyObject
        precondition(model.host.messages == ["Olá do plugin"] && PluginHost.dlopenCount == 1, "start não rodou uma vez")
        precondition(plugin.value(forKey: "menuBarCalls") as? Int == 1 && plugin.value(forKey: "stopCount") as? Int == 0, "begin não aplicou a presença")
        let active = try? JSONDecoder().decode([String].self, from: Data(contentsOf: root.appendingPathComponent("active.json")))
        precondition(active == ["local.hello"], "active.json sem o iniciado")
        precondition(registered == 1 && model.problems.isEmpty && model.installed["local.hello"] != nil, "categorias/card depois de instalar")
        try? FileManager.default.removeItem(at: assets)
        return (model, root)
    }

    /// Pausa por avulso aberto, volta ao fechar, pasta quebrada e menu principal. Plugin falso: o fixture só carrega uma vez.
    @MainActor static func lifecycle() {
        let fm = FileManager.default
        let root = temp("ciclo")
        defer { try? fm.removeItem(at: root) }
        let model = HubModel(store: PluginStore(root: root))
        var registered = 0
        model.registerCategories = { registered += 1 }
        func fake(_ id: String) -> (FakePlugin, LoadedPlugin) {
            let m = try! JSONDecoder().decode(PluginManifest.self, from: Data(
                #"{"id":"\#(id)","name":"Falso","version":"1.0.0","contract":1,"hasScreen":false,"permissions":[],"binary":"x.dylib"}"#.utf8))
            let f = FakePlugin()
            return (f, LoadedPlugin(manifest: m, plugin: f, folder: root))
        }
        // Nenhum app roda com esses ids: para o resume, o avulso "fechou".
        let (a, pa) = fake("local.falso.a"), (b, pb) = fake("local.falso.b"), (c, pc) = fake("local.falso.c")
        PluginHost.pause(pa, model: model)
        PluginHost.pause(pb, model: model)
        model.store.markForRemoval(id: "local.falso.b") // desinstalado enquanto pausado: não começa
        precondition(model.problems["local.falso.a"] == PluginHost.paused && a.starts == 0 && model.loaded.isEmpty)
        PluginHost.resume(model)
        precondition(a.starts == 1 && b.starts == 0 && model.loaded.map(\.manifest.id) == ["local.falso.a"], "pausado não começou")
        precondition(model.problems["local.falso.a"] == nil && registered == 1, "begin sem categorias")
        PluginHost.resume(model)
        precondition(a.starts == 1, "começou duas vezes")
        // Parado em uso: nunca começa de novo; o card passa a pedir reinício.
        PluginHost.begin(pc, model: model)
        PluginHost.stopForConflict(pc, model: model)
        precondition(c.stops == 1 && model.problems["local.falso.c"] == PluginHost.paused && !model.loaded.contains { $0.manifest.id == "local.falso.c" })
        PluginHost.resume(model)
        precondition(c.starts == 1 && model.problems["local.falso.c"] == PluginHost.restartToResume, "parado não pediu reinício")

        // Manifest ilegível: problema pelo nome da pasta, card próprio, Remover apaga sem carregar nada.
        let dl = PluginHost.dlopenCount
        let bad = root.appendingPathComponent("Plugins/Quebrado.neyplugin")
        try! fm.createDirectory(at: bad, withIntermediateDirectories: true)
        try! Data("{".utf8).write(to: bad.appendingPathComponent("manifest.json"))
        PluginHost.start(folder: bad, model: model)
        precondition(model.brokenFolders == ["Quebrado.neyplugin"] && PluginHost.dlopenCount == dl)
        model.removeBroken("Quebrado.neyplugin")
        precondition(!fm.fileExists(atPath: bad.path) && model.brokenFolders.isEmpty)
        precondition(!model.store.removeBroken("../Plugins.neyplugin") && !model.store.removeBroken("x"))

        // Menu principal: ⌘Q pelo terminate (applicationWillTerminate apaga o active.json), edição pelos seletores padrão.
        let items = AppDelegate.mainMenu().items.flatMap { $0.submenu?.items ?? [] }
        let quit = items.first { $0.keyEquivalent == "q" }
        precondition(quit?.action == #selector(NSApplication.terminate(_:)) && quit?.keyEquivalentModifierMask == .command)
        let actions = Set(items.compactMap { $0.action.map(NSStringFromSelector) })
        precondition(actions.isSuperset(of: ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:", "performClose:", "performMiniaturize:"]), "\(actions)")
        precondition(items.first { $0.action == Selector(("redo:")) }?.keyEquivalentModifierMask == [.command, .shift])
    }

    /// Pasta temporária `$TMPDIR/nh-<nome>` limpa; o selftest.sh apaga nh-* no fim.
    static func temp(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nh-\(name)-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func writeManifest(_ folder: URL, id: String = "local.aero", name: String = "Aero", version: String = "0.5.0", contract: Int = 1) {
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"id":"\#(id)","name":"\#(name)","version":"\#(version)","contract":\#(contract),"hasScreen":false,"permissions":[],"binary":"lib.dylib"}"#
        try! Data(json.utf8).write(to: folder.appendingPathComponent("manifest.json"))
    }

    static func catalog() {
        let fm = FileManager.default
        let dir = temp("catalog")
        defer { try? fm.removeItem(at: dir) }
        let repoCatalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../catalog.json")
        let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json") ?? repoCatalog
        let entries = Catalog.decode(try! Data(contentsOf: bundled))!
        precondition(entries.count == 2)
        precondition(entries[0] == CatalogEntry(id: "local.aero", name: "Aero", repo: "yagoramires/aero", summary: "Encaixe de janelas estilo Windows", hasScreen: false))
        precondition(entries[1] == CatalogEntry(id: "local.dose", name: "Dose", repo: "yagoramires/dose", summary: "Remédios e suplementos do dia", hasScreen: true))
        let cache = dir.appendingPathComponent("catalog.json")
        precondition(Catalog.load(cache: cache, bundled: bundled) == entries, "sem cache → embutido")
        try! Data("{".utf8).write(to: cache)
        precondition(Catalog.load(cache: cache, bundled: bundled) == entries, "cache quebrado → embutido")
        try! Data(#"[{"id":"local.x","name":"X","repo":"a/x","summary":"s","hasScreen":true}]"#.utf8).write(to: cache)
        precondition(Catalog.load(cache: cache, bundled: bundled).map(\.id) == ["local.x"], "cache bom ganha")
        // Entrada com id/repo perigoso some; o resto fica.
        let mixed = Catalog.decode(Data(#"[{"id":"../x","name":"X","repo":"a/x","summary":"","hasScreen":true},{"id":"local.y","name":"Y","repo":"a/y?x=1","summary":"","hasScreen":true},{"id":"local.z","name":"Z","repo":"a/z","summary":"","hasScreen":false}]"#.utf8))!
        precondition(mixed.map(\.id) == ["local.z"])
        precondition(Catalog.decode(Data("{".utf8)) == nil)

        let list = Catalog.parseReleases(Data(####"[{"tag_name":"v0.5.1","html_url":"https://e/1","body":"### Corrigido\n- **b**"},{"tag_name":"v0.5.0","html_url":"https://e/0","body":"a"},{"x":1}]"####.utf8))
        precondition(list.map(\.version) == ["0.5.1", "0.5.0"])
        precondition(Catalog.releasesURL(repo: "yagoramires/aero").absoluteString == "https://api.github.com/repos/yagoramires/aero/releases?per_page=10")
    }

    static func store() {
        let fm = FileManager.default
        let root = temp("store")
        defer { try? fm.removeItem(at: root) }
        let store = PluginStore(root: root)
        let plugins = root.appendingPathComponent("Plugins"), staged = root.appendingPathComponent("Staged")
        func version(_ folder: URL) -> String? { PluginStore.manifest(at: folder)?.version }

        // Remoção: marcador por id, pasta por nome do manifest.
        writeManifest(plugins.appendingPathComponent("Aero.neyplugin"))
        writeManifest(plugins.appendingPathComponent("Dose.neyplugin"), id: "local.dose", name: "Dose")
        precondition(store.installedFolders().map(\.lastPathComponent).sorted() == ["Aero.neyplugin", "Dose.neyplugin"])
        store.markForRemoval(id: "local.aero")
        store.markForRemoval(id: "../fora") // id inseguro: ignorado
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("fora").path))
        precondition(store.installedFolders().map(\.lastPathComponent) == ["Dose.neyplugin"])
        store.applyPending()
        precondition(!fm.fileExists(atPath: plugins.appendingPathComponent("Aero.neyplugin").path), "removido não apagado")
        precondition(fm.fileExists(atPath: plugins.appendingPathComponent("Dose.neyplugin").path))
        precondition((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("Remove").path))?.isEmpty ?? true)

        // Sobrescrita: Staged → Plugins com replaceItemAt.
        writeManifest(plugins.appendingPathComponent("Aero.neyplugin"), version: "0.5.0")
        writeManifest(staged.appendingPathComponent("Aero.neyplugin"), version: "0.5.1")
        store.applyPending()
        precondition(version(plugins.appendingPathComponent("Aero.neyplugin")) == "0.5.1", "não sobrescreveu")
        precondition(try! fm.contentsOfDirectory(atPath: staged.path).isEmpty, "Staged não esvaziou")
        // Staged novo (sem instalado) entra; marcado para remoção some dos dois lados.
        writeManifest(staged.appendingPathComponent("Novo.neyplugin"), id: "local.novo", name: "Novo")
        writeManifest(staged.appendingPathComponent("Dose.neyplugin"), id: "local.dose", name: "Dose", version: "9.9.9")
        store.markForRemoval(id: "local.dose")
        store.applyPending()
        precondition(version(plugins.appendingPathComponent("Novo.neyplugin")) == "0.5.0")
        precondition(!fm.fileExists(atPath: plugins.appendingPathComponent("Dose.neyplugin").path))
        precondition(try! fm.contentsOfDirectory(atPath: staged.path).isEmpty)

        // Staged/ que sobrou (applyPending falhou) volta como "pronta para reiniciar"; marcado para remoção não.
        writeManifest(staged.appendingPathComponent("Capture.neyplugin"), id: "local.capture", name: "Capture", version: "0.6.0")
        writeManifest(staged.appendingPathComponent("Novo.neyplugin"), id: "local.novo", name: "Novo")
        store.markForRemoval(id: "local.novo")
        precondition(store.stagedVersions() == ["local.capture": "0.6.0"])
        // Órfãos de Incoming/ (download ou lixeira interrompidos) somem no início.
        let orphan = root.appendingPathComponent("Incoming/\(UUID().uuidString)")
        try! fm.createDirectory(at: orphan, withIntermediateDirectories: true)
        store.applyPending()
        precondition(!fm.fileExists(atPath: orphan.path), "órfão de Incoming/ ficou")
        precondition(version(plugins.appendingPathComponent("Capture.neyplugin")) == "0.6.0" && store.stagedVersions().isEmpty)

        // validate: contract incompatível e manifest ruim.
        let c2 = root.appendingPathComponent("c2/Aero.neyplugin")
        writeManifest(c2, contract: 2)
        precondition(store.validate(folder: c2).failure == .contract(2))
        precondition(store.validate(folder: root.appendingPathComponent("nada")).failure == .manifest)
        let unsigned = root.appendingPathComponent("u/Aero.neyplugin")
        writeManifest(unsigned)
        precondition(store.validate(folder: unsigned).failure == .signature)

        let r = { (v: String) in Release(version: v, notes: "", page: URL(string: "https://e")!, assets: [:]) }
        let installed = PluginStore.manifest(at: plugins.appendingPathComponent("Aero.neyplugin"))!
        precondition(store.needsUpdate(installed: installed, latest: r("0.5.2")))
        precondition(!store.needsUpdate(installed: installed, latest: r("0.5.1")))
        writeManifest(c2, version: "0.5.0")
        let m050 = PluginStore.manifest(at: c2)!
        precondition(store.needsUpdate(installed: m050, latest: r("0.5.1")) && !store.needsUpdate(installed: m050, latest: r("0.5.0")))
    }

    /// Instalação e preparo de verdade, sem rede: release e asset são file:// montados aqui a partir do fixture.
    static func storeInstall(_ fixture: URL) {
        let fm = FileManager.default
        let root = temp("install"), assets = temp("assets")
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: assets) }
        func zip(_ kind: String, as name: String) -> URL { zipFixture(fixture, kind, into: assets, as: name) }
        let good = zip("good", as: "Hello-1.0.0.neyplugin"), adhoc = zip("adhoc", as: "Hello-1.0.1.neyplugin")
        let future = zip("future", as: "Hello-1.0.2.neyplugin")
        let latestJSON = assets.appendingPathComponent("latest.json")
        try! Data(#"{"tag_name":"v1.0.0","html_url":"https://e","assets":[{"name":"Hello-1.0.0.neyplugin","browser_download_url":"\#(good.absoluteString)"}]}"#.utf8).write(to: latestJSON)

        let store = PluginStore(root: root)
        store.latestURL = { _ in latestJSON }
        let hello = CatalogEntry(id: "local.hello", name: "Hello", repo: "x/hello", summary: "", hasScreen: true)
        let incoming = root.appendingPathComponent("Incoming")
        func incomingEmpty() -> Bool { (try? fm.contentsOfDirectory(atPath: incoming.path))?.isEmpty ?? true }

        precondition(wait { await store.latest("x/hello") }?.version == "1.0.0")
        let url = try! waitThrowing { try await store.install(hello) }
        // Compara caminhos resolvidos: "/" no fim de pasta existente e /var × /private/var mudam a URL.
        func p(_ u: URL) -> String { u.resolvingSymlinksInPath().path }
        precondition(p(url) == p(root.appendingPathComponent("Plugins/Hello.neyplugin")))
        precondition(store.validate(folder: url).failure == nil && incomingEmpty())
        precondition(store.installedFolders().map(p) == [p(url)])

        // id do catálogo diferente do manifest baixado: recusa.
        let impostor = CatalogEntry(id: "local.aero", name: "Hello", repo: "x/hello", summary: "", hasScreen: false)
        precondition(waitError { try await store.install(impostor) } == .manifest && incomingEmpty())

        func release(_ v: String, _ file: URL?) -> Release {
            Release(version: v, notes: "", page: URL(string: "https://e")!, assets: file.map { ["Hello-\(v).neyplugin": $0] } ?? [:])
        }
        let staged = root.appendingPathComponent("Staged/Hello.neyplugin")
        precondition(waitError { try await store.stageUpdate(hello, release: release("1.0.1", adhoc)) } == .signature)
        precondition(waitError { try await store.stageUpdate(hello, release: release("1.0.2", future)) } == .contract(2))
        precondition(waitError { try await store.stageUpdate(hello, release: release("1.0.3", nil)) } == .download)
        precondition(waitError { try await store.stageUpdate(hello, release: release("1.0.4", assets.appendingPathComponent("sumiu"))) } == .download)
        // Manifest com nome ou versão diferentes do catálogo/release: recusa (o nome vira a pasta de destino).
        let renamed = CatalogEntry(id: "local.hello", name: "Dose", repo: "x/hello", summary: "", hasScreen: true)
        let asDose = Release(version: "1.0.0", notes: "", page: URL(string: "https://e")!, assets: ["Dose-1.0.0.neyplugin": good])
        precondition(waitError { try await store.stageUpdate(renamed, release: asDose) } == .manifest)
        precondition(waitError { try await store.stageUpdate(hello, release: release("1.0.5", good)) } == .manifest)
        precondition(!fm.fileExists(atPath: staged.path) && incomingEmpty(), "preparo recusado deixou resto")
        try! waitThrowing { try await store.stageUpdate(hello, release: release("1.0.0", good)) }
        precondition(store.validate(folder: staged).failure == nil && incomingEmpty())
        store.applyPending()
        precondition(store.validate(folder: url).failure == nil && !fm.fileExists(atPath: staged.path))

        // Reinstalar depois de desinstalar na mesma sessão: vai para Staged e tira o marcador.
        store.markForRemoval(id: "local.hello")
        precondition(store.installedFolders().isEmpty)
        precondition(p(try! waitThrowing { try await store.install(hello) }) == p(staged))
        precondition(store.installedFolders().map(p) == [p(url)])

        // Remoção que falha mantém o marcador: o desinstalado não volta no próximo início.
        store.applyPending()
        store.markForRemoval(id: "local.hello")
        let plugins = root.appendingPathComponent("Plugins"), marker = root.appendingPathComponent("Remove/local.hello")
        try! fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: plugins.path)
        store.applyPending()
        try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: plugins.path)
        precondition(fm.fileExists(atPath: marker.path) && store.installedFolders().isEmpty)
        store.applyPending()
        precondition(!fm.fileExists(atPath: marker.path) && !fm.fileExists(atPath: url.path))
    }

    static func zipFixture(_ fixture: URL, _ kind: String, into dir: URL, as name: String) -> URL {
        let out = dir.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", fixture.appendingPathComponent("\(kind)/Hello.neyplugin").path, out.path]
        try! p.run(); p.waitUntilExit()
        precondition(p.terminationStatus == 0)
        return out
    }

    /// Hash de caminhos + bytes da pasta inteira: prova que o instalado ficou intacto.
    static func digest(_ folder: URL) -> String {
        let fm = FileManager.default
        var h = SHA256()
        for path in (fm.subpaths(atPath: folder.path) ?? []).sorted() {
            h.update(data: Data(path.utf8))
            if let d = fm.contents(atPath: folder.appendingPathComponent(path).path) { h.update(data: d) }
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Atualização com servidor falso (URLProtocol na sessão do PluginStore): nada toca a rede.
    static func storeUpdates(_ fixture: URL) {
        let fm = FileManager.default
        let root = temp("updates"), assets = temp("upassets")
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: assets) }
        let good = zipFixture(fixture, "good", into: assets, as: "g.zip"), future = zipFixture(fixture, "future", into: assets, as: "f.zip")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeServer.self]
        let store = PluginStore(root: root)
        store.session = URLSession(configuration: config)
        store.latestURL = { URL(string: "https://fake.test/\($0)/latest")! }
        func serve(_ repo: String, _ version: String, _ asset: URL, notes: String = "") {
            let name = "Hello-\(version).neyplugin", url = "https://fake.test/dl/\(repo)/\(name)"
            let body: [String: Any] = ["tag_name": "v\(version)", "html_url": "https://e", "body": notes,
                                       "assets": [["name": name, "browser_download_url": url]]]
            FakeServer.routes["https://fake.test/\(repo)/latest"] = try! JSONSerialization.data(withJSONObject: body)
            FakeServer.routes[url] = try! Data(contentsOf: asset)
        }
        FakeServer.reset()

        // Instalado velho (0.9.0): só o manifest muda, a assinatura é do binário.
        let installed = root.appendingPathComponent("Plugins/Hello.neyplugin")
        try! fm.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! fm.copyItem(at: fixture.appendingPathComponent("good/Hello.neyplugin"), to: installed)
        let manifest = installed.appendingPathComponent("manifest.json")
        try! Data(String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(of: "1.0.0", with: "0.9.0").utf8).write(to: manifest)
        let before = digest(installed)
        let hello = CatalogEntry(id: "local.hello", name: "Hello", repo: "x/hello", summary: "", hasScreen: true)
        // Instalado de verdade, mas sem rota no servidor (404): precisa ser consultado e falhar sem parar o seguinte.
        let sumido = root.appendingPathComponent("Plugins/Sumido.neyplugin")
        try! fm.copyItem(at: installed, to: sumido)
        let sm = sumido.appendingPathComponent("manifest.json")
        try! Data(String(contentsOf: sm, encoding: .utf8).replacingOccurrences(of: "local.hello", with: "local.sumido").replacingOccurrences(of: "\"Hello\"", with: "\"Sumido\"").utf8).write(to: sm)
        precondition(PluginStore.manifest(at: sumido)?.id == "local.sumido" && PluginStore.manifest(at: sumido)?.name == "Sumido")
        let broken = CatalogEntry(id: "local.sumido", name: "Sumido", repo: "x/sumido", summary: "", hasScreen: false)
        func check() -> (latest: [String: Release], staged: [String: String]) { wait { await store.checkUpdates([hello]) } }

        // Contract 2: recusa e o instalado fica byte a byte igual.
        serve("x/hello", "1.0.0", future)
        let futureRelease = wait { await store.latest("x/hello") }!
        precondition(waitError { try await store.stageUpdate(hello, release: futureRelease) } == .contract(2))
        precondition(digest(installed) == before && store.stagedVersions().isEmpty, "contract 2 mexeu no instalado")
        precondition(check().staged.isEmpty && digest(installed) == before)

        // Caminho feliz: um plugin com falha não impede o seguinte; notas persistem ao lado de Staged/.
        serve("x/hello", "1.0.0", good, notes: "- novo")
        FakeServer.reset(keepingRoutes: true)
        let all = wait { await store.checkUpdates([broken, hello]) }
        precondition(FakeServer.hits("https://fake.test/x/sumido/latest") == 1, "o plugin com falha nem foi consultado")
        precondition(all.staged == ["local.hello": "1.0.0"] && all.latest["local.hello"]?.version == "1.0.0" && all.latest["local.sumido"] == nil)
        precondition(digest(installed) == before, "preparar não troca o instalado")
        precondition(FakeServer.hits("https://fake.test/dl/x/hello/Hello-1.0.0.neyplugin") == 1)
        let model = HubModel(store: store)
        precondition(model.staged.isEmpty)
        model.absorb(all)
        precondition(!model.staged.isEmpty && model.latest["local.hello"] != nil, "banner não acendeu")

        // Já preparada na mesma versão: não baixa de novo.
        precondition(check().staged.isEmpty && FakeServer.hits("https://fake.test/dl/x/hello/Hello-1.0.0.neyplugin") == 1)

        // Só applyPending troca, e informa o que trocou com as notas (que ficam até serem mostradas).
        let applied = store.applyPending()
        precondition(applied == [AppliedUpdate(name: "Hello", version: "1.0.0", notes: "- novo")], "\(applied)")
        precondition(PluginStore.manifest(at: installed)?.version == "1.0.0" && store.stagedVersions().isEmpty)
        let stagedDir = root.appendingPathComponent("Staged")
        precondition(try! fm.contentsOfDirectory(atPath: stagedDir.path) == ["Hello.notes.md"], "notas somem antes de mostrar")
        store.clearNotes(applied)
        precondition((try! fm.contentsOfDirectory(atPath: stagedDir.path)).isEmpty, "notas não foram apagadas")
        precondition(store.applyPending().isEmpty)

        // Marcado para remoção: nada é preparado (manifest velho de novo, release mais nova).
        try! Data(String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(of: "1.0.0", with: "0.9.0").utf8).write(to: manifest)
        store.markForRemoval(id: "local.hello")
        FakeServer.reset(keepingRoutes: true)
        precondition(check().staged.isEmpty && FakeServer.hits("https://fake.test/dl/x/hello/Hello-1.0.0.neyplugin") == 0)
    }

    /// O selftest roda síncrono na main; as chamadas async rodam fora dela.
    static func wait<T>(_ op: @escaping () async -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        var out: T?
        Task.detached { out = await op(); done.signal() }
        done.wait()
        return out!
    }

    static func waitThrowing<T>(_ op: @escaping () async throws -> T) throws -> T {
        try wait { () async -> Result<T, Error> in
            do { return .success(try await op()) } catch { return .failure(error) }
        }.get()
    }

    static func waitError<T>(_ op: @escaping () async throws -> T) -> StageError? {
        do { _ = try waitThrowing(op); return nil } catch { return error as? StageError }
    }
}

extension Result {
    /// Só para teste: o erro, ou nil se deu certo.
    var failure: Failure? { if case .failure(let e) = self { e } else { nil } }
}

/// Plugin falso do `lifecycle`: mora no NeyHub, conta start/stop.
final class FakePlugin: NSObject, NeyPlugin {
    var starts = 0, stops = 0
    var contractVersion: Int { 1 }
    func start(host: NeyHost) { starts += 1 }
    func stop() { stops += 1 }
    func setMenuBarVisible(_ visible: Bool) {}
    func makeScreen() -> NSViewController? { nil }
    func makeSettings() -> NSViewController { NSViewController() }
}

/// Servidor falso: rotas por URL completa; sem rota responde 404. Só para o selftest.
final class FakeServer: URLProtocol {
    static let lock = NSLock()
    nonisolated(unsafe) static var routes: [String: Data] = [:]
    nonisolated(unsafe) static var counts: [String: Int] = [:]
    static func reset(keepingRoutes: Bool = false) { lock.lock(); if !keepingRoutes { routes = [:] }; counts = [:]; lock.unlock() }
    static func hits(_ url: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[url] ?? 0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.lock.lock()
        Self.counts[url.absoluteString, default: 0] += 1
        let data = Self.routes[url.absoluteString]
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: data == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

import AppKit
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
        if let fixture { plugins(fixture); storeInstall(fixture) } else { FileHandle.standardError.write(Data("sem --fixture: pulando carga de plugins\n".utf8)) }
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
        guard case .success(let p) = PluginHost.load(folder: good) else { preconditionFailure("good: \(PluginHost.load(folder: good))") }
        precondition(p.plugin.contractVersion == 1 && p.plugin.makeScreen() != nil)
        precondition(PluginHost.dlopenCount == 1)
        precondition(PluginHost.load(folder: good).failure == .alreadyLoaded)
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
        try! fm.linkItem(at: good.appendingPathComponent("libHelloPlugin.dylib"), to: other.appendingPathComponent("libHelloPlugin.dylib"))
        precondition(PluginHost.load(folder: other).failure == .alreadyLoaded && PluginHost.dlopenCount == 1)

        hosting(p)
    }

    /// Início, presença, tela embutida e desinstalar com o plugin `good` já carregado (start/stop uma vez só).
    @MainActor static func hosting(_ p: LoadedPlugin) {
        let fm = FileManager.default
        precondition(PluginHost.problemText(.contractTooNew(2)) == "Precisa atualizar o NeyHub")
        precondition(PluginHost.problemText(.signature) == "Assinatura não confere — reinstale pela Loja")
        precondition(PluginHost.problemText(.contractTooOld(0)) == "Precisa atualizar o app")
        precondition(PluginHost.problemText(.alreadyLoaded) == "Reinicie o NeyHub para reinstalar")
        precondition(PluginHost.problemText(.symbol) == "Não deu pra carregar")
        precondition(PluginHost.conflict(id: "local.inexistente") == nil)

        let root = temp("host")
        defer { try? fm.removeItem(at: root) }
        let store = PluginStore(root: root)
        let model = HubModel(store: store)
        func count(_ key: String) -> Int? { (p.plugin as AnyObject).value(forKey: key) as? Int }
        func active() -> [String]? { try? JSONDecoder().decode([String].self, from: Data(contentsOf: root.appendingPathComponent("active.json"))) }

        // Ponte host↔plugin atravessa as duas imagens; contadores lidos por KVC (a classe mora no plugin).
        let host = HostBridge()
        PluginHost.begin(p, model: model, host: host)
        precondition(host.messages == ["Olá do plugin"] && model.loaded.map(\.manifest.id) == ["local.hello"])
        precondition(active() == ["local.hello"], "active.json sem o iniciado")
        precondition(count("menuBarCalls") == 1, "begin não aplicou a presença")

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
        func zip(_ kind: String, as name: String) -> URL {
            let out = assets.appendingPathComponent(name)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--keepParent", fixture.appendingPathComponent("\(kind)/Hello.neyplugin").path, out.path]
            try! p.run(); p.waitUntilExit()
            precondition(p.terminationStatus == 0)
            return out
        }
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

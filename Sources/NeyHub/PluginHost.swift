import AppKit
import NeyKit

enum LoadError: Error, Equatable { case manifest, signature, contractTooNew(Int), contractTooOld(Int), symbol, notAPlugin, alreadyLoaded }

struct LoadedPlugin { let manifest: PluginManifest; let plugin: NeyPlugin; let folder: URL }

/// Carrega `<Nome>.neyplugin`, inicia, aplica presença e desinstala.
@MainActor
enum PluginHost {
    /// ids cujo dylib já foi aberto: o entry de um id nunca roda duas vezes no mesmo processo.
    private static var loadedIDs: Set<String> = []
    /// dev:inode dos dylibs abertos: o mesmo arquivo (symlink/hardlink) sob outro id daria o mesmo handle e rodaria o entry de novo.
    private static var loadedFiles: Set<String> = []
    /// Nunca fechados: código do plugin continua no processo até sair.
    private static var handles: [UnsafeMutableRawPointer] = []
    /// Quantas vezes chamamos dlopen (o selftest garante que plugin rejeitado não chega lá).
    private(set) static var dlopenCount = 0
    private static var launchObserver: NSKeyValueObservation?
    /// ids com alerta de conflito aberto: um segundo lançamento do avulso não empilha outro.
    private static var alerting: Set<String> = []
    /// Pausados no início (carregados, nunca iniciados) e parados em uso por causa do avulso.
    private static var waiting: [String: LoadedPlugin] = [:]
    private static var stopped: Set<String> = []

    static func load(folder: URL) -> Result<LoadedPlugin, LoadError> {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data), manifest.isValid
        else { return .failure(.manifest) }
        if let e = contractError(manifest.contract) { return .failure(e) }
        let binary = folder.appendingPathComponent(manifest.binary)
        guard PluginSignature.isTrustedPlugin(binary) else { return .failure(.signature) }
        guard !loadedIDs.contains(manifest.id) else { return .failure(.alreadyLoaded) }
        var st = stat()
        guard stat(binary.path, &st) == 0 else { return .failure(.symbol) }
        let file = "\(st.st_dev):\(st.st_ino)"
        guard !loadedFiles.contains(file) else { return .failure(.alreadyLoaded) }

        dlopenCount += 1
        // shortcut: assinatura conferida antes do dlopen; troca do arquivo entre os dois passos não é tratada (pasta é do usuário).
        guard let handle = dlopen(binary.path, RTLD_NOW) else {
            NSLog("NeyHub: dlopen \(manifest.id): \(dlerror().map { String(cString: $0) } ?? "?")")
            return .failure(.symbol)
        }
        handles.append(handle)
        loadedIDs.insert(manifest.id)
        loadedFiles.insert(file)
        guard let symbol = dlsym(handle, "neyhub_plugin_v1") else { return .failure(.symbol) }
        typealias Entry = @convention(c) () -> UnsafeMutableRawPointer
        let object = Unmanaged<AnyObject>.fromOpaque(unsafeBitCast(symbol, to: Entry.self)()).takeRetainedValue()
        guard let plugin = object as? NeyPlugin else { return .failure(.notAPlugin) }
        if let e = contractError(plugin.contractVersion) { return .failure(e) }
        return .success(LoadedPlugin(manifest: manifest, plugin: plugin, folder: folder))
    }

    private static func contractError(_ v: Int) -> LoadError? {
        v > neyPluginContractVersion ? .contractTooNew(v) : v < neyPluginContractVersion ? .contractTooOld(v) : nil
    }

    static func problemText(_ e: LoadError) -> String {
        switch e {
        case .signature: "Assinatura não confere — reinstale pela Loja"
        case .contractTooNew: "Precisa atualizar o NeyHub"
        case .contractTooOld: "Precisa atualizar o app"
        case .alreadyLoaded: "Reinicie o NeyHub para reinstalar"
        default: "Não deu pra carregar"
        }
    }

    // MARK: - Retorno de login

    /// Entrega a URL `hubmac://…` aos plugins iniciados, na ordem de carga, até um tratar.
    static func route(_ url: URL, model: HubModel) -> Bool {
        model.loaded.contains { $0.plugin.handleURL?(url) ?? false }
    }

    // MARK: - Início

    /// Chamar depois do `applyPending`. Avulso aberto pergunta antes; quem não carrega ganha o motivo no card.
    static func startAll(_ model: HubModel) {
        writeActive(model) // zera o de uma sessão que caiu: avulso pausado não pode achar que está hospedado
        for folder in model.store.installedFolders() { start(folder: folder, model: model) }
        observeLaunches(model)
    }

    /// Início e instalação pela Loja: carrega, pergunta se o avulso está aberto e inicia.
    /// Manifest ilegível não tem id: o problema fica com o nome da pasta (card "Pasta … com problema").
    static func start(folder: URL, model: HubModel) {
        switch load(folder: folder) {
        case .failure(.manifest):
            model.problems[folder.lastPathComponent] = problemText(.manifest)
        case .failure(let e):
            model.problems[PluginStore.manifest(at: folder)?.id ?? folder.lastPathComponent] = problemText(e)
        case .success(let p):
            let id = p.manifest.id
            guard let other = conflict(id: id) else { return begin(p, model: model) }
            offerClose(other, name: p.manifest.name) { closed in
                // Durante a espera: outro avulso pode ter aberto ou a pessoa pode ter desinstalado.
                if model.store.isMarkedForRemoval(id) { return }
                if closed, conflict(id: id) == nil { begin(p, model: model) } else { pause(p, model: model) }
            }
        }
    }

    /// Carregado e nunca iniciado: começa quando o avulso fechar (`resume`).
    static func pause(_ p: LoadedPlugin, model: HubModel) {
        waiting[p.manifest.id] = p
        model.problems[p.manifest.id] = paused
    }

    /// Avulso fechou: o pausado no início começa; o parado em uso não (o entry não roda de novo e `start` depois de
    /// `stop` não é garantido), só troca o aviso por "reinicie o NeyHub".
    static func resume(_ model: HubModel) {
        for (id, p) in waiting where conflict(id: id) == nil {
            waiting[id] = nil
            if !model.store.isMarkedForRemoval(id) { begin(p, model: model) }
        }
        for id in stopped where conflict(id: id) == nil {
            stopped.remove(id)
            if model.problems[id] == paused { model.problems[id] = restartToResume }
        }
    }

    /// Desinstalado: sai dos pausados e dos parados.
    static func forget(_ id: String) {
        waiting[id] = nil
        stopped.remove(id)
    }

    /// Avulso do mesmo app aberto (o NeyHub nunca é o avulso de um plugin).
    static func conflict(id: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first { !$0.isTerminated }
    }

    nonisolated static let paused = "Pausado: avulso aberto"
    nonisolated static let restartToResume = "Pausado — reinicie o NeyHub para voltar"

    /// Avulso que declara `NeyHubAware` no Info.plist mostra o próprio alerta (HubCheck) e sai: o NeyHub não mostra o dele.
    /// Contrato: só declare `NeyHubAware = true` num app que chama `HubCheck.leaveForHub` ao abrir; senão ninguém avisa
    /// e os dois rodam juntos.
    static func handlesConflictItself(_ bundleURL: URL?) -> Bool {
        bundleURL.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "NeyHubAware") as? Bool == true
    }

    static func begin(_ p: LoadedPlugin, model: HubModel) {
        p.plugin.start(host: model.host)
        model.loaded.append(p)
        model.problems[p.manifest.id] = nil
        apply(Presence.load(AppDefaults.forApp(p.manifest.id), hasScreen: p.manifest.hasScreen), to: p, model: model)
        writeActive(model)
        model.registerCategories() // idempotente: quem começa depois (Loja, avulso fechado) também ganha as dele
    }

    /// Avulso aberto com o NeyHub já rodando o plugin: mesmo alerta. "Agora não" para o plugin (dois processos no mesmo `dados.json`).
    /// Avulso que sai: o pausado volta (`resume`).
    /// KVO em `runningApplications`, não `didLaunchApplicationNotification`: ela não vem para apps de barra de menus (accessory).
    private static func observeLaunches(_ model: HubModel) {
        guard launchObserver == nil else { return }
        nonisolated(unsafe) let model = model // só tocado na main (DispatchQueue.main abaixo)
        launchObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { _, change in
            let apps = change.newValue ?? []
            // Fora do callback do KVO: o alerta é modal.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    resume(model) // barato; não depende de o KVO dizer que foi remoção
                    for app in apps where !app.isTerminated {
                        guard let p = model.loaded.first(where: { $0.manifest.id == app.bundleIdentifier }),
                              !handlesConflictItself(app.bundleURL) else { continue }
                        let id = p.manifest.id
                        guard alerting.insert(id).inserted else { continue }
                        offerClose(app, name: p.manifest.name) { closed in
                            alerting.remove(id)
                            // Desinstalado enquanto isso já levou stop(): nunca duas vezes.
                            guard !closed, model.loaded.contains(where: { $0.manifest.id == id }) else { return }
                            stopForConflict(p, model: model)
                        }
                    }
                }
            }
        }
    }

    /// "Agora não" com o plugin em uso: para e fica parado até o NeyHub reiniciar (`resume` só troca o aviso).
    static func stopForConflict(_ p: LoadedPlugin, model: HubModel) {
        drop(p, model: model) // tira do active.json antes do stop(): o HubCheck do avulso confere depois de responder
        p.plugin.stop()
        stopped.insert(p.manifest.id)
        model.problems[p.manifest.id] = paused
    }

    /// Alerta Grafite. Fechar encerra o avulso e espera ele sair sem travar a main; `done(false)` se recusou ou não saiu em 5 s.
    private static func offerClose(_ app: NSRunningApplication, name: String, done: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.window.appearance = NSAppearance(named: .darkAqua)
        alert.messageText = "O \(name) avulso está aberto. Fechar e usar pelo NeyHub?"
        alert.addButton(withTitle: "Fechar")
        alert.addButton(withTitle: "Agora não")
        NSApp.activate()
        let answer = alert.runModal()
        // O avulso saiu sozinho (HubCheck) enquanto o alerta estava aberto: segue no NeyHub, qualquer que seja a resposta.
        if app.isTerminated { return done(true) }
        guard answer == .alertFirstButtonReturn else { return done(false) }
        app.terminate()
        waitExit(app, tries: 25, done: done)
    }

    private static func waitExit(_ app: NSRunningApplication, tries: Int, done: @escaping (Bool) -> Void) {
        if app.isTerminated || tries == 0 { return done(app.isTerminated) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { waitExit(app, tries: tries - 1, done: done) }
    }

    // MARK: - Uso

    /// Barra de menus no plugin; a tela decide se o app aparece na sidebar.
    static func apply(_ p: Presence, to plugin: LoadedPlugin, model: HubModel) {
        let id = plugin.manifest.id, p = p.normalized(hasScreen: plugin.manifest.hasScreen)
        plugin.plugin.setMenuBarVisible(p.menuBar)
        model.presences[id] = p
        // Saiu da sidebar com a tela aberta: vai para o detalhe na Loja, onde dá para voltar o modo.
        if !p.screen, model.route == .app(id) { model.route = .store; model.detail = id }
    }

    static func uninstall(_ p: LoadedPlugin, store: PluginStore, model: HubModel) {
        p.plugin.stop()
        store.markForRemoval(id: p.manifest.id)
        drop(p, model: model)
    }

    /// Tira da sidebar e do `active.json`; o dylib continua aberto até o NeyHub sair.
    private static func drop(_ p: LoadedPlugin, model: HubModel) {
        let id = p.manifest.id
        model.loaded.removeAll { $0.manifest.id == id }
        model.screens[id] = nil
        model.presences[id] = nil
        if model.route == .app(id) { model.route = .store }
        writeActive(model)
    }

    // MARK: - active.json

    /// Ids iniciados nesta sessão; os avulsos leem (`HubCheck.isHosted`) para não rodar junto.
    static func activeURL(_ store: PluginStore) -> URL { store.root.appendingPathComponent("active.json") }

    private static func writeActive(_ model: HubModel) {
        do { try JSONEncoder().encode(model.loaded.map(\.manifest.id)).write(to: activeURL(model.store), options: .atomic) }
        catch { NSLog("NeyHub: não deu pra gravar active.json: \(error)") }
    }
}

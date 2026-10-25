import AppKit
import Combine
import NeyKit
import NeyKitApp
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = HubModel()
    private lazy var notifications = Notifications(model: model)
    private var window: NSWindow?
    private var awakeItem: AwakeStatusItem?
    private var awakeSub: AnyCancellable?
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        DistributedNotificationCenter.default().addObserver(forName: .init("local.neyhub.show"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showWindow() }
        }
        notifications.install()
        model.registerCategories = { [notifications] in notifications.registerCategories() }
        model.host.onOpenPermissions = { [self] in model.route = .permissions; showWindow() }
        model.host.onShowScreen = { [self] id in model.showScreen(id); showWindow() }
        offerLoginItem()
        let applied = model.store.applyPending() // antes de qualquer plugin ser carregado
        model.openStore()          // catálogo do cache/embutido já; rede em segundo plano
        showWindow()
        awakeSub = model.awake.$showInMenuBar.sink { [self] show in // $: dispara já com o valor salvo
            awakeItem = show ? (awakeItem ?? AwakeStatusItem(awake: model.awake)) : nil
        }
        PluginHost.startAll(model) // cada begin registra as categorias
        Task { await model.refreshPermissions() } // ponto da sidebar já no início
        startUpdates()
        showWhatsNew(applied)
        model.store.clearNotes(applied)
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = model.updater?.applyStaged() // fechar normalmente também instala o que já foi baixado
        try? FileManager.default.removeItem(at: PluginHost.activeURL(model.store)) // ausente já é o estado certo
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where !PluginHost.route(url, model: model) {
            let alert = NSAlert()
            alert.window.appearance = NSAppearance(named: .darkAqua)
            alert.messageText = "Nenhum app esperava este login"
            alert.informativeText = "Abra o app que pediu o login e tente de novo."
            NSApp.activate()
            alert.runModal()
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// NeyHub: Updater próprio (5 s, 6 h). Plugins: mesmo ritmo, aqui. Baixa sozinho; só aplica no próximo início.
    private func startUpdates() {
        let updater = Updater(name: "NeyHub", repo: "yagoramires/neyhub", id: "local.neyhub")
        updater.onChange = { [model, weak updater] in model.hubStaged = updater?.staged }
        model.updater = updater
        model.hubStaged = updater.staged
        updater.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [model] in model.checkPluginUpdates() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [model] _ in model.checkPluginUpdates() }
    }

    /// Uma janela com as notas do NeyHub (se ele atualizou) e de cada plugin trocado pelo applyPending.
    private func showWhatsNew(_ applied: [AppliedUpdate]) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        var sections: [(title: String, notes: String)] = []
        if let notes = Updater.notesAfterUpdate(id: "local.neyhub", current: version), !notes.isEmpty { sections.append(("NeyHub \(version)", notes)) }
        sections += applied.filter { !$0.notes.isEmpty }.map { ("\($0.name) \($0.version)", $0.notes) }
        if !sections.isEmpty { WhatsNew.show(sections: sections) }
    }

    private func showWindow() {
        let w = window ?? MainWindow.make(model: model)
        w.delegate = self
        window = w
        NSApp.setActivationPolicy(.regular)
        model.awake.refresh()
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Mínimo para ⌘Q, ⌘W e editar texto (campos dos plugins). Sair passa pelo applicationWillTerminate.
    static func mainMenu() -> NSMenu {
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let sub = NSMenu(title: title)
            items.forEach(sub.addItem)
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = sub
            return top
        }
        let main = NSMenu()
        main.addItem(menu("NeyHub", [item("Sobre o NeyHub", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""), .separator(),
                                     item("Sair do NeyHub", #selector(NSApplication.terminate(_:)), "q")]))
        main.addItem(menu("Editar", [item("Desfazer", Selector(("undo:")), "z"), item("Refazer", Selector(("redo:")), "z", [.command, .shift]),
                                     .separator(), item("Recortar", #selector(NSText.cut(_:)), "x"), item("Copiar", #selector(NSText.copy(_:)), "c"),
                                     item("Colar", #selector(NSText.paste(_:)), "v"), item("Selecionar tudo", #selector(NSText.selectAll(_:)), "a")]))
        main.addItem(menu("Janela", [item("Fechar", #selector(NSWindow.performClose(_:)), "w"),
                                     item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m")]))
        return main
    }

    /// Registra como item de login só na primeira execução; falha só vai pro log.
    private func offerLoginItem() {
        let key = "loginItemOffered"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do { try SMAppService.mainApp.register() } catch { NSLog("NeyHub: item de login falhou: \(error)") }
    }
}

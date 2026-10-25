import AppKit
import Combine
import NeyKit
import NeyKitApp
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = HubModel()
    private let host = HostBridge()
    private lazy var notifications = Notifications(model: model)
    private var window: NSWindow?
    private var awakeItem: AwakeStatusItem?
    private var awakeSub: AnyCancellable?
    private var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifications.install()
        host.onOpenPermissions = { [self] in model.route = .permissions; showWindow() }
        host.onShowScreen = { [self] id in model.showScreen(id); showWindow() }
        offerLoginItem()
        let applied = model.store.applyPending() // antes de qualquer plugin ser carregado
        model.openStore()          // catálogo do cache/embutido já; rede em segundo plano
        showWindow()
        awakeSub = model.awake.$showInMenuBar.sink { [self] show in // $: dispara já com o valor salvo
            awakeItem = show ? (awakeItem ?? AwakeStatusItem(awake: model.awake)) : nil
        }
        PluginHost.startAll(model, store: model.store, host: host)
        notifications.registerCategories()
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

    /// Registra como item de login só na primeira execução; falha só vai pro log.
    private func offerLoginItem() {
        let key = "loginItemOffered"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do { try SMAppService.mainApp.register() } catch { NSLog("NeyHub: item de login falhou: \(error)") }
    }
}

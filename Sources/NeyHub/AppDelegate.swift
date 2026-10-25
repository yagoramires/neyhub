import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = HubModel()
    private let host = HostBridge()
    private lazy var notifications = Notifications(model: model)
    private var window: NSWindow?
    private var awakeItem: AwakeStatusItem?
    private var awakeSub: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifications.install()
        host.onOpenPermissions = { [self] in model.route = .permissions; showWindow() }
        host.onShowScreen = { [self] id in model.showScreen(id); showWindow() }
        offerLoginItem()
        model.store.applyPending() // antes de qualquer plugin ser carregado
        model.openStore()          // catálogo do cache/embutido já; rede em segundo plano
        showWindow()
        awakeSub = model.awake.$showInMenuBar.sink { [self] show in // $: dispara já com o valor salvo
            awakeItem = show ? (awakeItem ?? AwakeStatusItem(awake: model.awake)) : nil
        }
        PluginHost.startAll(model, store: model.store, host: host)
        notifications.registerCategories()
        Task { await model.refreshPermissions() } // ponto da sidebar já no início
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    private func showWindow() {
        let w = window ?? MainWindow.make(model: model)
        w.delegate = self
        window = w
        NSApp.setActivationPolicy(.regular)
        model.awake.refresh()
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Registra como item de login só na primeira execução; falha só vai pro log.
    private func offerLoginItem() {
        let key = "loginItemOffered"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        do { try SMAppService.mainApp.register() } catch { NSLog("NeyHub: item de login falhou: \(error)") }
    }
}

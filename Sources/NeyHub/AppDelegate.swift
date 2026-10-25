import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = HubModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        offerLoginItem()
        showWindow()
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

import AppKit
import NeyKit

/// Onde o próprio NeyHub aparece: ícone no Dock e/ou na barra de menus. Nunca os dois apagados.
struct HubPresence: Equatable {
    var dock = false, menuBar = true

    static func load(_ d: UserDefaults) -> HubPresence {
        HubPresence(dock: d.object(forKey: "presence.dock") as? Bool ?? false,
                    menuBar: d.object(forKey: "presence.menuBar") as? Bool ?? true).normalized
    }

    func save(_ d: UserDefaults) {
        d.set(dock, forKey: "presence.dock")
        d.set(menuBar, forKey: "presence.menuBar")
    }

    /// Valor salvo à mão com os dois apagados: a barra de menus volta (como no Presence dos apps).
    var normalized: HubPresence { !dock && !menuBar ? HubPresence(dock: false, menuBar: true) : self }

    /// Apagar um com o outro já apagado liga o outro de volta.
    func setting(dock v: Bool) -> HubPresence { HubPresence(dock: v, menuBar: menuBar || !v) }
    func setting(menuBar v: Bool) -> HubPresence { HubPresence(dock: dock || !v, menuBar: v) }

    /// Janela aberta precisa de Dock/foco; fechada, só fica regular se o ícone do Dock estiver ligado.
    func policy(windowOpen: Bool) -> NSApplication.ActivationPolicy { windowOpen || dock ? .regular : .accessory }
}

/// Ícone do NeyHub na barra de menus + as duas opções (menu do ícone e menu "NeyHub").
/// Só mexe em NSStatusBar/NSApp depois do `install()`: o selftest usa defaults isoladas sem tocar no sistema.
final class HubPresenceController: NSObject, NSMenuItemValidation {
    private let defaults: UserDefaults
    private(set) var presence: HubPresence
    private var windowOpen = false
    private var live = false
    private var item: NSStatusItem?
    var onOpen: () -> Void = {}

    init(defaults: UserDefaults = AppDefaults.forApp("local.neyhub")) {
        self.defaults = defaults
        presence = HubPresence.load(defaults)
        super.init()
    }

    func install() { live = true; apply() }

    func windowChanged(open: Bool) { windowOpen = open; apply() }

    /// As duas opções com o alvo no controller; o estado (✓) vem do `validateMenuItem`.
    func toggleItems() -> [NSMenuItem] {
        [NSMenuItem(title: "Mostrar ícone no Dock", action: #selector(toggleDock), keyEquivalent: ""),
         NSMenuItem(title: "Mostrar ícone na barra de menus", action: #selector(toggleMenuBar), keyEquivalent: "")]
            .map { $0.target = self; return $0 }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleDock): item.state = presence.dock ? .on : .off
        case #selector(toggleMenuBar): item.state = presence.menuBar ? .on : .off
        default: break
        }
        return true
    }

    @objc func toggleDock() { set(presence.setting(dock: !presence.dock)) }
    @objc func toggleMenuBar() { set(presence.setting(menuBar: !presence.menuBar)) }
    @objc private func open() { onOpen() }

    private func set(_ p: HubPresence) {
        presence = p
        p.save(defaults)
        apply()
    }

    private func apply() {
        guard live else { return }
        NSApp.setActivationPolicy(presence.policy(windowOpen: windowOpen))
        if presence.menuBar, item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            i.autosaveName = "local.neyhub"
            i.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "NeyHub")
            i.button?.image?.isTemplate = true
            i.menu = statusMenu()
            item = i
        } else if !presence.menuBar, let i = item {
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
    }

    func statusMenu() -> NSMenu {
        let open = NSMenuItem(title: "Abrir NeyHub", action: #selector(open), keyEquivalent: "")
        open.target = self
        let quit = NSMenuItem(title: "Sair do NeyHub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let menu = NSMenu()
        ([open, .separator()] + toggleItems() + [.separator(), quit]).forEach(menu.addItem)
        return menu
    }
}

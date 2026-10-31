import AppKit
import NeyKit
import SwiftUI

enum MainWindow {
    static func make(model: HubModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Grafite.bg)
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.center()
        window.setFrameAutosaveName("NeyHubMain")
        return window
    }
}

/// Tela de um plugin dentro da janela: nome e modo no topo, a tela do plugin embaixo.
struct AppScreen: View {
    @ObservedObject var model: HubModel
    let plugin: LoadedPlugin

    var body: some View {
        let m = plugin.manifest
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIcon(name: m.title, id: m.id, size: 26)
                Text(m.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                PresencePicker(model: model, id: m.id, name: m.title, hasScreen: m.hasScreen)
            }
            if let screen = model.screen(for: plugin) {
                PluginViewHost(make: { screen }).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Este app não tem tela.").font(.system(size: 11)).foregroundStyle(Grafite.muted)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

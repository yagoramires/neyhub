import AppKit
import Combine
import NeyKit
import SwiftUI

enum Route: Hashable { case store, permissions, app(String) }

final class HubModel: ObservableObject {
    @Published var route: Route = .store
    @Published var loaded: [LoadedPlugin] = []
    @Published var problems: [String: String] = [:]
    @Published var granted: [Permission: Bool] = [:]    // última consulta ao sistema (PermissionsView.swift)
    @Published var presences: [String: Presence] = [:]   // id → presença aplicada (PluginHost.apply)
    /// Tela de cada plugin, criada uma vez: trocar de item na sidebar não recria.
    var screens: [String: NSViewController] = [:]
    let awake = AwakeModel()

    // Loja (StoreView.swift)
    let store: PluginStore
    @Published var catalog: [CatalogEntry] = []
    @Published var installed: [String: PluginManifest] = [:] // id → manifest em Plugins/
    @Published var latest: [String: Release] = [:]           // id → última release no GitHub
    @Published var staged: [String: String] = [:]            // id → versão pronta para o próximo início
    @Published var busy: Set<String> = []
    @Published var detail: String?                           // id aberto no detalhe da Loja

    init(store: PluginStore = PluginStore(root: PluginStore.defaultRoot)) { self.store = store }

    /// Carregados com a tela ligada: só esses aparecem em "Instalados".
    var sidebarApps: [LoadedPlugin] { loaded.filter { presences[$0.manifest.id]?.screen == true } }

    func screen(for p: LoadedPlugin) -> NSViewController? {
        if let vc = screens[p.manifest.id] { return vc }
        let vc = p.plugin.makeScreen()
        screens[p.manifest.id] = vc
        return vc
    }
}

struct Sidebar: View {
    @ObservedObject var model: HubModel
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text("ney").foregroundStyle(Grafite.strong) + Text("hub").foregroundStyle(Grafite.accent))
                .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                .padding(.horizontal, 6).padding(.bottom, 10)
            item(.store, title: "Loja") { symbol("bag") }
            item(.permissions, title: "Permissões", dot: model.missingPermission) { symbol("lock.shield") }
            GSectionLabel("Instalados").padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 4)
            ForEach(model.sidebarApps, id: \.manifest.id) { plugin in
                item(.app(plugin.manifest.id), title: plugin.manifest.name) {
                    AppIcon(name: plugin.manifest.name, id: plugin.manifest.id, size: 18)
                }
            }
            Spacer(minLength: 0)
            AwakeSwitch(awake: model.awake)
        }
        .padding(.horizontal, 8).padding(.bottom, 12).padding(.top, 38) // 38: espaço dos botões da janela
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Grafite.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Grafite.border).frame(width: 1) }
    }

    private func item<Icon: View>(_ route: Route, title: String, dot: Bool = false, @ViewBuilder icon: () -> Icon) -> some View {
        let selected = model.route == route
        return Button { model.route = route } label: {
            HStack(spacing: 7) {
                icon().frame(width: 18, height: 18)
                Text(title).font(.system(size: 12))
                Spacer(minLength: 0)
                if dot { Circle().fill(Grafite.accent).frame(width: 6, height: 6).accessibilityHidden(true) }
            }
            .foregroundStyle(selected ? Grafite.strong : Grafite.ghostText)
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(selected ? Grafite.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (dot ? ", falta permissão" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 12, weight: .medium)).accessibilityHidden(true)
    }

    /// Cor estável por id (hash simples; String.hashValue muda a cada execução). A Loja usa a mesma.
    static func color(for id: String) -> Color {
        let palette = ["#3d7bff", "#ff5a4f", "#25c26e", "#a46bff", "#f0a020", "#e04fa0"]
        let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Grafite.color(hex: palette[sum % palette.count]) ?? Grafite.accent
    }
}

struct RootView: View {
    @ObservedObject var model: HubModel
    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
            switch model.route {
            case .permissions: PermissionsView(model: model)
            case .app(let id):
                if let p = model.loaded.first(where: { $0.manifest.id == id }) { AppScreen(model: model, plugin: p).id(id) } else { store }
            case .store: store
            }
        }
        .foregroundStyle(Grafite.text)
        .background(Grafite.bg)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var store: some View {
        StoreView(model: model)
            .padding(.horizontal, 16).padding(.top, 38)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

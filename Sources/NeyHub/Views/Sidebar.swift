import Combine
import NeyKit
import SwiftUI

enum Route: Hashable { case store, permissions, app(String) }

final class HubModel: ObservableObject {
    @Published var route: Route = .store
    @Published var loaded: [LoadedPlugin] = []
    @Published var problems: [String: String] = [:]

    // Loja (StoreView.swift)
    let store: PluginStore
    @Published var catalog: [CatalogEntry] = []
    @Published var installed: [String: PluginManifest] = [:] // id → manifest em Plugins/
    @Published var latest: [String: Release] = [:]           // id → última release no GitHub
    @Published var staged: [String: String] = [:]            // id → versão pronta para o próximo início
    @Published var busy: Set<String> = []
    @Published var detail: String?                           // id aberto no detalhe da Loja

    init(store: PluginStore = PluginStore(root: PluginStore.defaultRoot)) { self.store = store }
}

struct Sidebar: View {
    @ObservedObject var model: HubModel
    // Task 11 liga ao Acordado de verdade.
    private let awake = Binding<Bool>.constant(true)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text("ney").foregroundStyle(Grafite.strong) + Text("hub").foregroundStyle(Grafite.accent))
                .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                .padding(.horizontal, 6).padding(.bottom, 10)
            item(.store, title: "Loja") { symbol("bag") }
            item(.permissions, title: "Permissões") { symbol("lock.shield") }
            GSectionLabel("Instalados").padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 4)
            ForEach(model.loaded, id: \.manifest.id) { plugin in
                item(.app(plugin.manifest.id), title: plugin.manifest.name) {
                    AppIcon(name: plugin.manifest.name, id: plugin.manifest.id, size: 18)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("☾ Acordado").font(.system(size: 11)).foregroundStyle(Grafite.accent)
                Spacer()
                GSwitch(isOn: awake, label: "Acordado").allowsHitTesting(false).opacity(0.6)
            }
            .padding(.leading, 7).padding(.vertical, 1)
            .background(Grafite.awakeBg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.awakeBorder, lineWidth: 1))
        }
        .padding(.horizontal, 8).padding(.bottom, 12).padding(.top, 38) // 38: espaço dos botões da janela
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Grafite.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Grafite.border).frame(width: 1) }
    }

    private func item<Icon: View>(_ route: Route, title: String, @ViewBuilder icon: () -> Icon) -> some View {
        let selected = model.route == route
        return Button { model.route = route } label: {
            HStack(spacing: 7) {
                icon().frame(width: 18, height: 18)
                Text(title).font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Grafite.strong : Grafite.ghostText)
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(selected ? Grafite.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
            if model.route == .store {
                StoreView(model: model)
                    .padding(.horizontal, 16).padding(.top, 38)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                placeholder
            }
        }
        .foregroundStyle(Grafite.text)
        .background(Grafite.bg)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Grafite.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var title: String {
        switch model.route {
        case .store, .permissions: "Permissões"
        case .app(let id): model.loaded.first { $0.manifest.id == id }?.manifest.name ?? id
        }
    }

    private var subtitle: String {
        switch model.route {
        case .store, .permissions: "O que cada plugin pode acessar."
        case .app: "Em breve."
        }
    }
}

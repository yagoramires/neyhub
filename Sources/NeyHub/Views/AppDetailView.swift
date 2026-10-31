import AppKit
import NeyKit
import SwiftUI

/// Detalhe de um app da Loja: resumo, modo, configurações do plugin, novidades e Desinstalar.
struct AppDetailView: View {
    @ObservedObject var model: HubModel
    let entry: CatalogEntry
    /// nil = carregando; buscado só quando o detalhe abre (os snapshots injetam).
    @ViewState var notes: [Release]?

    init(model: HubModel, entry: CatalogEntry, notes: [Release]? = nil) {
        self.model = model; self.entry = entry; _notes = ViewState(wrappedValue: notes)
    }

    private var plugin: NeyPlugin? { model.loaded.first { $0.manifest.id == entry.id }?.plugin }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Button { model.detail = nil } label: {
                    Label("Loja", systemImage: "chevron.left").font(.system(size: 11)).foregroundStyle(Grafite.ghostText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voltar para a Loja")

                HStack(spacing: 10) {
                    AppIcon(name: entry.title, id: entry.id, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
                            .accessibilityAddTraits(.isHeader)
                        Text(model.status(entry)).font(.system(size: 11)).foregroundStyle(Grafite.muted)
                    }
                    Spacer()
                    StoreAction(model: model, entry: entry)
                    if model.installed[entry.id] != nil {
                        GPill(title: "Desinstalar", style: .ghost) { model.uninstall(entry.id) }
                            .accessibilityLabel("Desinstalar \(entry.title)")
                    }
                }
                Text(entry.summary).font(.system(size: 12))
                if let problem = model.problems[entry.id] { ProblemText(problem, model: model) }

                if model.installed[entry.id] != nil {
                    GSectionLabel("Modo")
                    PresencePicker(model: model, id: entry.id, name: entry.title, hasScreen: entry.hasScreen)
                }
                if let plugin {
                    GSectionLabel("Configurações")
                    PluginViewHost(make: plugin.makeSettings).frame(minHeight: 120)
                }
                GSectionLabel("Novidades")
                releaseNotes
            }
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if notes == nil, !entry.soon { notes = await Catalog.releases(repo: entry.repo) } }
    }

    @ViewBuilder private var releaseNotes: some View {
        if let notes, !notes.isEmpty {
            // Por posição: duas releases podem ter a mesma versão (tag repetida com prefixo diferente).
            ForEach(Array(notes.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 3) {
                    Text("v\(r.version)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Grafite.strong)
                    ForEach(Array(r.notes.split(separator: "\n").enumerated()), id: \.offset) { _, line in Self.noteLine(String(line)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(notes == nil ? "Carregando…" : "Sem novidades (ou sem conexão).").font(.system(size: 11)).foregroundStyle(Grafite.muted)
        }
    }

    /// Markdown por linha: "#…" vira rótulo, "- " vira "•", o resto passa por AttributedString (texto puro se não parsear).
    static func noteLine(_ raw: String) -> Text {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            return Text(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Grafite.label)
        }
        let body = line.hasPrefix("- ") || line.hasPrefix("* ") ? "• " + line.dropFirst(2) : line
        let text = (try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body)
        return Text(text).font(.system(size: 11)).foregroundStyle(Grafite.text)
    }
}

/// "Tela · Barra de menus · Os dois"; sem tela, só mostrar/esconder na barra. No detalhe da Loja e no topo da tela do app.
struct PresencePicker: View {
    @ObservedObject var model: HubModel
    let id: String, name: String, hasScreen: Bool

    var body: some View {
        let p = model.presence(id, hasScreen: hasScreen)
        if hasScreen {
            HStack(spacing: 6) {
                choice("Tela", Presence(screen: true, menuBar: false), current: p)
                choice("Barra de menus", Presence(screen: false, menuBar: true), current: p)
                choice("Os dois", Presence(screen: true, menuBar: true), current: p)
            }
        } else {
            HStack {
                Text("Mostrar na barra de menus").font(.system(size: 12))
                Spacer()
                GSwitch(isOn: Binding(get: { p.menuBar }, set: { model.setPresence(Presence(screen: false, menuBar: $0), id: id, hasScreen: false) }),
                        label: "Mostrar \(name) na barra de menus")
            }
        }
    }

    private func choice(_ title: String, _ value: Presence, current: Presence) -> some View {
        GPill(title: title, style: value == current ? .primary : .ghost) { model.setPresence(value, id: id, hasScreen: true) }
            .accessibilityLabel("Modo \(title)")
            .accessibilityAddTraits(value == current ? .isSelected : [])
    }
}

/// Embute um NSViewController do plugin (configurações e tela).
struct PluginViewHost: NSViewControllerRepresentable {
    let make: () -> NSViewController
    func makeNSViewController(context: Context) -> NSViewController { make() }
    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}

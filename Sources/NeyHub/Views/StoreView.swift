import AppKit
import NeyKit
import NeyKitApp
import SwiftUI

// MARK: - Ações da Loja

extension HubModel {
    static let catalogCache = PluginStore.defaultRoot.appendingPathComponent("catalog.json")

    /// Mostra o catálogo na hora (cache ou embutido) e só depois vai à rede, em segundo plano.
    func openStore() {
        let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json") ?? Self.catalogCache
        catalog = Catalog.load(cache: Self.catalogCache, bundled: bundled)
        reloadInstalled()
        staged = store.stagedVersions() // applyPending que falhou deixa Staged/: o aviso de reiniciar volta
        Task.detached { [self] in
            if let fresh = await Catalog.refresh(cache: Self.catalogCache) { await MainActor.run { self.catalog = fresh } }
            for e in await MainActor.run(body: { self.catalog }) where !e.soon { // "Em breve" não tem release: sem chamada à API
                if let r = await self.store.latest(e.repo) { await MainActor.run { self.latest[e.id] = r } }
            }
        }
    }

    /// Ciclo de atualização dos plugins (AppDelegate: 5 s depois de abrir, depois a cada 6 h). Pula cards ocupados.
    func checkPluginUpdates() {
        guard !checking else { return } // tique de 6 h não se sobrepõe a uma checagem lenta
        checking = true
        Task.detached { [self] in
            for e in await MainActor.run(body: { self.catalog }) where !e.soon {
                // Card ocupado (instalar/atualizar à mão) fica de fora; o ciclo marca o card enquanto baixa.
                guard await MainActor.run(body: { self.busy.insert(e.id).inserted }) else { continue }
                let result = await store.checkUpdates([e])
                await MainActor.run { self.busy.remove(e.id); self.absorb(result) }
            }
            await MainActor.run { self.checking = false }
        }
    }

    func absorb(_ result: (latest: [String: Release], staged: [String: String])) {
        latest.merge(result.latest) { _, new in new }
        staged.merge(result.staged) { _, new in new }
    }

    func reloadInstalled() {
        let manifests = store.installedFolders().compactMap(PluginStore.manifest(at:))
        installed = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func install(_ e: CatalogEntry) {
        run(e) {
            let url = try await self.store.install(e)
            // Reinstalado na mesma sessão: ficou em Staged/ e entra no próximo início. Senão começa já, como no início.
            if url.deletingLastPathComponent().lastPathComponent == "Staged" {
                if let m = PluginStore.manifest(at: url) { await MainActor.run { self.staged[e.id] = m.version } }
            } else {
                await MainActor.run { PluginHost.start(folder: url, model: self) }
            }
        }
    }

    func update(_ e: CatalogEntry) {
        guard let release = latest[e.id] else { return }
        run(e) {
            try await self.store.stageUpdate(e, release: release)
            await MainActor.run { self.staged[e.id] = release.version }
        }
    }

    /// Download e validação fora da main; card ocupado enquanto isso e erro legível no fim.
    private func run(_ e: CatalogEntry, _ op: @escaping () async throws -> Void) {
        guard !busy.contains(e.id) else { return }
        busy.insert(e.id)
        // Erro velho de instalar/baixar sai; "Pausado" é estado do plugin e fica até ele voltar.
        if ![PluginHost.paused, PluginHost.restartToResume].contains(problems[e.id]) { problems[e.id] = nil }
        Task.detached { [self] in
            let failure: String?
            do { try await op(); failure = nil } catch { failure = Self.text(error) }
            await MainActor.run {
                self.busy.remove(e.id)
                // Sucesso não apaga o que o início do plugin anotou; "Pausado" ganha do erro (o resume depende dele).
                if let failure, ![PluginHost.paused, PluginHost.restartToResume].contains(self.problems[e.id]) { self.problems[e.id] = failure }
                self.reloadInstalled()
            }
        }
    }

    static func text(_ error: Error) -> String {
        switch error as? StageError {
        case .download: "Não deu pra baixar — confira a conexão"
        case .manifest: "Pacote inválido"
        case .contract(let v): v > neyPluginContractVersion ? "Precisa atualizar o NeyHub" : "Versão antiga demais para este NeyHub"
        case .signature: "Assinatura não confere"
        case nil: "Não deu pra instalar"
        }
    }

    /// Pausado ou que não carregou não está em `loaded`: só marca.
    @MainActor func uninstall(_ id: String) {
        if let p = loaded.first(where: { $0.manifest.id == id }) { PluginHost.uninstall(p, store: store, model: self) } else { store.markForRemoval(id: id) }
        PluginHost.forget(id) // pausado não começa quando o avulso fechar
        staged[id] = nil
        problems[id] = nil // sem "Pausado" velho no card
        detail = nil
        reloadInstalled()
    }

    func presence(_ id: String, hasScreen: Bool) -> Presence {
        Presence.load(AppDefaults.forApp(id), hasScreen: hasScreen).normalized(hasScreen: hasScreen)
    }

    @MainActor func setPresence(_ p: Presence, id: String, hasScreen: Bool) {
        let p = p.normalized(hasScreen: hasScreen)
        p.save(AppDefaults.forApp(id))
        if let plugin = loaded.first(where: { $0.manifest.id == id }) { PluginHost.apply(p, to: plugin, model: self) }
        objectWillChange.send()
    }

    /// Pastas em `Plugins/` com manifest ilegível (problema guardado pelo nome da pasta, sem card do catálogo).
    var brokenFolders: [String] { problems.keys.filter { $0.hasSuffix(".neyplugin") }.sorted() }

    /// Nunca carregada (o manifest não abriu): dá para apagar já, sem esperar o reinício.
    @MainActor func removeBroken(_ folder: String) {
        if store.removeBroken(folder) { problems[folder] = nil }
    }

    /// Só quando a pessoa pede: reabre depois que este processo sair, e o applyPending do início aplica o Staged/.
    func restartNow() {
        _ = updater?.applyStaged() // o NeyHub novo, se houver; falha deixa o atual intacto
        Updater.relaunch(Bundle.main.bundleURL)
        NSApp.terminate(nil)
    }
}

// MARK: - Telas

struct StoreView: View {
    @ObservedObject var model: HubModel

    var body: some View {
        if let id = model.detail, let entry = model.catalog.first(where: { $0.id == id }) {
            AppDetailView(model: model, entry: entry)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Loja").font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Grafite.muted)
                if !model.staged.isEmpty || model.hubStaged != nil { StagedBanner(model: model).padding(.top, 10) }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 8) {
                        ForEach(model.catalog, id: \.id) { StoreCard(model: model, entry: $0) }
                        ForEach(model.brokenFolders, id: \.self) { BrokenCard(model: model, folder: $0) }
                    }
                    .padding(.bottom, 16)
                }
                .padding(.top, 10)
            }
        }
    }

    private var subtitle: String {
        let n = model.catalog.filter { !$0.soon }.count
        let i = model.catalog.filter { model.installed[$0.id] != nil }.count
        let u = model.catalog.filter { model.hasUpdate($0) }.count
        var parts = ["\(n) \(n == 1 ? "app" : "apps")", "\(i) \(i == 1 ? "instalado" : "instalados")"]
        if u > 0 { parts.append("\(u) \(u == 1 ? "atualização" : "atualizações")") }
        return parts.joined(separator: " · ")
    }
}

enum CardAction { case busy, soon, install, update, open, none }

extension HubModel {
    /// O que o card/detalhe oferece; "Em breve" nunca instala.
    func action(_ e: CatalogEntry) -> CardAction {
        if e.soon { return .soon }
        if busy.contains(e.id) { return .busy }
        if installed[e.id] == nil { return .install }
        if hasUpdate(e) { return .update }
        return detail == nil ? .open : .none
    }

    /// Instalado, release mais nova no GitHub e ainda não preparada.
    func hasUpdate(_ e: CatalogEntry) -> Bool {
        guard let m = installed[e.id], let r = latest[e.id], staged[e.id] == nil else { return false }
        return store.needsUpdate(installed: m, latest: r)
    }

    /// Linha de status do card e do detalhe (o VoiceOver lê junto com o nome).
    func status(_ e: CatalogEntry) -> String {
        if busy.contains(e.id) { return installed[e.id] == nil ? "Instalando…" : "Baixando atualização…" }
        if let v = staged[e.id] { return "v\(v) pronta — reinicie o NeyHub" }
        guard let m = installed[e.id] else { return e.summary }
        if hasUpdate(e), let r = latest[e.id] { return "\(m.version) → \(r.version)" }
        return "v\(m.version)"
    }
}

/// Ícone de letra com cor estável por id (o mesmo da sidebar).
struct AppIcon: View {
    let name: String, id: String, size: CGFloat
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Sidebar.color(for: id), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Instalar / Atualizar / Abrir, conforme o estado. Rótulo com o nome do app para o VoiceOver.
struct StoreAction: View {
    @ObservedObject var model: HubModel
    let entry: CatalogEntry

    var body: some View {
        switch model.action(entry) {
        case .busy: ProgressView().controlSize(.small).accessibilityLabel(model.status(entry))
        case .soon:
            Text("Em breve").font(.system(size: 10, weight: .bold)).foregroundStyle(Grafite.muted)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .overlay(Capsule().stroke(Grafite.ghostBorder, lineWidth: 1))
                .accessibilityLabel("\(entry.name), em breve")
        case .install: GPill(title: "Instalar") { model.install(entry) }.accessibilityLabel("Instalar \(entry.name)")
        case .update: GPill(title: "Atualizar") { model.update(entry) }.accessibilityLabel("Atualizar \(entry.name)")
        case .open: GPill(title: "Abrir", style: .ghost) { open() }.accessibilityLabel("Abrir \(entry.name)")
        case .none: EmptyView()
        }
    }

    /// Com tela e carregado: vai para a tela do app; senão, para o detalhe.
    private func open() {
        if entry.hasScreen, model.loaded.contains(where: { $0.manifest.id == entry.id }) { model.route = .app(entry.id) } else { model.detail = entry.id }
    }
}

struct StoreCard: View {
    @ObservedObject var model: HubModel
    let entry: CatalogEntry

    var body: some View {
        GCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    // "Em breve" não tem release: sem detalhe (que consultaria o GitHub).
                    if entry.soon { header } else {
                        Button { model.detail = entry.id } label: { header.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.name), \(model.status(entry))")
                            .accessibilityHint("Abre os detalhes")
                    }
                    StoreAction(model: model, entry: entry)
                }
                if model.installed[entry.id] != nil {
                    HStack {
                        Text("Barra de menus").font(.system(size: 11))
                        Spacer()
                        GSwitch(isOn: menuBar, label: "Barra de menus do \(entry.name)")
                    }
                    .padding(.top, 4)
                }
                if let problem = model.problems[entry.id] { ProblemText(problem, model: model).padding(.top, 6) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppIcon(name: entry.name, id: entry.id, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 11, weight: .bold)).foregroundStyle(Grafite.strong)
                Text(model.status(entry)).font(.system(size: 11)).foregroundStyle(Grafite.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var menuBar: Binding<Bool> {
        Binding(get: { model.presence(entry.id, hasScreen: entry.hasScreen).menuBar },
                set: { var p = model.presence(entry.id, hasScreen: entry.hasScreen); p.menuBar = $0; model.setPresence(p, id: entry.id, hasScreen: entry.hasScreen) })
    }
}

/// Aviso do card; parado por causa do avulso só volta reiniciando, então o botão vem junto.
struct ProblemText: View {
    let text: String
    let model: HubModel
    init(_ text: String, model: HubModel) { self.text = text; self.model = model }
    var body: some View {
        HStack(spacing: 6) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10)).foregroundStyle(Grafite.text)
                .accessibilityElement(children: .combine)
            if text == PluginHost.restartToResume {
                Spacer(minLength: 0)
                GPill(title: "Reiniciar NeyHub") { model.restartNow() }.accessibilityLabel("Reiniciar o NeyHub")
            }
        }
    }
}

/// Pasta em `Plugins/` cujo manifest não abre: não é de nenhum app do catálogo, então ganha um card só para remover.
struct BrokenCard: View {
    @ObservedObject var model: HubModel
    let folder: String
    var body: some View {
        GCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Pasta \(folder) com problema").font(.system(size: 11, weight: .bold)).foregroundStyle(Grafite.strong).lineLimit(1)
                    Spacer(minLength: 0)
                    GPill(title: "Remover", style: .ghost) { model.removeBroken(folder) }.accessibilityLabel("Remover a pasta \(folder)")
                }
                if let problem = model.problems[folder] { ProblemText(problem, model: model) }
            }
        }
    }
}

/// "Atualizações prontas — Reiniciar agora". O NeyHub nunca reinicia sozinho.
struct StagedBanner: View {
    @ObservedObject var model: HubModel
    var body: some View {
        HStack(spacing: 6) {
            Text("Atualizações prontas").font(.system(size: 11, weight: .semibold)).foregroundStyle(Grafite.accent)
            Text("— entram quando o NeyHub reiniciar").font(.system(size: 11)).foregroundStyle(Grafite.muted)
            Spacer()
            GPill(title: "Reiniciar agora") { model.restartNow() }.accessibilityLabel("Reiniciar o NeyHub agora")
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Grafite.awakeBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.awakeBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

import AppKit
import NeyKit
import SwiftUI

/// `NeyHub --snapshots <pasta>`: desenha componentes, janela vazia, Loja e detalhe em PNG e sai.
enum Snapshots {
    private struct Sample: View {
        @ViewState var on = true
        @ViewState var off = false
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("NEY").font(.system(size: 13, weight: .heavy)).foregroundStyle(Grafite.strong)
                GSectionLabel("Plugins")
                HStack(spacing: 8) {
                    GCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dose").font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
                            Text("Remédios no menu").font(.system(size: 11)).foregroundStyle(Grafite.muted)
                            HStack { GPill(title: "Ativo"); GPill(title: "Remover", style: .ghost); Spacer(); GSwitch(isOn: $on, label: "Dose") }
                        }
                    }
                    GCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Aero").font(.system(size: 16, weight: .semibold)).foregroundStyle(Grafite.strong)
                            Text("Janelas").font(.system(size: 11)).foregroundStyle(Grafite.muted)
                            HStack { GPill(title: "Instalar"); Spacer(); GSwitch(isOn: $off, label: "Aero") }
                        }
                    }
                }
                Text("Acordado")
                    .font(.system(size: 11)).foregroundStyle(Grafite.accent)
                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Grafite.awakeBg, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.awakeBorder, lineWidth: 1))
            }
            .padding(16)
            .frame(width: 420)
            .grafiteWindow()
        }
    }

    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        save(Sample(), as: "components.png", in: folder)
        save(RootView(model: HubModel()).frame(width: 900, height: 600), as: "window-empty.png", in: folder)

        // Loja com dados injetados: Aero instalado com atualização, Dose disponível.
        let shop = HubModel(store: PluginStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("nh-snapshots")))
        let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../catalog.json")
        shop.catalog = Catalog.decode((try? Data(contentsOf: bundled)) ?? Data()) ?? []
        shop.installed["local.aero"] = try? JSONDecoder().decode(PluginManifest.self, from: Data(
            #"{"id":"local.aero","name":"Aero","version":"0.5.0","contract":1,"hasScreen":false,"permissions":[],"binary":"libAero.dylib"}"#.utf8))
        let page = URL(string: "https://github.com/yagoramires/aero/releases")!
        shop.latest["local.aero"] = Release(version: "0.5.1", notes: "", page: page, assets: [:])
        saveHosted(RootView(model: shop), as: "store.png", in: folder)

        let notes = [Release(version: "0.5.1", notes: "### Corrigido\n- Encaixe em monitor **vertical**\n- Atalho ⌃⌥← no Sonoma", page: page, assets: [:]),
                     Release(version: "0.5.0", notes: "### Adicionado\n- Zonas de encaixe com prévia", page: page, assets: [:])]
        shop.staged["local.aero"] = "0.5.1"
        shop.detail = "local.aero"
        let detail = HStack(spacing: 0) {
            Sidebar(model: shop)
            AppDetailView(model: shop, entry: shop.catalog[0], notes: notes).padding(.horizontal, 16).padding(.top, 38)
        }
        saveHosted(detail.foregroundStyle(Grafite.text).background(Grafite.bg).environment(\.colorScheme, .dark),
                   as: "store-detail.png", in: folder)

        // Permissões: Aero e Dose pedem; acessibilidade concedida, o resto não.
        let perms = HubModel(store: PluginStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("nh-snapshots")))
        func manifest(_ id: String, _ name: String, _ list: String) -> PluginManifest {
            try! JSONDecoder().decode(PluginManifest.self, from: Data(
                #"{"id":"\#(id)","name":"\#(name)","version":"1.0.0","contract":1,"hasScreen":false,"permissions":\#(list),"binary":"l.dylib"}"#.utf8))
        }
        perms.installed["local.aero"] = manifest("local.aero", "Aero", #"["accessibility","screenRecording"]"#)
        perms.installed["local.dose"] = manifest("local.dose", "Dose", #"["notifications"]"#)
        perms.granted = [.accessibility: true, .screenRecording: false, .notifications: false]
        perms.route = .permissions
        saveHosted(RootView(model: perms), as: "permissions.png", in: folder)
        perms.route = .settings
        saveHosted(RootView(model: perms), as: "settings.png", in: folder)
        print("ok \(folder.path)")
    }

    /// Plugin de mentira do tour: a tela é a imagem que o próprio app desenhou com dados de exemplo.
    private final class TourPlugin: NSObject, NeyPlugin {
        let image: NSImage?
        init(image: NSImage?) { self.image = image }
        var contractVersion: Int { neyPluginContractVersion }
        func start(host: NeyHost) {}
        func stop() {}
        func setMenuBarVisible(_ visible: Bool) {}
        func makeScreen() -> NSViewController? {
            let vc = NSViewController()
            let view = NSImageView()
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageAlignment = .alignTopLeft
            // A imagem pode ser maior que a área: sem isto o NSImageView exige o tamanho dela e some.
            for o in [NSLayoutConstraint.Orientation.horizontal, .vertical] { view.setContentCompressionResistancePriority(.defaultLow, for: o) }
            vc.view = view
            return vc
        }
        func makeSettings() -> NSViewController { NSViewController() }
    }

    /// Janela padrão (1100 × 680) com os seis apps instalados: Loja, a tela de cada app com tela e Permissões.
    /// Nenhum dado real: o catálogo é o embutido e as telas vêm de `screens/<app>.png`.
    static func tour(into folder: URL, screens: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../catalog.json")
        let catalog = Catalog.decode((try? Data(contentsOf: bundled)) ?? Data()) ?? []
        let permissions: [String: String] = ["local.aero": #"["accessibility"]"#, "local.dose": #"["notifications"]"#,
                                             "local.capture": #"["screenRecording","microphone"]"#, "local.deck": #"["accessibility"]"#,
                                             "local.pauta": #"["notifications"]"#, "local.hub": "[]"]
        // Um modelo novo por quadro: reaproveitado, um quadro herdava o estado do anterior e saía em branco.
        func makeModel() -> HubModel { MainActor.assumeIsolated {
            let model = HubModel(store: PluginStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("nh-tour")))
            model.catalog = catalog
            for e in catalog {
                let m = try! JSONDecoder().decode(PluginManifest.self, from: Data(
                    #"{"id":"\#(e.id)","name":"\#(e.name)","displayName":"\#(e.title)","version":"0.2.0","contract":1,"hasScreen":\#(e.hasScreen),"permissions":\#(permissions[e.id] ?? "[]"),"binary":"l.dylib"}"#.utf8))
                model.installed[e.id] = m
                let key = e.id.split(separator: ".").last.map(String.init) ?? e.id
                model.loaded.append(LoadedPlugin(manifest: m, plugin: TourPlugin(image: NSImage(contentsOf: screens.appendingPathComponent("\(key).png"))),
                                                 folder: URL(fileURLWithPath: "/")))
                model.presences[e.id] = Presence(screen: e.hasScreen, menuBar: true)
            }
            model.granted = [.accessibility: true, .notifications: true, .screenRecording: true, .microphone: false]
            return model
        } }
        let size = CGSize(width: 1100, height: 680)
        let routes: [(String, Route)] = [("1-loja", .store)]
            + catalog.filter(\.hasScreen).enumerated().map { ("\($0.offset + 2)-\($0.element.name.lowercased())", .app($0.element.id)) }
            + [("9-permissoes", .permissions)]
        for (name, route) in routes {
            let model = makeModel()
            MainActor.assumeIsolated { model.route = route }
            saveHosted(RootView(model: model).frame(width: size.width, height: size.height), as: "\(name).png", in: folder, size: size)
        }
        print("ok \(folder.path)")
    }

    /// ImageRenderer não desenha ScrollView/LazyVGrid: aqui a view vai numa janela fora da tela e é capturada como o app real.
    private static func saveHosted<V: View>(_ view: V, as name: String, in folder: URL, size: CGSize = CGSize(width: 900, height: 600)) {
        MainActor.assumeIsolated {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("falhou \(name)"); exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            window.orderOut(nil)
            guard let png = rep.representation(using: .png, properties: [:]) else { print("falhou \(name)"); exit(1) }
            try? png.write(to: folder.appendingPathComponent(name))
        }
    }

    private static func save<V: View>(_ view: V, as name: String, in folder: URL) {
        let renderer = MainActor.assumeIsolated { ImageRenderer(content: view) }
        MainActor.assumeIsolated { renderer.scale = 2 }
        guard let image = MainActor.assumeIsolated({ renderer.nsImage }), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("falhou \(name)"); exit(1)
        }
        try? png.write(to: folder.appendingPathComponent(name))
    }
}

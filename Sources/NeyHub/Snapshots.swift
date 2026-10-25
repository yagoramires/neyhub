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
        print("ok \(folder.path)")
    }

    /// ImageRenderer não desenha ScrollView/LazyVGrid: aqui a view vai numa janela fora da tela e é capturada como o app real.
    private static func saveHosted<V: View>(_ view: V, as name: String, in folder: URL) {
        MainActor.assumeIsolated {
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 900, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
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

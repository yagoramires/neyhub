import AppKit
import NeyKit
import SwiftUI

/// `NeyHub --snapshots <pasta>`: desenha os componentes Grafite em components.png e sai.
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
        print("ok \(folder.path)")
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

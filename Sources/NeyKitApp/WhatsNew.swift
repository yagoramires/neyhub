import AppKit
import NeyKit
import SwiftUI

/// Janela "Novidades" no tema Grafite, mostrada uma vez depois de atualizar.
public enum WhatsNew {
    private static var window: NSWindow?

    public static func show(name: String, version: String, notes: String) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Novidades do \(name)"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(Grafite.bg)
        w.contentView = NSHostingView(rootView: NotesView(title: "\(name) \(version)", notes: notes) { window?.close() })
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

/// Markdown do CHANGELOG: títulos (#), itens (- ou *) e o resto como parágrafo com negrito/itálico/links.
struct NotesView: View {
    let title: String, notes: String, close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GSectionLabel("Novidades")
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(Grafite.strong)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notes.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in row(line) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); GPill(title: "OK", action: close) }
        }
        .padding(EdgeInsets(top: 34, leading: 20, bottom: 16, trailing: 20))
        .frame(minWidth: 420, minHeight: 360)
        .grafiteWindow()
    }

    @ViewBuilder func row(_ line: String) -> some View {
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") {
            Text(inline(String(text.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Grafite.strong).padding(.top, 4)
        } else if text.hasPrefix("- ") || text.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(Grafite.accent)
                Text(inline(String(text.dropFirst(2))))
            }
            .font(.system(size: 12))
        } else if !text.isEmpty {
            Text(inline(text)).font(.system(size: 12))
        }
    }

    func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

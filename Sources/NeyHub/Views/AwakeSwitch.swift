import AppKit
import Combine
import NeyKit
import NeyKitApp
import SwiftUI

/// Estado do Acordado: sempre o do sistema (`pmset -g`), nunca um valor salvo.
final class AwakeModel: ObservableObject {
    @Published private(set) var on = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published var showInMenuBar = AppDefaults.forApp("local.neyhub").bool(forKey: AwakeModel.menuBarKey) {
        didSet { AppDefaults.forApp("local.neyhub").set(showInMenuBar, forKey: Self.menuBarKey) }
    }
    static let menuBarKey = "awakeMenuBar"
    private var wake: NSObjectProtocol?

    init() {
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !busy else { return }
        Task { @MainActor in
            let v = await Task.detached { Awake.isEnabled() }.value
            if !busy, v != on { on = v } // só publica se mudou
        }
    }

    func toggle(to value: Bool) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            do { try await Task.detached { try Awake.set(value) }.value }
            catch AwakeError.cancelled {} // o usuário desistiu: o switch só volta ao estado real
            catch AwakeError.failed(let msg) { error = "Falhou: " + (msg.split(separator: "\n").first.map(String.init) ?? "sem detalhe") }
            catch { self.error = "Falhou: \(error.localizedDescription)" }
            on = await Task.detached { Awake.isEnabled() }.value
            busy = false
        }
    }
}

/// Switch do rodapé da sidebar. Opção da barra de menus no menu de contexto (NeyHub ainda não tem tela de ajustes).
struct AwakeSwitch: View {
    @ObservedObject var awake: AwakeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("☾ Acordado").font(.system(size: 11)).foregroundStyle(Grafite.accent)
                Spacer()
                GSwitch(isOn: Binding(get: { awake.on }, set: { awake.toggle(to: $0) }), label: "Acordado")
                    .disabled(awake.busy).opacity(awake.busy ? 0.6 : 1)
            }
            .padding(.leading, 7).padding(.vertical, 1)
            .background(Grafite.awakeBg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.awakeBorder, lineWidth: 1))
            .contextMenu { Toggle("Mostrar Acordado na barra de menus", isOn: $awake.showInMenuBar) }
            if let e = awake.error {
                Text(e).font(.system(size: 10)).foregroundStyle(Grafite.muted).lineLimit(2).padding(.horizontal, 4)
            }
        }
        // O SwiftUI cancela a task ao sair da tela: só consulta com a janela aberta.
        .task { while !Task.isCancelled { awake.refresh(); try? await Task.sleep(for: .seconds(10)) } }
    }
}

/// Ícone opcional na barra de menus; o menu relê o estado ao abrir.
final class AwakeStatusItem: NSObject, NSMenuDelegate {
    private let awake: AwakeModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggle = NSMenuItem(title: "Acordado", action: #selector(flip), keyEquivalent: "")
    private var sub: AnyCancellable?

    init(awake: AwakeModel) {
        self.awake = awake
        super.init()
        toggle.target = self
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(toggle)
        item.menu = menu
        sub = awake.$on.sink { [weak self] on in self?.render(on) }
    }

    deinit { NSStatusBar.system.removeStatusItem(item) }

    private func render(_ on: Bool) {
        toggle.state = on ? .on : .off
        item.button?.image = NSImage(systemSymbolName: on ? "moon.zzz.fill" : "moon.zzz", accessibilityDescription: on ? "Acordado ligado" : "Acordado desligado")
    }

    func menuWillOpen(_ menu: NSMenu) { awake.refresh() }
    @objc private func flip() { awake.toggle(to: !awake.on) }
}

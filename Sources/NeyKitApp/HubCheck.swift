import AppKit
import ServiceManagement

/// Checagem inversa do §5.5: o avulso não roda junto com o próprio plugin ativo no NeyHub.
public enum HubCheck {
    /// Ids iniciados pelo NeyHub nesta sessão (array JSON de strings); os testes trocam o caminho.
    static var activeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NeyHub/active.json")

    /// NeyHub rodando (outro processo que não este) e com `id` ativo.
    public static func isHosted(id: String) -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let hub = NSRunningApplication.runningApplications(withBundleIdentifier: "local.neyhub").contains { $0.processIdentifier != me }
        return hub && isActive(id)
    }

    /// Ilegível ou fora do formato conta como não ativo.
    static func isActive(_ id: String) -> Bool {
        guard let data = try? Data(contentsOf: activeURL), let ids = try? JSONDecoder().decode([String].self, from: data) else { return false }
        return ids.contains(id)
    }

    /// Tira o avulso dos itens de login, avisa e encerra.
    public static func leaveForHub(name: String) {
        try? SMAppService.mainApp.unregister() // não registrado é o caso comum; nada a fazer
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "O \(name) já roda no NeyHub"
        alert.informativeText = "Para não rodar duas vezes, esta cópia vai fechar."
        alert.addButton(withTitle: "Abrir NeyHub")
        alert.addButton(withTitle: "Sair")
        if alert.runModal() == .alertFirstButtonReturn,
           let hub = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "local.neyhub") {
            NSWorkspace.shared.open(hub)
        }
        NSApp.terminate(nil)
    }
}

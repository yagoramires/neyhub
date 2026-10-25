import Foundation
import NeyKit

/// Ponte que o NeyHub entrega a cada plugin em `start(host:)`.
final class HostBridge: NSObject, NeyHost {
    private(set) var messages: [String] = []

    /// O AppDelegate liga: abre a janela na tela de Permissões.
    var onOpenPermissions: (() -> Void)?

    func openPermissions() { onOpenPermissions?() }

    func log(_ message: String) {
        messages.append(message)
        print("[plugin] \(message)")
    }
}

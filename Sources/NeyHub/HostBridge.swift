import Foundation
import NeyKit

/// Ponte que o NeyHub entrega a cada plugin em `start(host:)`. Task 9/10 ligam Permissões e o log de verdade.
final class HostBridge: NSObject, NeyHost {
    private(set) var messages: [String] = []

    func openPermissions() { log("openPermissions pedido") }

    func log(_ message: String) {
        messages.append(message)
        print("[plugin] \(message)")
    }
}

import AppKit
import UserNotifications

/// O NeyHub é o único `UNUserNotificationCenter.delegate`: o macOS só conhece o app hospedeiro, não o plugin.
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    private let model: HubModel
    init(model: HubModel) { self.model = model }

    /// Dono de `<id>.<resto>`: o plugin de id mais longo seguido de ".". `local.dosex.1` não é do `local.dose`.
    static func owner(of identifier: String, among ids: [String]) -> String? {
        ids.filter { identifier.hasPrefix($0 + ".") }.max { $0.count < $1.count }
    }

    /// Categorias de todos os plugins num conjunto só (o sistema guarda uma lista por app); id repetido: o primeiro plugin ganha.
    static func merge(_ lists: [(plugin: String, categories: Set<UNNotificationCategory>)]) -> Set<UNNotificationCategory> {
        var seen: [String: String] = [:], out: Set<UNNotificationCategory> = []
        for (plugin, categories) in lists {
            for c in categories.sorted(by: { $0.identifier < $1.identifier }) {
                if let first = seen[c.identifier] { NSLog("NeyHub: categoria '\(c.identifier)' de \(plugin) ignorada (já é de \(first))"); continue }
                seen[c.identifier] = plugin
                out.insert(c)
            }
        }
        return out
    }

    /// Delegate cedo (resposta que abriu o app chega no lançamento); categorias a cada plugin que começa (`PluginHost.begin`).
    func install() { UNUserNotificationCenter.current().delegate = self }

    @MainActor func registerCategories() {
        let lists = model.loaded.map { ($0.manifest.id, $0.plugin.notificationCategories?() ?? []) }
        UNUserNotificationCenter.current().setNotificationCategories(Self.merge(lists))
    }

    /// Ids dos avisos na Central e a remoção; o selftest troca para nunca tocar na central de verdade.
    var delivered: (@escaping ([String]) -> Void) -> Void = { done in
        UNUserNotificationCenter.current().getDeliveredNotifications { done($0.map(\.request.identifier)) }
    }
    var remove: ([String]) -> Void = { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: $0) }

    /// Desinstalar tira da Central os avisos do plugin. O `stop()` não tira: sair do NeyHub também o chama.
    @MainActor func removeDelivered(of id: String) {
        let ids = model.loaded.map(\.manifest.id) + [id], remove = remove
        delivered { list in
            let mine = list.filter { Self.owner(of: $0, among: ids) == id }
            if !mine.isEmpty { remove(mine) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let identifier = response.notification.request.identifier, action = response.actionIdentifier
        nonisolated(unsafe) let done = done
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.receive(identifier, action)
                done()
            }
        }
    }

    /// Toques que chegaram antes de os plugins iniciarem (o aviso pode abrir o NeyHub): entregues no `finishStart`.
    private var pending: [(identifier: String, action: String)] = []
    private var started = false

    @MainActor func receive(_ identifier: String, _ action: String) {
        guard started else { return pending.append((identifier, action)) }
        let ids = model.loaded.map(\.manifest.id)
        if let id = Self.owner(of: identifier, among: ids), let p = model.loaded.first(where: { $0.manifest.id == id }) {
            p.plugin.handleNotification?(identifier: identifier, actionIdentifier: action)
        }
    }

    @MainActor func finishStart() {
        started = true
        let queued = pending; pending = []
        for t in queued { receive(t.identifier, t.action) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }
}

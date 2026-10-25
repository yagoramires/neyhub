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

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let identifier = response.notification.request.identifier, action = response.actionIdentifier
        nonisolated(unsafe) let done = done
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let ids = self.model.loaded.map(\.manifest.id)
                if let id = Self.owner(of: identifier, among: ids), let p = self.model.loaded.first(where: { $0.manifest.id == id }) {
                    p.plugin.handleNotification?(identifier: identifier, actionIdentifier: action)
                }
                done()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }
}

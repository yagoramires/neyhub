import AppKit
import UserNotifications

/// Versão do contrato que este NeyKit fala. Plugin com `contract` diferente não é carregado.
public let neyPluginContractVersion = 1

/// O que o NeyHub oferece ao plugin.
@objc public protocol NeyHost: NSObjectProtocol {
    func openPermissions()                 // leva o NeyHub para a tela de Permissões
    func log(_ message: String)
}

/// Objeto devolvido pelo símbolo `neyhub_plugin_v1` do dylib. A classe mora no módulo do plugin.
@objc public protocol NeyPlugin: NSObjectProtocol {
    var contractVersion: Int { get }
    func start(host: NeyHost)              // começa o trabalho de fundo; chamado uma vez por processo
    func stop()                            // tira ícone, event taps, atalhos, timers (desinstalar)
    func setMenuBarVisible(_ visible: Bool)// false REMOVE o NSStatusItem; true cria com autosaveName = id
    func makeScreen() -> NSViewController? // nil = só barra (Aero, Capture)
    func makeSettings() -> NSViewController
    @objc optional func notificationCategories() -> Set<UNNotificationCategory>
    @objc optional func handleNotification(identifier: String, actionIdentifier: String)
}

/// `<Nome>.neyplugin/manifest.json`.
public struct PluginManifest: Codable, Equatable {
    public let id: String, name: String, version: String, contract: Int, hasScreen: Bool
    public let permissions: [String]       // Task 10 troca por [Permission]
    public let binary: String              // só nome de arquivo: sem "/" e sem ".."

    /// `binary` é nome simples (não sai da pasta) e id/nome não vazios.
    public var isValid: Bool {
        !id.isEmpty && !name.isEmpty && !binary.isEmpty && binary != "."
            && !binary.contains("/") && !binary.contains("..")
    }
}

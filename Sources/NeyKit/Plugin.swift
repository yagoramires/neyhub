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
    public let permissions: [Permission]
    public let binary: String              // só nome de arquivo: sem "/" e sem ".."

    private enum CodingKeys: String, CodingKey { case id, name, version, contract, hasScreen, permissions, binary }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version); contract = try c.decode(Int.self, forKey: .contract)
        hasScreen = try c.decode(Bool.self, forKey: .hasScreen); binary = try c.decode(String.self, forKey: .binary)
        // Permissão de um NeyHub mais novo não pode impedir o carregamento: descarta e avisa no log.
        let raw = try c.decode([String].self, forKey: .permissions)
        let known = raw.compactMap(Permission.init(rawValue:))
        let unknown = raw.filter { Permission(rawValue: $0) == nil }
        if !unknown.isEmpty { NSLog("NeyHub: permissões desconhecidas em \(try c.decode(String.self, forKey: .id)): \(unknown)") }
        permissions = known
    }

    /// id seguro (`PluginSignature.isSafeID`); `name` (vira `<Nome>.neyplugin`) e `binary` são nomes simples, não saem da pasta.
    public var isValid: Bool { PluginSignature.isSafeID(id) && Self.isPlainName(name) && Self.isPlainName(binary) }

    private static func isPlainName(_ s: String) -> Bool { !s.isEmpty && s != "." && !s.contains("/") && !s.contains("..") }
}

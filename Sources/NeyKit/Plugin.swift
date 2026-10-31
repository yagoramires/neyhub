import AppKit
import UserNotifications

/// Versão do contrato que este NeyKit fala. Plugin com `contract` diferente não é carregado.
public let neyPluginContractVersion = 1

/// O que o NeyHub oferece ao plugin.
@objc public protocol NeyHost: NSObjectProtocol {
    func openPermissions()                 // leva o NeyHub para a tela de Permissões
    func log(_ message: String)
    /// Mostra a tela do app `id` na janela do NeyHub (ou o card dele na Loja, se o modo não tem tela).
    /// Opcional: o contrato continua v1; o plugin confere com `responds(to:)` antes de contar com ele.
    @objc optional func showScreen(id: String)
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
    /// URL `hubmac://…` que o NeyHub recebeu (retorno de login); true = este plugin tratou.
    @objc optional func handleURL(_ url: URL) -> Bool
}

/// `<Nome>.neyplugin/manifest.json`.
public struct PluginManifest: Codable, Equatable {
    public let id: String, name: String, version: String, contract: Int, hasScreen: Bool
    public let permissions: [Permission]
    public let binary: String              // só nome de arquivo: sem "/" e sem ".."
    /// Versão mínima do macOS ("15.0"), opcional. Conferida antes do dlopen: dylib feito para um macOS mais novo não carrega.
    public let minMacOS: String?
    /// Nome que aparece (opcional): `name` continua sendo a pasta e o asset. NeyHub antigo ignora.
    public let displayName: String?
    public var title: String { displayName.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? name }

    private enum CodingKeys: String, CodingKey { case id, name, version, contract, hasScreen, permissions, binary, minMacOS, displayName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version); contract = try c.decode(Int.self, forKey: .contract)
        hasScreen = try c.decode(Bool.self, forKey: .hasScreen); binary = try c.decode(String.self, forKey: .binary)
        minMacOS = try c.decodeIfPresent(String.self, forKey: .minMacOS)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        // Permissão de um NeyHub mais novo não pode impedir o carregamento: descarta e avisa no log.
        let raw = try c.decode([String].self, forKey: .permissions)
        let known = raw.compactMap(Permission.init(rawValue:))
        let unknown = raw.filter { Permission(rawValue: $0) == nil }
        if !unknown.isEmpty { NSLog("NeyHub: permissões desconhecidas em \(try c.decode(String.self, forKey: .id)): \(unknown)") }
        permissions = known
    }

    /// id seguro (`PluginSignature.isSafeID`); `name` (vira `<Nome>.neyplugin`) e `binary` são nomes simples, não saem da pasta;
    /// `minMacOS`, quando vem, é uma versão legível.
    public var isValid: Bool {
        PluginSignature.isSafeID(id) && Self.isPlainName(name) && Self.isPlainName(binary) && (minMacOS.map { Self.osVersion($0) != nil } ?? true)
    }

    /// Roda neste macOS: sem `minMacOS`, sempre.
    public func runs(on os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        guard let min = minMacOS.flatMap(Self.osVersion) else { return true }
        return (os.majorVersion, os.minorVersion, os.patchVersion) >= (min.majorVersion, min.minorVersion, min.patchVersion)
    }

    /// "15" / "15.0" / "15.0.1" → versão; qualquer outra coisa → nil.
    static func osVersion(_ s: String) -> OperatingSystemVersion? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        let n = parts.map { $0! } + [0, 0]
        return OperatingSystemVersion(majorVersion: n[0], minorVersion: n[1], patchVersion: n[2])
    }

    private static func isPlainName(_ s: String) -> Bool { !s.isEmpty && s != "." && !s.contains("/") && !s.contains("..") }
}

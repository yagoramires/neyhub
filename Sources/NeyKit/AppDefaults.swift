import Foundation

public enum AppDefaults {
    /// Padrões do app `id`. No próprio app usa `.standard`: `UserDefaults(suiteName:)` com o bundle id do processo devolve nil.
    public static func forApp(_ id: String) -> UserDefaults {
        if id == Bundle.main.bundleIdentifier { return .standard }
        return UserDefaults(suiteName: id) ?? .standard // nil só em ids inválidos; .standard evita crash
    }
}

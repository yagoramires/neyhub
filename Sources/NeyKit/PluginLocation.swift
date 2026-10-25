import Foundation

/// Onde o plugin mora, achado pelo endereço do próprio dylib: o plugin nunca lê `Bundle.main` (é o do NeyHub).
/// Quem chama passa `#dsohandle` de dentro do plugin.
public enum PluginLocation {
    /// A pasta `<Nome>.neyplugin` (a que guarda o dylib); nil se o `dladdr` falhar.
    public static func folder(dso: UnsafeRawPointer) -> URL? {
        var info = Dl_info()
        guard dladdr(dso, &info) != 0, let path = info.dli_fname else { return nil }
        return URL(fileURLWithPath: String(cString: path)).deletingLastPathComponent()
    }

    /// Versão do `manifest.json` ao lado do dylib (o release.sh grava nele a do Info.plist); "?" se não abrir.
    public static func version(dso: UnsafeRawPointer) -> String {
        guard let manifest = folder(dso: dso)?.appendingPathComponent("manifest.json") else { return "?" }
        return (try? JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifest)))?.version ?? "?"
    }

    /// `<Nome>.neyplugin/Resources`, se existir (o release copia `Resources/Bundle/` para lá).
    public static func resources(dso: UnsafeRawPointer) -> URL? {
        guard let dir = folder(dso: dso)?.appendingPathComponent("Resources", isDirectory: true) else { return nil }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue ? dir : nil
    }
}

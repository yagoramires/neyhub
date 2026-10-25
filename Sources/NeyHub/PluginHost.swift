import Foundation
import NeyKit

enum LoadError: Error, Equatable { case manifest, signature, contractTooNew(Int), contractTooOld(Int), symbol, notAPlugin, alreadyLoaded }

struct LoadedPlugin { let manifest: PluginManifest; let plugin: NeyPlugin; let folder: URL }

/// Carrega `<Nome>.neyplugin`. Só da main thread.
enum PluginHost {
    /// ids cujo dylib já foi aberto: o entry de um id nunca roda duas vezes no mesmo processo.
    private static var loadedIDs: Set<String> = []
    /// Quantas vezes chamamos dlopen (o selftest garante que plugin rejeitado não chega lá).
    private(set) static var dlopenCount = 0

    static func load(folder: URL) -> Result<LoadedPlugin, LoadError> {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data), manifest.isValid
        else { return .failure(.manifest) }
        if manifest.contract > neyPluginContractVersion { return .failure(.contractTooNew(manifest.contract)) }
        if manifest.contract < neyPluginContractVersion { return .failure(.contractTooOld(manifest.contract)) }
        let binary = folder.appendingPathComponent(manifest.binary)
        guard PluginSignature.isTrustedPlugin(binary) else { return .failure(.signature) }
        guard !loadedIDs.contains(manifest.id) else { return .failure(.alreadyLoaded) }

        dlopenCount += 1
        // shortcut: assinatura conferida antes do dlopen; troca do arquivo entre os dois passos não é tratada (pasta é do usuário).
        guard let handle = dlopen(binary.path, RTLD_NOW) else { return .failure(.symbol) }
        loadedIDs.insert(manifest.id)
        guard let symbol = dlsym(handle, "neyhub_plugin_v1") else { return .failure(.symbol) }
        typealias Entry = @convention(c) () -> UnsafeMutableRawPointer
        let object = Unmanaged<AnyObject>.fromOpaque(unsafeBitCast(symbol, to: Entry.self)()).takeRetainedValue()
        guard let plugin = object as? NeyPlugin else { return .failure(.notAPlugin) }
        return .success(LoadedPlugin(manifest: manifest, plugin: plugin, folder: folder))
    }
}

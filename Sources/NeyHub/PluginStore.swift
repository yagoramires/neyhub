import Foundation
import NeyKit

enum StageError: Error, Equatable { case download, manifest, contract(Int), signature }

/// Pastas do NeyHub: `Plugins/<Nome>.neyplugin` (instalados), `Staged/<Nome>.neyplugin` (entram no próximo início),
/// `Incoming/<uuid>/` (download em andamento), `Remove/<id>` (marcador de desinstalação).
/// Nomes de pasta vêm do `name` do manifest; o id de uma pasta sempre sai do manifest.json dela.
final class PluginStore {
    static let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NeyHub")

    let root: URL
    /// `/releases/latest` do repo; os testes trocam por um file://.
    var latestURL: (String) -> URL = Release.latestURL(repo:)
    private let fm = FileManager.default

    init(root: URL) { self.root = root }

    private func dir(_ name: String) -> URL { root.appendingPathComponent(name) }

    static func manifest(at folder: URL) -> PluginManifest? {
        (try? Data(contentsOf: folder.appendingPathComponent("manifest.json"))).flatMap { try? JSONDecoder().decode(PluginManifest.self, from: $0) }
    }

    private func bundles(in name: String) -> [URL] {
        ((try? fm.contentsOfDirectory(at: dir(name), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "neyplugin" }.sorted { $0.path < $1.path }
    }

    private var removalIDs: Set<String> { Set((try? fm.contentsOfDirectory(atPath: dir("Remove").path)) ?? []) }

    /// `Plugins/*.neyplugin` menos os marcados em `Remove/`.
    func installedFolders() -> [URL] {
        let removed = removalIDs
        return bundles(in: "Plugins").filter { Self.manifest(at: $0).map { !removed.contains($0.id) } ?? true }
    }

    /// id → versão em `Staged/`, menos os marcados para remoção.
    func stagedVersions() -> [String: String] {
        let removed = removalIDs
        let ms = bundles(in: "Staged").compactMap(Self.manifest(at:)).filter { !removed.contains($0.id) }
        return Dictionary(ms.map { ($0.id, $0.version) }, uniquingKeysWith: { a, _ in a })
    }

    /// Manifest válido, contrato igual ao nosso e binário com a assinatura fixa.
    func validate(folder: URL) -> Result<PluginManifest, StageError> {
        guard let m = Self.manifest(at: folder), m.isValid else { return .failure(.manifest) }
        guard m.contract == neyPluginContractVersion else { return .failure(.contract(m.contract)) }
        guard PluginSignature.isTrustedPlugin(folder.appendingPathComponent(m.binary)) else { return .failure(.signature) }
        return .success(m)
    }

    /// Última release do repo; nil sem rede ou resposta inesperada.
    func latest(_ repo: String) async -> Release? {
        guard let (data, _) = try? await URLSession.shared.data(for: Catalog.request(latestURL(repo))) else { return nil }
        return Release.parse(data)
    }

    /// Baixa a última release e põe em `Plugins/`. Se a pasta já existe (desinstalado nesta sessão, ainda carregado),
    /// vai para `Staged/` e entra no próximo início.
    func install(_ e: CatalogEntry) async throws -> URL {
        guard let release = await latest(e.repo) else { throw StageError.download }
        let url = try await receive(e, release, into: "Plugins")
        try? fm.removeItem(at: dir("Remove").appendingPathComponent(e.id)) // só depois de dar certo: falha não ressuscita o desinstalado
        return url
    }

    /// Prepara a versão nova em `Staged/`; incompatível ou mal assinada não é preparada (o erro vai para o card).
    func stageUpdate(_ e: CatalogEntry, release: Release) async throws {
        _ = try await receive(e, release, into: "Staged")
    }

    func needsUpdate(installed: PluginManifest, latest: Release) -> Bool { Release.isNewer(latest.version, than: installed.version) }

    func markForRemoval(id: String) {
        guard PluginSignature.isSafeID(id) else { return }
        try? fm.createDirectory(at: dir("Remove"), withIntermediateDirectories: true)
        fm.createFile(atPath: dir("Remove").appendingPathComponent(id).path, contents: nil)
    }

    /// Chamar ANTES de carregar plugins. Marcados em `Remove/` saem de `Plugins/` e `Staged/`; depois `Staged/*` substitui
    /// `Plugins/*` com `replaceItemAt` (nunca apaga antes de mover): se a troca falha, o antigo continua.
    func applyPending() {
        try? fm.removeItem(at: dir("Incoming")) // órfãos de download/lixeira interrompidos; no início nada está baixando
        let removed = removalIDs
        var stuck = Set<String>() // remoção falhou: mantém o marcador, senão o desinstalado volta no próximo início
        for folder in bundles(in: "Plugins") + bundles(in: "Staged") {
            guard let id = Self.manifest(at: folder)?.id, removed.contains(id) else { continue }
            // Move para fora (atômico) antes de apagar: falha no meio não deixa uma pasta pela metade em Plugins/.
            let trash = dir("Incoming").appendingPathComponent(UUID().uuidString)
            do {
                try fm.createDirectory(at: dir("Incoming"), withIntermediateDirectories: true)
                try fm.moveItem(at: folder, to: trash)
                try? fm.removeItem(at: trash)
            } catch {
                stuck.insert(id)
                NSLog("NeyHub: não deu pra remover \(folder.lastPathComponent): \(error)")
            }
        }
        for id in removed.subtracting(stuck) { try? fm.removeItem(at: dir("Remove").appendingPathComponent(id)) }
        try? fm.createDirectory(at: dir("Plugins"), withIntermediateDirectories: true)
        for staged in bundles(in: "Staged") {
            let dest = dir("Plugins").appendingPathComponent(staged.lastPathComponent)
            do {
                if fm.fileExists(atPath: dest.path) { _ = try fm.replaceItemAt(dest, withItemAt: staged) } else { try fm.moveItem(at: staged, to: dest) }
            } catch {
                NSLog("NeyHub: não deu pra aplicar \(staged.lastPathComponent): \(error)")
            }
        }
    }

    /// Baixa `<Nome>-<v>.neyplugin`, descompacta em `Incoming/<uuid>/`, valida o único `*.neyplugin` e só então move para `into`.
    private func receive(_ e: CatalogEntry, _ release: Release, into destination: String) async throws -> URL {
        guard let asset = release.asset("\(e.name)-\(release.version).neyplugin") else { throw StageError.download }
        let incoming = dir("Incoming").appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: incoming) }
        let zip = incoming.appendingPathComponent("asset.zip"), out = incoming.appendingPathComponent("out")
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            let (file, response) = try await URLSession.shared.download(for: Catalog.request(asset))
            guard (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true else { throw StageError.download }
            try fm.moveItem(at: file, to: zip)
        } catch { throw StageError.download }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // Zip-slip: o `ditto -x -k` tira os ".." dos caminhos e grava symlinks como arquivos comuns (conferido).
        ditto.arguments = ["-x", "-k", zip.path, out.path]
        do { try ditto.run() } catch { throw StageError.download }
        ditto.waitUntilExit()
        let found = ((try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "neyplugin" }
        guard ditto.terminationStatus == 0, found.count == 1,
              (try? found[0].resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false else { throw StageError.manifest }
        let manifest = try validate(folder: found[0]).get()
        // Só o binário é assinado: id, nome (vira a pasta) e versão do manifest têm de bater com catálogo e release.
        guard manifest.id == e.id, manifest.name == e.name, manifest.version == release.version else { throw StageError.manifest }

        let name = "\(manifest.name).neyplugin"
        // Plugins/ ocupado = ainda carregado nesta sessão: não troca por baixo, prepara para o próximo início.
        let folder = destination == "Plugins" && fm.fileExists(atPath: dir("Plugins").appendingPathComponent(name).path) ? "Staged" : destination
        try fm.createDirectory(at: dir(folder), withIntermediateDirectories: true)
        let dest = dir(folder).appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) { _ = try fm.replaceItemAt(dest, withItemAt: found[0]) } else { try fm.moveItem(at: found[0], to: dest) }
        return dest
    }
}

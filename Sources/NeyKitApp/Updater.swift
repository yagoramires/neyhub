import AppKit
import NeyKit

/// Atualização automática do avulso (decisão 19): baixa sozinho, aplica ao sair, nunca reinicia no meio do uso.
/// Preparado fica em `~/Library/Application Support/<id>/Update/{<Nome>.app, notes.md, version}`.
public final class Updater {
    /// Raiz das pastas por id; os testes trocam por uma pasta temporária.
    static var supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    /// App que será trocado; os testes trocam por um bundle falso.
    static var currentApp = Bundle.main.bundleURL

    private let name: String, repo: String, id: String
    private var timer: Timer?
    private var busy = false

    /// Versão já baixada e conferida, esperando o app fechar.
    public private(set) var staged: String?
    public var onChange: (() -> Void)?

    public init(name: String, repo: String, id: String) {
        self.name = name; self.repo = repo; self.id = id
        if let v = Self.version(of: stagedApp), Self.isSafeToApply(staged: v, current: currentVersion) { staged = v }
    }

    private static func updateDir(_ id: String) -> URL { supportRoot.appendingPathComponent("\(id)/Update") }
    private var stagedApp: URL { Self.updateDir(id).appendingPathComponent("\(name).app") }
    private var currentVersion: String { Self.version(of: Self.currentApp) ?? "0" }

    static func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    private func log(_ text: String) { FileHandle.standardError.write(Data("\(name) update: \(text)\n".utf8)) }

    /// Primeira checagem em 5 s, depois a cada 6 h.
    public func start() {
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    /// Falha de rede ou assinatura só loga: tenta de novo no próximo ciclo.
    private func check() {
        guard !busy else { return }
        busy = true
        let floor = staged ?? currentVersion, name = name
        var request = URLRequest(url: Release.latestURL(repo: repo))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(name)/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let release = data.flatMap(Release.parse) else {
                self.log("não deu pra consultar (\(error?.localizedDescription ?? "resposta inesperada"))")
                return self.finish(nil)
            }
            guard Release.isNewer(release.version, than: floor) else { return self.finish(nil) }
            guard let asset = release.asset("\(name)-\(release.version).zip") else {
                self.log("release \(release.version) sem \(name)-\(release.version).zip")
                return self.finish(nil)
            }
            URLSession.shared.downloadTask(with: asset) { file, _, error in
                // O arquivo baixado some quando este bloco termina: prepara aqui mesmo.
                guard let file else {
                    self.log("download falhou (\(error?.localizedDescription ?? "?"))")
                    return self.finish(nil)
                }
                self.finish(self.stage(zip: file, notes: release.notes))
            }.resume()
        }.resume()
    }

    private func finish(_ version: String?) {
        DispatchQueue.main.async {
            self.busy = false
            guard let version else { return }
            self.staged = version
            self.onChange?()
        }
    }

    /// Descompacta numa pasta temporária, confere versão e assinatura e só então troca `Update/` inteira.
    func stage(zip: URL, notes: String) -> String? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("nh-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let unzipped = tmp.appendingPathComponent("zip"), folder = tmp.appendingPathComponent("Update")
        do {
            try fm.createDirectory(at: unzipped, withIntermediateDirectories: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, unzipped.path]
            try ditto.run()
            ditto.waitUntilExit()
            let app = unzipped.appendingPathComponent("\(name).app")
            guard ditto.terminationStatus == 0, let version = Self.version(of: app) else {
                log("o zip não tem o \(name).app")
                return nil
            }
            guard Self.isSafeToApply(staged: version, current: currentVersion) else { return nil }
            guard PluginSignature.isTrustedApp(app, id: id) else {
                log("assinatura de \(version) recusada")
                return nil
            }
            try fm.moveItem(at: app, to: folder.appendingPathComponent("\(name).app"))
            try notes.write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
            try version.write(to: folder.appendingPathComponent("version"), atomically: true, encoding: .utf8)
            let dir = Self.updateDir(id)
            try fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
            try fm.moveItem(at: folder, to: dir)
            log("\(version) pronta; entra quando o app fechar")
            return version
        } catch {
            log("não deu pra preparar (\(error.localizedDescription))")
            return nil
        }
    }

    /// Chamar em `applicationWillTerminate`. Confere tudo de novo; em qualquer falha deixa o app atual intacto.
    public func applyStaged() -> Bool {
        let app = stagedApp, current = Self.currentApp
        guard let version = Self.version(of: app), Self.isSafeToApply(staged: version, current: currentVersion) else { return false }
        guard PluginSignature.isTrustedApp(app, id: id) else {
            log("assinatura de \(version) recusada na hora de aplicar")
            return false
        }
        do {
            // Troca atômica: o app atual só sai do lugar quando o novo já está nele.
            _ = try FileManager.default.replaceItemAt(current, withItemAt: app)
        } catch {
            log("não deu pra trocar (\(error.localizedDescription))")
            return false
        }
        staged = nil
        log("\(version) instalada em \(current.path)")
        return true
    }

    /// Botão "Reiniciar agora": aplica, reabre depois que este processo sair e encerra.
    public func relaunchNow() {
        guard applyStaged() else { return }
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Self.currentApp.path]
        do { try relaunch.run() } catch { log("não deu pra reabrir (\(error.localizedDescription))") }
        NSApp.terminate(nil)
    }

    public static func isSafeToApply(staged: String, current: String) -> Bool { Release.isNewer(staged, than: current) }

    /// Patch note da versão que acabou de entrar, uma vez só. Apaga `Update/` quando não há mais nada a aplicar.
    public static func notesAfterUpdate(id: String, current: String) -> String? {
        let defaults = AppDefaults.forApp(id)
        guard defaults.string(forKey: "lastRunVersion") != current else { return nil }
        defaults.set(current, forKey: "lastRunVersion")
        let dir = updateDir(id)
        guard let version = try? String(contentsOf: dir.appendingPathComponent("version"), encoding: .utf8),
              !isSafeToApply(staged: version, current: current) else { return nil }
        let notes = version == current ? try? String(contentsOf: dir.appendingPathComponent("notes.md"), encoding: .utf8) : nil
        try? FileManager.default.removeItem(at: dir)
        return notes
    }
}

import AppKit
import NeyKit

/// Testes do NeyKitApp, chamados por `NeyHub --selftest` (de dentro do NeyHub.app assinado).
public enum NeyKitAppSelfTest {
    public static func run() {
        updater()
        hubCheck()
    }

    static let fm = FileManager.default

    /// Pasta temporária com prefixo nh- (o scripts/selftest.sh apaga as que sobrarem).
    static func temp(_ tag: String) -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("nh-\(tag)-\(UUID().uuidString)")
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ text: String, _ url: URL) { try! text.write(to: url, atomically: true, encoding: .utf8) }

    static func fakeApp(_ url: URL, version: String) {
        try? fm.removeItem(at: url)
        try! fm.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        precondition(NSDictionary(dictionary: ["CFBundleShortVersionString": version]).write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true))
    }

    static func zip(_ app: URL, to zip: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try! p.run(); p.waitUntilExit()
        precondition(p.terminationStatus == 0)
    }

    static func updater() {
        precondition(Updater.isSafeToApply(staged: "0.5.0", current: "0.4.1"))
        precondition(!Updater.isSafeToApply(staged: "0.4.1", current: "0.4.1"))
        precondition(!Updater.isSafeToApply(staged: "0.4.0", current: "0.4.1"))

        let root = temp("updater")
        let saved = (Updater.supportRoot, Updater.currentApp)
        let std = UserDefaults.standard, oldRun = std.object(forKey: "lastRunVersion")
        let tempID = "neyhub.selftest.updater"
        defer {
            (Updater.supportRoot, Updater.currentApp) = saved
            try? fm.removeItem(at: root)
            AppDefaults.forApp(tempID).removePersistentDomain(forName: tempID)
            if let oldRun { std.set(oldRun, forKey: "lastRunVersion") } else { std.removeObject(forKey: "lastRunVersion") }
        }
        Updater.supportRoot = root

        // Novidades: uma vez só, e a pasta Update/ some depois de lida.
        AppDefaults.forApp(tempID).removePersistentDomain(forName: tempID)
        let tempUpdate = root.appendingPathComponent("\(tempID)/Update")
        try! fm.createDirectory(at: tempUpdate, withIntermediateDirectories: true)
        write("0.5.0", tempUpdate.appendingPathComponent("version"))
        write("### Novo\n- x", tempUpdate.appendingPathComponent("notes.md"))
        precondition(Updater.notesAfterUpdate(id: tempID, current: "0.5.0") == "### Novo\n- x")
        precondition(Updater.notesAfterUpdate(id: tempID, current: "0.5.0") == nil)
        precondition(!fm.fileExists(atPath: tempUpdate.path))

        // App "instalado" falso na 0.0.1; o candidato é uma cópia do próprio NeyHub.app (assinado, local.neyhub).
        let me = Bundle.main.bundleURL, myVersion = Updater.version(of: me)!
        let current = root.appendingPathComponent("Current/NeyHub.app")
        fakeApp(current, version: "0.0.1")
        Updater.currentApp = current
        let u = Updater(name: "NeyHub", repo: "yagoramires/neyhub", id: "local.neyhub")
        precondition(u.staged == nil)

        // stage: zip adulterado (arquivo a mais no bundle selado) não chega em Update/.
        let update = root.appendingPathComponent("local.neyhub/Update"), stagedApp = update.appendingPathComponent("NeyHub.app")
        let work = temp("updater-zip")
        defer { try? fm.removeItem(at: work) }
        let bad = work.appendingPathComponent("bad/NeyHub.app")
        try! fm.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! fm.copyItem(at: me, to: bad)
        write("x", bad.appendingPathComponent("Contents/Resources/extra.txt"))
        zip(bad, to: work.appendingPathComponent("bad.zip"))
        precondition(u.stage(zip: work.appendingPathComponent("bad.zip"), notes: "n") == nil)
        precondition(!fm.fileExists(atPath: update.path))
        // Zip que não tem o <Nome>.app também não.
        zip(current, to: work.appendingPathComponent("other.zip"))
        precondition(Updater(name: "Outro", repo: "x/y", id: "local.neyhub").stage(zip: work.appendingPathComponent("other.zip"), notes: "n") == nil)
        precondition(!fm.fileExists(atPath: update.path))

        // stage: zip bom vai inteiro para Update/{NeyHub.app, notes.md, version}.
        zip(me, to: work.appendingPathComponent("good.zip"))
        precondition(u.stage(zip: work.appendingPathComponent("good.zip"), notes: "### Novo") == myVersion)
        precondition(PluginSignature.isTrustedApp(stagedApp, id: "local.neyhub"))
        precondition((try? String(contentsOf: update.appendingPathComponent("version"), encoding: .utf8)) == myVersion)
        precondition(Updater(name: "NeyHub", repo: "yagoramires/neyhub", id: "local.neyhub").staged == myVersion)

        // applyStaged: candidato adulterado depois de preparado → não troca.
        let extra = stagedApp.appendingPathComponent("Contents/Resources/extra.txt")
        write("x", extra)
        precondition(!u.applyStaged())
        precondition(Updater.version(of: current) == "0.0.1")
        try! fm.removeItem(at: extra)

        // Candidato não mais novo que o instalado → não troca.
        fakeApp(current, version: myVersion)
        precondition(!u.applyStaged())
        precondition(fm.fileExists(atPath: stagedApp.path))

        // Caminho feliz: troca, e uma segunda chamada não faz nada.
        fakeApp(current, version: "0.0.1")
        precondition(u.applyStaged())
        precondition(Updater.version(of: current) == myVersion && PluginSignature.isTrustedApp(current, id: "local.neyhub"))
        precondition(u.staged == nil && !u.applyStaged())

        // Dentro do .app (id do processo → UserDefaults.standard) as novidades saem uma vez.
        precondition(Updater.notesAfterUpdate(id: "local.neyhub", current: myVersion) == "### Novo")
        precondition(Updater.notesAfterUpdate(id: "local.neyhub", current: myVersion) == nil)
        precondition(std.string(forKey: "lastRunVersion") == myVersion)
    }

    static func hubCheck() {
        let dir = temp("hubcheck"), saved = HubCheck.activeURL
        defer { HubCheck.activeURL = saved; try? fm.removeItem(at: dir) }
        HubCheck.activeURL = dir.appendingPathComponent("active.json")
        precondition(!HubCheck.isActive("local.aero"))
        write(#"["local.aero","local.dose"]"#, HubCheck.activeURL)
        precondition(HubCheck.isActive("local.aero") && !HubCheck.isActive("local.hub"))
        write(#"{"local.aero":true}"#, HubCheck.activeURL)
        precondition(!HubCheck.isActive("local.aero"))
        write("lixo", HubCheck.activeURL)
        precondition(!HubCheck.isActive("local.aero"))

        // O próprio processo (local.neyhub) não conta como "NeyHub rodando".
        write(#"["local.aero"]"#, HubCheck.activeURL)
        precondition(!HubCheck.isHosted(id: "local.dose"))
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.neyhub")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        precondition(HubCheck.isHosted(id: "local.aero") == !others.isEmpty)
    }
}

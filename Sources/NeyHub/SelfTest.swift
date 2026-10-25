import AppKit
import NeyKit
import NeyKitApp

/// `NeyHub --selftest [--fixture <pasta>]` roda tudo e imprime "selftest ok". Precisa rodar de dentro do .app.
enum SelfTest {
    static func run(fixture: URL?) {
        precondition(Bundle.main.bundleIdentifier == "local.neyhub", "selftest fora do .app")
        NeyKitSelfTest.run()
        NeyKitAppSelfTest.run()
        signature()
        if let fixture { plugins(fixture) } else { FileHandle.standardError.write(Data("sem --fixture: pulando carga de plugins\n".utf8)) }
    }

    static func signature() {
        precondition(PluginSignature.isTrustedApp(Bundle.main.bundleURL, id: "local.neyhub"))
        precondition(!PluginSignature.isTrustedApp(Bundle.main.bundleURL, id: "local.aero"))
        precondition(!PluginSignature.isTrustedApp(Bundle.main.bundleURL, id: #"x" or anchor apple"#))
    }

    /// Pastas montadas pelo scripts/selftest.sh: good (assinada), adhoc, tampered, future (contract 2).
    static func plugins(_ dir: URL) {
        func folder(_ name: String) -> URL { dir.appendingPathComponent("\(name)/Hello.neyplugin") }
        let good = folder("good")
        guard case .success(let p) = PluginHost.load(folder: good) else { preconditionFailure("good: \(PluginHost.load(folder: good))") }
        precondition(p.plugin.contractVersion == 1 && p.plugin.makeScreen() != nil)
        precondition(PluginHost.dlopenCount == 1)
        precondition(PluginHost.load(folder: good).failure == .alreadyLoaded)
        precondition(PluginHost.load(folder: folder("adhoc")).failure == .signature)
        precondition(PluginHost.load(folder: folder("tampered")).failure == .signature)
        precondition(PluginHost.load(folder: folder("future")).failure == .contractTooNew(2))
        precondition(PluginHost.load(folder: dir.appendingPathComponent("nada.neyplugin")).failure == .manifest)
        precondition(PluginHost.dlopenCount == 1, "dlopen chamado para plugin rejeitado")

        // Ponte host↔plugin atravessa as duas imagens; stopCount é lido por KVC (a classe mora no plugin).
        let host = HostBridge()
        p.plugin.start(host: host)
        precondition(host.messages == ["Olá do plugin"])
        p.plugin.stop()
        precondition((p.plugin as AnyObject).value(forKey: "stopCount") as? Int == 1)
    }
}

extension Result {
    /// Só para teste: o erro, ou nil se deu certo.
    var failure: Failure? { if case .failure(let e) = self { e } else { nil } }
}

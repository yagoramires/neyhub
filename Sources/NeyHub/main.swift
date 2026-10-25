import AppKit
import NeyKit

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    let flag = arguments.firstIndex(of: "--fixture")
    let fixture = flag.flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
    MainActor.assumeIsolated { SelfTest.run(fixture: fixture) }
    print("selftest ok")
    exit(0)
}

if let flag = arguments.firstIndex(of: "--validate-manifest") {
    func fail(_ message: String, _ code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8)); exit(code)
    }
    // Sem argumento não pode cair na abertura normal do app.
    guard arguments.indices.contains(flag + 1) else { fail("uso: NeyHub --validate-manifest <manifest.json>", 2) }
    let path = arguments[flag + 1]
    guard let data = FileManager.default.contents(atPath: path), let m = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
        fail("manifest ilegível ou incompleto: \(path)")
    }
    if !m.isValid { fail("manifest inválido (id, name ou binary)") }
    if m.contract != neyPluginContractVersion { fail("contract \(m.contract) != \(neyPluginContractVersion)") }
    print("ok \(m.id) \(m.version)")
    exit(0)
}

let app = NSApplication.shared
if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
    app.setActivationPolicy(.prohibited)
    Snapshots.run(into: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}
// Instância única: outro NeyHub já aberto (open -n, outra cópia) é trazido à frente com a janela, e este sai.
let me = ProcessInfo.processInfo.processIdentifier
if let other = NSRunningApplication.runningApplications(withBundleIdentifier: "local.neyhub").first(where: { $0.processIdentifier != me && !$0.isTerminated }),
   let url = other.bundleURL {
    // Abrir o que já roda manda o "reabrir" (applicationShouldHandleReopen mostra a janela); só activate() não traz a janela fechada.
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in exit(0) }
    RunLoop.main.run(until: Date().addingTimeInterval(5))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()

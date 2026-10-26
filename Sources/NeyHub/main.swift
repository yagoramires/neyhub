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
    if !m.isValid { fail("manifest inválido (id, name, binary ou minMacOS)") }
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
// `--tour <saída> <telas>`: quadros do GIF do README (telas/<app>.png = a tela de cada app com dados de exemplo).
if let flag = arguments.firstIndex(of: "--tour"), arguments.indices.contains(flag + 2) {
    app.setActivationPolicy(.prohibited)
    Snapshots.tour(into: URL(fileURLWithPath: arguments[flag + 1]), screens: URL(fileURLWithPath: arguments[flag + 2]))
    exit(0)
}
// Instância única: outro NeyHub aberto antes deste (open -n, outra cópia) vem para a frente e este sai.
// Só o mais antigo fica: dois abertos ao mesmo tempo não saem os dois.
let me = NSRunningApplication.current
if let other = NSRunningApplication.runningApplications(withBundleIdentifier: "local.neyhub").first(where: {
    $0.processIdentifier != me.processIdentifier && !$0.isTerminated
        && ($0.launchDate ?? .distantPast) <= (me.launchDate ?? .distantFuture)
}) {
    // activate() não reabre a janela fechada: pede ao outro, pelo nome, que mostre a dele.
    DistributedNotificationCenter.default().postNotificationName(.init("local.neyhub.show"), object: nil, deliverImmediately: true)
    other.activate()
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()

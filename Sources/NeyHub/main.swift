import AppKit
import NeyKit

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    let flag = arguments.firstIndex(of: "--fixture")
    SelfTest.run(fixture: flag.flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil })
    print("selftest ok")
    exit(0)
}

if let flag = arguments.firstIndex(of: "--validate-manifest"), arguments.indices.contains(flag + 1) {
    let path = arguments[flag + 1]
    guard let data = FileManager.default.contents(atPath: path), let m = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
        print("manifest ilegível ou incompleto: \(path)"); exit(1)
    }
    if !m.isValid { print("manifest inválido (id, name ou binary)"); exit(1) }
    if m.contract != neyPluginContractVersion { print("contract \(m.contract) != \(neyPluginContractVersion)"); exit(1) }
    print("ok \(m.id) \(m.version)")
    exit(0)
}

let app = NSApplication.shared
if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
    app.setActivationPolicy(.prohibited)
    Snapshots.run(into: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()

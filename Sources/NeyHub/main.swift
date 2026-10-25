import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    let flag = arguments.firstIndex(of: "--fixture")
    SelfTest.run(fixture: flag.flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil })
    print("selftest ok")
    exit(0)
}

let app = NSApplication.shared
if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
    app.setActivationPolicy(.prohibited)
    Snapshots.run(into: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}
app.setActivationPolicy(.regular)
app.run()

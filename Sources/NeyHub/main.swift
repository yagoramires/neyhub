import AppKit

let arguments = CommandLine.arguments

// --fixture <pasta> é aceito e ignorado por enquanto.
if arguments.contains("--selftest") {
    SelfTest.run()
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

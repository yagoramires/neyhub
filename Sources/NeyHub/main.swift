import AppKit

let arguments = CommandLine.arguments

// --fixture <pasta> é aceito e ignorado por enquanto.
if arguments.contains("--selftest") {
    SelfTest.run()
    print("selftest ok")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.run()

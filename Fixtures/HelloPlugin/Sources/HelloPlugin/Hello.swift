import AppKit
import NeyKit
import SwiftUI

/// Plugin mínimo para o selftest do NeyHub. Linka só NeyKit.
/// `stopCount`/`menuBarCalls` são @objc para o host ler por KVC (`value(forKey: "stopCount")`).
final class HelloEntry: NSObject, NeyPlugin {
    @objc private(set) var stopCount = 0
    @objc private(set) var menuBarCalls = 0

    var contractVersion: Int { 1 }
    func start(host: NeyHost) { host.log("Olá do plugin") }
    func stop() { stopCount += 1 }
    func setMenuBarVisible(_ visible: Bool) { menuBarCalls += 1 }
    func makeScreen() -> NSViewController? { NSHostingController(rootView: GCard { Text("Olá do plugin") }) }
    func makeSettings() -> NSViewController { NSHostingController(rootView: Text("Sem ajustes")) }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(HelloEntry()).toOpaque()
}

import AppKit
import SwiftUI
/// Testes do NeyKit, chamados por `NeyHub --selftest`. Sem XCTest (só CommandLineTools).
public enum NeyKitSelfTest {
    public static func run() {
        precondition(Grafite.color(hex: "#c6ff3d") != nil)
        precondition(Grafite.color(hex: "c6ff3d") != nil)
        precondition(Grafite.color(hex: "#zzz") == nil)
        precondition(Grafite.color(hex: "#12345") == nil)
        precondition(Grafite.color(hex: "+c6ff3") == nil)
        precondition(Grafite.color(hex: "#+12345") == nil)
        let rgb = NSColor(Grafite.color(hex: "#c6ff3d")!).usingColorSpace(.sRGB)!
        precondition(abs(rgb.redComponent - 0xc6 / 255) < 0.002 && abs(rgb.greenComponent - 1) < 0.002
                     && abs(rgb.blueComponent - 0x3d / 255) < 0.002)
        manifest()
    }

    static func manifest() {
        func decode(binary: String, id: String = "local.hello") -> PluginManifest {
            let json = #"{"id":"\#(id)","name":"Hello","version":"1.0.0","contract":1,"hasScreen":true,"permissions":["acessibilidade"],"binary":"\#(binary)"}"#
            return try! JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        }
        let m = decode(binary: "libHello.dylib")
        precondition(m.id == "local.hello" && m.contract == 1 && m.hasScreen && m.permissions == ["acessibilidade"])
        precondition(m.isValid)
        precondition(!decode(binary: "../x").isValid)
        precondition(!decode(binary: "a/b").isValid)
        precondition(!decode(binary: "").isValid)
        precondition(!decode(binary: "x", id: "").isValid)
        precondition(neyPluginContractVersion == 1)
    }
}

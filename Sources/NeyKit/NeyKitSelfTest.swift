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
    }
}

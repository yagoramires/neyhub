/// Testes do NeyKit, chamados por `NeyHub --selftest`. Sem XCTest (só CommandLineTools).
public enum NeyKitSelfTest {
    public static func run() {
        precondition(Grafite.color(hex: "#c6ff3d") != nil)
        precondition(Grafite.color(hex: "c6ff3d") != nil)
        precondition(Grafite.color(hex: "#zzz") == nil)
        precondition(Grafite.color(hex: "#12345") == nil)
    }
}

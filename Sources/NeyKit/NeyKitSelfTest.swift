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
        releaseDefaultsPresence()
    }

    static func manifest() {
        func decode(binary: String, id: String = "local.hello", name: String = "Hello") -> PluginManifest {
            let json = #"{"id":"\#(id)","name":"\#(name)","version":"1.0.0","contract":1,"hasScreen":true,"permissions":["acessibilidade"],"binary":"\#(binary)"}"#
            return try! JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
        }
        let m = decode(binary: "libHello.dylib")
        precondition(m.id == "local.hello" && m.contract == 1 && m.hasScreen && m.permissions == ["acessibilidade"])
        precondition(m.isValid)
        precondition(!decode(binary: "../x").isValid)
        precondition(!decode(binary: "a/b").isValid)
        precondition(!decode(binary: "").isValid)
        precondition(!decode(binary: "x", id: "").isValid)
        // id vira nome de pasta, marcador em Remove/ e domínio de defaults: só [A-Za-z0-9.-], sem começar por ".".
        for bad in ["a/b", "..", ".x", "a b", "local_x", #"x\" or anchor apple"#, "lócal"] {
            precondition(!decode(binary: "x", id: bad).isValid, "id \(bad) aceito")
            precondition(!PluginSignature.isSafeID(bad))
        }
        precondition(decode(binary: "x", id: "local.my-app2").isValid && PluginSignature.isSafeID("local.my-app2"))
        // name vira <Nome>.neyplugin: nome simples, sem sair da pasta.
        precondition(!decode(binary: "x", name: "../x").isValid && !decode(binary: "x", name: "a/b").isValid && !decode(binary: "x", name: "").isValid)
        precondition(neyPluginContractVersion == 1)
    }

    static func releaseDefaultsPresence() {
        let r = Release.parse(Data(####"{"tag_name":"v0.5.0","html_url":"https://github.com/yagoramires/aero/releases/tag/v0.5.0","body":"### Corrigido\n- x","assets":[{"name":"Aero-0.5.0.neyplugin","browser_download_url":"https://e/p"},{"name":"Aero-0.5.0.zip","browser_download_url":"https://e/z"},{"name":"sem-url"}]}"####.utf8))!
        precondition(r.version == "0.5.0" && r.notes.hasPrefix("### Corrigido") && r.asset("Aero-0.5.0.zip")?.absoluteString == "https://e/z")
        precondition(r.asset("Aero-0.5.0.neyplugin") != nil && r.asset("sem-url") == nil && r.assets.count == 2)
        precondition(Release.parse(Data(#"{"html_url":"https://e"}"#.utf8)) == nil)
        precondition(Release.parse(Data(#"{"tag_name":"v1"}"#.utf8)) == nil)
        precondition(Release.parse(Data(#"{"tag_name":"v1","html_url":"https://e"}"#.utf8))?.notes == "")
        precondition(Release.isNewer("0.10.0", than: "0.9.9") && !Release.isNewer("1.0", than: "1.0.0"))
        precondition(!Release.isNewer("1.0.0", than: "1.0") && Release.isNewer("1.0.1", than: "1.0"))
        let tagged = { (t: String) in Release.parse(Data(#"{"tag_name":"\#(t)","html_url":"https://e"}"#.utf8))!.version }
        precondition(tagged("1.0v") == "1.0v" && tagged("v1.2.3") == "1.2.3")
        precondition(Release.latestURL(repo: "yagoramires/aero").absoluteString == "https://api.github.com/repos/yagoramires/aero/releases/latest")
        precondition(Presence(screen: false, menuBar: false).normalized(hasScreen: true) == .init(screen: false, menuBar: true))
        precondition(Presence(screen: true, menuBar: false).normalized(hasScreen: false) == .init(screen: false, menuBar: false))
        let name = "neyhub.selftest.presence"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        precondition(Presence.load(d, hasScreen: true) == .init(screen: true, menuBar: true))
        precondition(Presence.load(d, hasScreen: false) == .init(screen: false, menuBar: true))
        Presence(screen: false, menuBar: true).save(d)
        precondition(Presence.load(d, hasScreen: true) == .init(screen: false, menuBar: true))
        d.removePersistentDomain(forName: name)
        precondition(AppDefaults.forApp("local.neyhub") === UserDefaults.standard)
        precondition(AppDefaults.forApp("local.aero") !== UserDefaults.standard)
    }
}

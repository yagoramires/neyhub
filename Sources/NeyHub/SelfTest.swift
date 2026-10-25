import Foundation
import NeyKit
import NeyKitApp

/// `NeyHub --selftest` roda tudo e imprime "selftest ok". Precisa rodar de dentro do .app.
enum SelfTest {
    static func run() {
        precondition(Bundle.main.bundleIdentifier == "local.neyhub", "selftest fora do .app")
        NeyKitSelfTest.run()
        NeyKitAppSelfTest.run()
    }
}

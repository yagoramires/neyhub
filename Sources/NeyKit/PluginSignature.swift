import Foundation
import Security

/// Confere a assinatura de plugins e apps contra o certificado "Aero Local Signing".
public enum PluginSignature {
    // shortcut: certificado fixo no código; se o "Aero Local Signing" for recriado, atualizar aqui e republicar os plugins.
    public static let trustedLeaf = #"certificate leaf = H"c8fc5847339bf8a7c29ab0c5d1fcdaf5897ec092""#

    /// Dylib assinado pelo certificado fixo e íntegro (ad-hoc e adulterado falham).
    public static func isTrustedPlugin(_ binary: URL) -> Bool { check(binary, trustedLeaf) }

    /// App com bundle id `id` assinado pelo certificado fixo; confere também o código aninhado, em modo estrito.
    public static func isTrustedApp(_ app: URL, id: String) -> Bool {
        // id entra no texto do requisito: só caracteres de bundle id, para não injetar cláusulas.
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return false }
        return check(app, #"identifier "\#(id)" and \#(trustedLeaf)"#,
                     flags: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    }

    private static func check(_ url: URL, _ requirement: String, flags: UInt32 = kSecCSCheckAllArchitectures) -> Bool {
        var code: SecStaticCode?, req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: flags), req) == errSecSuccess
    }
}

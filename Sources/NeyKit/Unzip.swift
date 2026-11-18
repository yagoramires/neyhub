import Foundation

public enum Unzip {
    /// Descompacta com `ditto -x -k`, que tira os ".." dos caminhos e grava symlinks como arquivos comuns (zip-slip, conferido).
    /// Lança se o ditto não abre; `false` se ele falha (zip inválido).
    public static func extract(_ zip: URL, into folder: URL) throws -> Bool {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        return ditto.terminationStatus == 0
    }
}

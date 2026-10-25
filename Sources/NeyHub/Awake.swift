import Foundation

enum AwakeError: Error, Equatable {
    case cancelled          // prompt de administrador cancelado: a UI não mostra erro
    case failed(String)
}

/// `pmset -a disablesleep`: só o usuário liga e desliga; nada aqui roda ao sair do app.
enum Awake {
    static let sudoersPath = "/etc/sudoers.d/neyhub"

    /// " SleepDisabled\t\t1" → true; sem a linha → nil.
    static func parse(pmset: String) -> Bool? {
        for line in pmset.split(separator: "\n") {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if f.count == 2, f[0] == "SleepDisabled" { return f[1] == "1" }
        }
        return nil
    }

    /// Nome de usuário vira texto de sudoers e de shell de root: só o alfabeto seguro passa.
    static func sudoersLine(user: String) -> String? {
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return nil }
        return "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    }

    /// Roda inteiro como root. O temporário fica em /private/tmp (raiz, sticky): o $TMPDIR herdado seria uma pasta do usuário,
    /// onde ele poderia trocar o arquivo entre o visudo e o install.
    static func installScript(user: String) -> String? {
        guard let line = sudoersLine(user: user) else { return nil }
        return """
        set -e
        t=$(/usr/bin/mktemp /private/tmp/neyhub.XXXXXX)
        trap '/bin/rm -f "$t"' EXIT
        printf '%s\\n' '\(line)' > "$t"
        /usr/sbin/visudo -cf "$t"
        /usr/bin/install -m 0440 -o root -g wheel "$t" \(sudoersPath)
        """
    }

    static func appleScript(for script: String) -> String {
        let q = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(q)\" with administrator privileges"
    }

    /// nil = não deu para ler (a UI mantém o último valor conhecido).
    static func isEnabled() -> Bool? {
        let r = run("/usr/bin/pmset", ["-g"])
        return r.status == 0 ? parse(pmset: r.out) : nil
    }

    /// Sem senha via sudoers; se a regra ainda não existe, instala (1 prompt) e tenta de novo uma vez.
    static func set(_ on: Bool) throws {
        let args = ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]
        var r = run("/usr/bin/sudo", args)
        if r.status != 0, r.err.contains("a password is required") {
            try installRule()
            r = run("/usr/bin/sudo", args)
        }
        if r.status != 0 { throw AwakeError.failed(r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func installRule() throws {
        guard let script = installScript(user: NSUserName()) else { throw AwakeError.failed("usuário com caracteres inesperados") }
        let r = run("/usr/bin/osascript", ["-e", appleScript(for: script)])
        if r.status == 0 { return }
        throw r.err.contains("(-128)") ? AwakeError.cancelled : AwakeError.failed(r.err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let p = Process(), o = Pipe(), e = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = o
        p.standardError = e
        p.standardInput = FileHandle.nullDevice // sudo -n nunca espera teclado
        do { try p.run() } catch { return (-1, "", "\(error.localizedDescription)") }
        // Saídas pequenas: ler uma e depois a outra não enche o pipe.
        let out = o.fileHandleForReading.readDataToEndOfFile(), err = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}

import Foundation
import NeyKit

/// Uma linha do `catalog.json` (repo neyhub, branch main; cópia embutida no .app para abrir sem rede).
/// `soon` (opcional no JSON): card "Em breve", ainda sem release.
struct CatalogEntry: Codable, Equatable {
    let id, name, repo, summary: String; let hasScreen: Bool; var soon = false

    init(id: String, name: String, repo: String, summary: String, hasScreen: Bool, soon: Bool = false) {
        (self.id, self.name, self.repo, self.summary, self.hasScreen, self.soon) = (id, name, repo, summary, hasScreen, soon)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name), repo: try c.decode(String.self, forKey: .repo),
                  summary: try c.decode(String.self, forKey: .summary), hasScreen: try c.decode(Bool.self, forKey: .hasScreen),
                  soon: try c.decodeIfPresent(Bool.self, forKey: .soon) ?? false)
    }
}

enum Catalog {
    static let remote = URL(string: "https://raw.githubusercontent.com/yagoramires/neyhub/main/catalog.json")!

    /// Lista do catálogo; entradas com id, nome ou repo perigosos (viram pasta, defaults e URL) são descartadas.
    static func decode(_ data: Data) -> [CatalogEntry]? {
        guard let all = try? JSONDecoder().decode([CatalogEntry].self, from: data) else { return nil }
        return all.filter { e in
            let parts = e.repo.split(separator: "/", omittingEmptySubsequences: false)
            return PluginSignature.isSafeID(e.id) && !e.name.isEmpty && !e.name.contains("/")
                && parts.count == 2 && parts.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) } }
        }
    }

    /// Sem rede: cache se legível, senão o embutido.
    static func load(cache: URL, bundled: URL) -> [CatalogEntry] {
        (try? Data(contentsOf: cache)).flatMap(decode) ?? (try? Data(contentsOf: bundled)).flatMap(decode) ?? []
    }

    /// Baixa o catálogo novo e grava no cache; nil se a rede ou o JSON falharem (fica o que já está na tela).
    static func refresh(cache: URL) async -> [CatalogEntry]? {
        guard let (data, response) = try? await URLSession.shared.data(for: request(remote)),
              (response as? HTTPURLResponse)?.statusCode == 200, let entries = decode(data) else { return nil }
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cache, options: .atomic)
        return entries
    }

    static func releasesURL(repo: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10")!
    }

    /// Resposta de `/releases`: lista de objetos no mesmo formato de `/releases/latest`.
    static func parseReleases(_ data: Data) -> [Release] {
        let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? []
        return list.compactMap { (try? JSONSerialization.data(withJSONObject: $0)).flatMap(Release.parse) }
    }

    /// Patch notes do detalhe; vazio sem rede.
    static func releases(repo: String) async -> [Release] {
        guard let (data, _) = try? await URLSession.shared.data(for: request(releasesURL(repo: repo))) else { return [] }
        return parseReleases(data)
    }

    /// GET com o User-Agent exigido pela API do GitHub.
    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("NeyHub/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")", forHTTPHeaderField: "User-Agent")
        return r
    }
}

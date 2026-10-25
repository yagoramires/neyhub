import Foundation

/// Release do GitHub (`/releases/latest`), já reduzida ao que os apps usam.
public struct Release: Equatable {
    public let version: String, notes: String, page: URL, assets: [String: URL]

    public init(version: String, notes: String, page: URL, assets: [String: URL]) {
        self.version = version; self.notes = notes; self.page = page; self.assets = assets
    }

    public func asset(_ name: String) -> URL? { assets[name] }

    public static func latestURL(repo: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    public static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        var assets: [String: URL] = [:]
        for a in json["assets"] as? [[String: Any]] ?? [] {
            if let n = a["name"] as? String, let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)) { assets[n] = u }
        }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: json["body"] as? String ?? "", page: page, assets: assets)
    }

    // shortcut: pré-release (1.0.0-beta) não é ordenado, só os números de cada componente contam; upgrade se publicarmos pré-releases.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }, y = b.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for i in 0..<max(x.count, y.count) where (i < x.count ? x[i] : 0) != (i < y.count ? y[i] : 0) {
            return (i < x.count ? x[i] : 0) > (i < y.count ? y[i] : 0)
        }
        return false
    }
}

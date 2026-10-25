// swift-tools-version:6.0
import Foundation
import PackageDescription

// Raiz do neyhub (3 níveis acima deste arquivo). A identidade de `.package(path:)` é o nome da pasta
// em minúsculas, então derivamos dela: funciona no checkout principal e em worktrees.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let package = Package(
    name: "HelloPlugin",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HelloPlugin", type: .dynamic, targets: ["HelloPlugin"])],
    dependencies: [.package(path: root.path)],
    targets: [
        .target(name: "HelloPlugin",
                dependencies: [.product(name: "NeyKit", package: root.lastPathComponent.lowercased())],
                swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

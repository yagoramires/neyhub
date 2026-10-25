// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NeyHub",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NeyKit", targets: ["NeyKit"]),
        .library(name: "NeyKitApp", targets: ["NeyKitApp"]),
        .executable(name: "NeyHub", targets: ["NeyHub"]),
    ],
    targets: [
        .target(name: "NeyKit", path: "Sources/NeyKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "NeyKitApp", dependencies: ["NeyKit"], path: "Sources/NeyKitApp", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "NeyHub", dependencies: ["NeyKit", "NeyKitApp"], path: "Sources/NeyHub", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

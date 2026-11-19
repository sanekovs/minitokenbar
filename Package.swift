// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniTokenBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MiniTokenBar", targets: ["MiniTokenBar"])],
    targets: [.executableTarget(name: "MiniTokenBar", resources: [.copy("Resources")])],
    swiftLanguageVersions: [.v5]
)

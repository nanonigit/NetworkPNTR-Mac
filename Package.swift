// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ArtexMac", platforms: [.macOS(.v15)],
    products: [.executable(name: "ArtexMac", targets: ["ArtexMac"]), .executable(name: "VMProbe", targets: ["VMProbe"])],
    targets: [
        .target(name: "ArtexCore", resources: [.copy("Resources/feature-map.json"), .copy("Resources/auth-terms.ja.json"), .copy("Resources/auth-terms.en.json")]),
        .executableTarget(name: "ArtexMac", dependencies: ["ArtexCore"]),
        .executableTarget(name: "VMProbe", dependencies: ["ArtexCore"]),
        .testTarget(name: "ArtexCoreTests", dependencies: ["ArtexCore"], resources: [.copy("Fixtures")])
    ], swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ArtexMac", defaultLocalization: "en", platforms: [.macOS(.v15)],
    products: [.executable(name: "ArtexMac", targets: ["ArtexMac"]), .executable(name: "VMProbe", targets: ["VMProbe"])],
    targets: [
        .target(name: "ArtexCloudTLS", linkerSettings: [.linkedLibrary("curl")]),
        .target(name: "ArtexCore", dependencies: ["ArtexCloudTLS"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/en.lproj"), .process("Resources/ja.lproj"), .copy("Resources/feature-map.json"), .copy("Resources/auth-terms.ja.json"), .copy("Resources/auth-terms.en.json")]),
        .executableTarget(name: "ArtexMac", dependencies: ["ArtexCore"]),
        .executableTarget(name: "VMProbe", dependencies: ["ArtexCore"]),
        .testTarget(name: "VMProbeTests", dependencies: ["VMProbe", "ArtexCore"]),
        .testTarget(name: "ArtexMacTests", dependencies: ["ArtexMac", "ArtexCore"]),
        .testTarget(name: "ArtexCoreTests", dependencies: ["ArtexCore"], resources: [.copy("Fixtures")])
    ], swiftLanguageModes: [.v6]
)

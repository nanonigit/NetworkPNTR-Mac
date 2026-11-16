// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ArtexMac", defaultLocalization: "en", platforms: [.macOS(.v15)],
    products: [.executable(name: "ArtexMac", targets: ["ArtexMac"]), .executable(name: "VMProbe", targets: ["VMProbe"]), .executable(name: "ArtexMCP", targets: ["ArtexMCP"])],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"), .package(url: "https://github.com/apple/swift-log.git", exact: "1.17.0")],
    targets: [
        .target(name: "ArtexCloudTLS", linkerSettings: [.linkedFramework("Security"), .linkedFramework("CoreFoundation")]),
        .target(name: "ArtexCore", dependencies: ["ArtexCloudTLS"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/en.lproj"), .process("Resources/ja.lproj"), .copy("Resources/feature-map.json"), .copy("Resources/auth-terms.ja.json"), .copy("Resources/auth-terms.en.json")]),
        .executableTarget(name: "ArtexMac", dependencies: ["ArtexCore"]),
        .executableTarget(name: "VMProbe", dependencies: ["ArtexCore"]),
        .executableTarget(name: "ArtexMCP", dependencies: ["ArtexCore", .product(name: "MCP", package: "swift-sdk"), .product(name: "Logging", package: "swift-log")]),
        .testTarget(name: "ArtexMCPTests", dependencies: ["ArtexMCP", "ArtexCore"]),
        .testTarget(name: "VMProbeTests", dependencies: ["VMProbe", "ArtexCore"]),
        .testTarget(name: "ArtexMacTests", dependencies: ["ArtexMac", "ArtexCore"]),
        .testTarget(name: "ArtexCoreTests", dependencies: ["ArtexCore"], resources: [.copy("Fixtures")])
    ], swiftLanguageModes: [.v6]
)

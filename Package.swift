// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NetworkPNTRMac", defaultLocalization: "en", platforms: [.macOS(.v15)],
    products: [.executable(name: "NetworkPNTRMac", targets: ["NetworkPNTRMac"]), .executable(name: "VMProbe", targets: ["VMProbe"]), .executable(name: "NetworkPNTRMCP", targets: ["NetworkPNTRMCP"])],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"), .package(url: "https://github.com/apple/swift-log.git", exact: "1.17.0")],
    targets: [
        .target(name: "NetworkPNTRCloudTLS", linkerSettings: [.linkedFramework("Security"), .linkedFramework("CoreFoundation")]),
        .target(name: "NetworkPNTRCore", dependencies: ["NetworkPNTRCloudTLS"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/en.lproj"), .process("Resources/ja.lproj"), .copy("Resources/feature-map.json"), .copy("Resources/auth-terms.ja.json"), .copy("Resources/auth-terms.en.json")]),
        .executableTarget(name: "NetworkPNTRMac", dependencies: ["NetworkPNTRCore"]),
        .executableTarget(name: "VMProbe", dependencies: ["NetworkPNTRCore"]),
        .executableTarget(name: "NetworkPNTRMCP", dependencies: ["NetworkPNTRCore", .product(name: "MCP", package: "swift-sdk"), .product(name: "Logging", package: "swift-log")]),
        .testTarget(name: "NetworkPNTRMCPTests", dependencies: ["NetworkPNTRMCP", "NetworkPNTRCore"]),
        .testTarget(name: "VMProbeTests", dependencies: ["VMProbe", "NetworkPNTRCore"]),
        .testTarget(name: "NetworkPNTRMacTests", dependencies: ["NetworkPNTRMac", "NetworkPNTRCore"]),
        .testTarget(name: "NetworkPNTRCoreTests", dependencies: ["NetworkPNTRCore"], resources: [.copy("Fixtures")])
    ], swiftLanguageModes: [.v6]
)

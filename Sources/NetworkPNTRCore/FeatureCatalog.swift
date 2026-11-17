import Foundation

public struct BrowserFeature: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let browserPath: String
    public let nativeStatus: String
    public let phase: Int
}
public struct BrowserRoute: Codable, Sendable { public let route: String; public let source: String }
public struct FeatureCatalog: Codable, Sendable {
    public let baseline: String
    public let features: [BrowserFeature]
    public let routes: [BrowserRoute]
    public let endpoints: [String]
    public static func load() throws -> FeatureCatalog {
        guard let url = Bundle.module.url(forResource: "feature-map", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

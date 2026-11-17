import Foundation

struct OllamaRuntimeStatus: Decodable {
    struct Cloud: Decodable {
        let disabled: Bool
    }

    let cloud: Cloud

    func requireLocalOnly() throws {
        guard cloud.disabled else { throw OllamaCatalog.Failure.cloudEnabled }
    }
}

public struct OllamaModelList: Decodable, Sendable {
    public let models: [Model]

    public struct Model: Decodable, Sendable {
        public let name: String
        public let digest: String?
        public let size: Int64?
        public let sizeVRAM: Int64?
        public let contextLength: Int?
        public let details: Details?

        enum CodingKeys: String, CodingKey {
            case name, digest, size, details
            case sizeVRAM = "size_vram"
            case contextLength = "context_length"
        }
    }

    public struct Details: Decodable, Sendable {
        public let format: String?
        public let family: String?
        public let parameterSize: String?
        public let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case format, family
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }
}

public struct OllamaModelMetadata: Decodable, Sendable {
    public let capabilities: [String]?
    public let maximumContext: Int?

    public var supportsTools: Bool? { capabilities.map { $0.contains("tools") } }

    func validateContextLength(_ requested: Int) throws {
        guard requested > 0, let maximumContext, requested <= maximumContext else {
            throw OllamaCatalog.Failure.unverifiedContextLength
        }
    }

    private enum CodingKeys: String, CodingKey {
        case capabilities
        case modelInfo = "model_info"
    }

    private struct MetadataKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities)
        if container.contains(.modelInfo), try !container.decodeNil(forKey: .modelInfo) {
            let metadata = try container.nestedContainer(keyedBy: MetadataKey.self, forKey: .modelInfo)
            let architecture = try metadata.decodeIfPresent(String.self, forKey: .init(stringValue: "general.architecture"))
            let limit = try architecture.flatMap {
                try metadata.decodeIfPresent(Int.self, forKey: .init(stringValue: $0 + ".context_length"))
            }
            maximumContext = limit.flatMap { $0 > 0 ? $0 : nil }
        } else {
            maximumContext = nil
        }
    }
}

public struct OllamaInferenceMetrics: Decodable, Sendable {
    public let model: String
    public let done: Bool
    public let inputTokens: Int64?
    public let outputTokens: Int64?
    public let totalNanoseconds: Int64?
    public let generationNanoseconds: Int64?

    enum CodingKeys: String, CodingKey {
        case model, done
        case inputTokens = "prompt_eval_count"
        case outputTokens = "eval_count"
        case totalNanoseconds = "total_duration"
        case generationNanoseconds = "eval_duration"
    }

    public var outputTokensPerSecond: Double? {
        guard done, let outputTokens, outputTokens >= 0,
              let generationNanoseconds, generationNanoseconds > 0 else { return nil }
        return Double(outputTokens) * 1_000_000_000 / Double(generationNanoseconds)
    }
}

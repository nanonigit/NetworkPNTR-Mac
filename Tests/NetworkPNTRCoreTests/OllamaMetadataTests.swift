import Foundation
import XCTest
@testable import NetworkPNTRCore

final class OllamaMetadataTests: XCTestCase {
    func testContextIsValidatedAgainstDiscoveredArchitectureLimit() throws {
        let metadata = try JSONDecoder().decode(OllamaModelMetadata.self, from: Data(
            #"{"model_info":{"general.architecture":"custom","custom.context_length":1024}}"#.utf8
        ))
        XCTAssertNoThrow(try metadata.validateContextLength(1_024))
        for length in [0, -1, 1_025, 2_048] {
            XCTAssertThrowsError(try metadata.validateContextLength(length)) {
                XCTAssertEqual($0 as? OllamaCatalog.Failure, .unverifiedContextLength)
            }
        }
        let unknown = try JSONDecoder().decode(OllamaModelMetadata.self, from: Data("{}".utf8))
        XCTAssertThrowsError(try unknown.validateContextLength(1_024))
    }

    func testTextChatUsesBoundedNonStreamingRequestAndDecodesMetrics() throws {
        let messages = [OllamaTextMessage(role: .user, content: "Hello")]
        let request = try OllamaTextRequest(model: "fixture", messages: messages, contextLength: 2_048)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertEqual(object["options"] as? [String: Int], ["num_ctx": 2_048, "num_predict": 1_024])
        XCTAssertNil(object["tools"])
        XCTAssertThrowsError(try OllamaTextRequest(model: "fixture", messages: [], contextLength: 2_048))
        XCTAssertThrowsError(try OllamaTextRequest(model: "fixture", messages: messages, contextLength: 32_769))
        XCTAssertThrowsError(try OllamaTextRequest(model: "fixture", messages: [
            .init(role: .user, content: String(repeating: "a", count: OllamaTextRequest.bodyLimit + 1))
        ], contextLength: 2_048))
        let reply = try JSONDecoder().decode(OllamaTextReply.self, from: Data(
            #"{"model":"fixture","message":{"role":"assistant","content":"Hello"},"done":true,"eval_count":12,"eval_duration":300000000}"#.utf8
        ))
        XCTAssertEqual(reply.message.content, "Hello")
        XCTAssertEqual(reply.metrics.outputTokensPerSecond, 40)
    }

    func testLocalOnlyRequiresExplicitCloudDisabledStatus() throws {
        let decoder = JSONDecoder()
        let disabled = try decoder.decode(OllamaRuntimeStatus.self, from: Data(
            #"{"cloud":{"disabled":true,"source":"env"}}"#.utf8
        ))
        XCTAssertNoThrow(try disabled.requireLocalOnly())
        let enabled = try decoder.decode(OllamaRuntimeStatus.self, from: Data(
            #"{"cloud":{"disabled":false}}"#.utf8
        ))
        XCTAssertThrowsError(try enabled.requireLocalOnly()) {
            XCTAssertEqual($0 as? OllamaCatalog.Failure, .cloudEnabled)
        }
        XCTAssertThrowsError(try decoder.decode(OllamaRuntimeStatus.self, from: Data(
            #"{"cloud":{}}"#.utf8
        )))
    }

    func testModelIdentityAndCapacityComeFromRuntimeMetadata() throws {
        let list = try JSONDecoder().decode(OllamaModelList.self, from: Data(
            #"{"models":[{"name":"arbitrary-model:custom","size":5000000000,"size_vram":4000000000,"context_length":8192,"details":{"format":"gguf","quantization_level":"Q4_K_M"}}]}"#.utf8
        ))
        let model = try XCTUnwrap(list.models.first)
        XCTAssertEqual(model.name, "arbitrary-model:custom")
        XCTAssertEqual(model.details?.quantizationLevel, "Q4_K_M")
        XCTAssertEqual(model.contextLength, 8192)
        XCTAssertEqual(model.sizeVRAM, 4_000_000_000)
        let metadata = try JSONDecoder().decode(OllamaModelMetadata.self, from: Data(
            #"{"capabilities":["completion","tools"],"model_info":{"general.architecture":"fixture","fixture.context_length":32768,"other.context_length":99999}}"#.utf8
        ))
        XCTAssertEqual(metadata.supportsTools, true)
        XCTAssertEqual(metadata.maximumContext, 32_768)
        let unknown = try JSONDecoder().decode(OllamaModelMetadata.self, from: Data("{}".utf8))
        XCTAssertNil(unknown.supportsTools)
        XCTAssertNil(unknown.maximumContext)
    }

    func testRateUsesOnlyCompletedGenerationTime() throws {
        let metrics = try JSONDecoder().decode(OllamaInferenceMetrics.self, from: Data(
            #"{"model":"arbitrary-model:custom","done":true,"prompt_eval_count":12,"eval_count":24,"total_duration":2000000000,"eval_duration":600000000}"#.utf8
        ))
        XCTAssertEqual(metrics.inputTokens, 12)
        XCTAssertEqual(metrics.outputTokens, 24)
        XCTAssertEqual(metrics.totalNanoseconds, 2_000_000_000)
        XCTAssertEqual(metrics.outputTokensPerSecond, 40)
        let partial = try JSONDecoder().decode(OllamaInferenceMetrics.self, from: Data(
            #"{"model":"arbitrary-model:custom","done":false,"eval_count":24,"eval_duration":600000000}"#.utf8
        ))
        XCTAssertNil(partial.outputTokensPerSecond)
    }
}

import Foundation
import XCTest
@testable import NetworkPNTRCore

final class AssetCatalogServiceTests: XCTestCase {
    @MainActor func testListPreservesDSLAndDecodesOptionalFieldsAndLargeIdentifiers() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        let dsl = #"ip="198.51.100.1" || domain="日本語+ & ? # %""#
        try client.enqueue([
            "count": 1, "total": 26,
            "assets": [[
                "id": Int64(9_007_199_254_740_993), "type": "ip", "last_seen": "2026-10-22T10:00:00Z",
                "task_ids": NSNull(), "ip": "198.51.100.1", "open_ports": [["port": 443, "service": "https"]]
            ]]
        ])
        let result = try await service.list(type: .ip, dsl: " \(dsl) ", page: 1, size: 25)
        XCTAssertEqual(result.assets.first?.id, 9_007_199_254_740_993)
        XCTAssertEqual(result.assets.first?.openPorts?.first?.port, 443)
        XCTAssertNil(result.assets.first?.taskIds)
        XCTAssertEqual(result.total, 26)
        let path = try XCTUnwrap(client.calls.first?.path)
        XCTAssertTrue(path.contains("%2B"))
        XCTAssertEqual(URLComponents(string: path)?.queryItems, [
            .init(name: "type", value: "ip"), .init(name: "limit", value: "25"),
            .init(name: "offset", value: "25"), .init(name: "dsl", value: dsl)
        ])
    }

    @MainActor func testAcceptsEmptyPageWithTotalAndRejectsInconsistentReceipts() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        try client.enqueue(["count": 0, "total": 7, "assets": []])
        let page = try await service.list(type: .service, page: 5)
        XCTAssertTrue(page.assets.isEmpty)
        XCTAssertEqual(page.total, 7)
        try client.enqueue(["count": 1, "total": 1, "assets": []])
        do {
            _ = try await service.list(type: .service)
            XCTFail("Expected invalid response")
        } catch BackendAPIError.invalidResponse {}
    }

    @MainActor func testValidatesPagingLocallyAndPreservesBackendErrorStatus() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        do {
            _ = try await service.list(type: .endpoint, page: .max, size: 200)
            XCTFail("Expected invalid query")
        } catch AssetCatalogQueryError.invalidQuery {}
        XCTAssertTrue(client.calls.isEmpty)

        try client.enqueue(["error": "invalid expression"], status: 400)
        do {
            _ = try await service.list(type: .endpoint, dsl: "(")
            XCTFail("Expected backend validation error")
        } catch BackendAPIError.status(400) {}

        try client.enqueue(["root_domain": 1, "endpoint": 0])
        let counts = try await service.counts()
        XCTAssertEqual(counts, ["root_domain": 1, "endpoint": 0])
        XCTAssertEqual(client.calls.last?.path, "/api/assets/counts")
    }

    @MainActor func testCompanyListAcceptsNullAndDecodesScopeSummaries() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        client.replies.append(.init(status: 200, body: Data("null".utf8)))
        let empty = try await service.companies()
        XCTAssertTrue(empty.isEmpty)
        try client.enqueue([[
            "id": 8200, "name": "Fixture", "asset_count": 3,
            "scope": [["raw": "*.example.test"]]
        ]])
        let companies = try await service.companies()
        XCTAssertEqual(companies.first?.scope?.first?.raw, "*.example.test")
        XCTAssertEqual(companies.first?.assetCount, 3)
    }

    @MainActor func testChangingSearchResetsPageAndRejectsOldResults() async throws {
        let client = ChatTestTransport()
        let store = AssetCatalogStore(service: AssetCatalogService(client: client))
        XCTAssertNil(store.query.type)
        store.select(.rootDomain)
        store.setPage(1)
        let old = store.query
        client.handler = { call in
            if call.path.contains("offset=50") {
                store.search(#"domain="fixture.example.test""#)
                return try ChatTestTransport.response(["assets": [], "count": 0, "total": 54])
            }
            return try ChatTestTransport.response(["assets": [], "count": 0, "total": 0])
        }
        await store.refreshPage(old)
        XCTAssertEqual(store.query.page, 0)
        XCTAssertNil(store.page.value)
        await store.refreshPage(store.query)
        XCTAssertEqual(store.page.value?.total, 0)
        store.select(.ip)
        XCTAssertTrue(store.query.dsl.isEmpty)
        XCTAssertNil(store.page.value)
    }

    @MainActor func testDeletesExactIDsOnceAndAcceptsPartialReceipt() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        let ids: [Int64] = [5, 9_007_199_254_740_993]
        try client.enqueue(["deleted": 1])
        let deleted = try await service.deleteAssets(ids: ids)
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(client.calls.count, 1)
        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.method, "DELETE")
        XCTAssertEqual(call.path, "/api/assets")
        let body = try XCTUnwrap(call.body)
        XCTAssertEqual(try JSONDecoder().decode([String: [Int64]].self, from: body), ["ids": ids])
    }

    @MainActor func testDeleteRejectsInvalidIDsAndImpossibleReceiptWithoutRetry() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        for ids: [Int64] in [[], [0], [1, 1]] {
            do {
                _ = try await service.deleteAssets(ids: ids)
                XCTFail("Invalid IDs were accepted")
            } catch AssetCatalogQueryError.invalidQuery {}
        }
        XCTAssertTrue(client.calls.isEmpty)
        try client.enqueue(["deleted": 2])
        do {
            _ = try await service.deleteAssets(ids: [1])
            XCTFail("Impossible deletion count was accepted")
        } catch BackendAPIError.invalidResponse {}
        try client.enqueue(["error": "fixture"], status: 503)
        do {
            _ = try await service.deleteAssets(ids: [1])
            XCTFail("HTTP failure was accepted")
        } catch BackendAPIError.status(503) {}
        XCTAssertEqual(client.calls.count, 2)
    }

    @MainActor func testDeleteInvalidatesPageAndRefreshClampsRemovedLastPage() async throws {
        let client = ChatTestTransport()
        let store = AssetCatalogStore(service: AssetCatalogService(client: client))
        store.select(.rootDomain)
        store.setSize(25)
        store.setPage(1)
        try client.enqueue(["deleted": 1])
        await store.deleteAssets(ids: [26])
        XCTAssertEqual(store.deletedCount, 1)
        XCTAssertTrue(store.page.isStale)
        try client.enqueue(["count": 0, "total": 25, "assets": []])
        await store.refreshPage(store.query)
        XCTAssertEqual(store.query.page, 0)
        XCTAssertNil(store.page.value)
        XCTAssertEqual(client.calls.map(\.method), ["DELETE", "GET"])
    }

    @MainActor func testCreatesCompanyWithStructuredScopeAndPreservesConflict() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        let scope = [CompanyScopeInput(kind: .domain, value: "*.example.test")]
        try client.enqueue(["id": 7, "created": true, "scope_added": 1, "scope_skipped": 0, "scope_invalid": 0], status: 201)
        let created = try await service.createCompany(name: " Fixture ", scope: scope)
        XCTAssertEqual(created.id, 7)
        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.path, "/api/companies")
        let json = try JSONSerialization.jsonObject(with: XCTUnwrap(call.body)) as? [String: Any]
        XCTAssertEqual(json?["name"] as? String, "Fixture")
        XCTAssertEqual(json?["scope"] as? [[String: String]], [["kind": "domain", "value": "*.example.test"]])
        try client.enqueue(["error": "fixture conflict"], status: 409)
        do {
            _ = try await service.createCompany(name: "Fixture", scope: scope)
            XCTFail("Duplicate name should report conflict")
        } catch BackendAPIError.status(409) {}
        XCTAssertEqual(client.calls.count, 2)
    }

    @MainActor func testClearsScopeAndPreservesDeleteAssetChoice() async throws {
        let client = ChatTestTransport()
        let service = AssetCatalogService(client: client)
        try client.enqueue(["added": 0, "skipped": 0, "invalid": 0, "warnings": ["fixture"]])
        let receipt = try await service.writeCompanyScope(id: 7, scope: [], replace: true)
        XCTAssertEqual(receipt.warnings, ["fixture"])
        XCTAssertEqual(client.calls[0].path, "/api/companies/7/scope")
        let replacement = try JSONSerialization.jsonObject(with: XCTUnwrap(client.calls[0].body)) as? [String: Any]
        XCTAssertEqual(replacement?["reset"] as? Bool, true)
        XCTAssertEqual(replacement?["scope"] as? [[String: String]], [])
        try client.enqueue(["deleted": 1, "assets_deleted": 0])
        let deleted = try await service.deleteCompany(id: 7, deleteAssets: false)
        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(client.calls[1].method, "DELETE")
        XCTAssertEqual(client.calls[1].path, "/api/companies/7")
        let deletion = try JSONDecoder().decode([String: Bool].self, from: XCTUnwrap(client.calls[1].body))
        XCTAssertEqual(deletion, ["delete_assets": false])
    }

    @MainActor func testDSLValidationIsLocalizedAndCorrectionClearsFailure() async throws {
        let client = ChatTestTransport()
        let store = AssetCatalogStore(service: AssetCatalogService(client: client))
        store.select(.rootDomain)
        store.search("(")
        try client.enqueue(["error": "fixture parser details"], status: 400)
        await store.refreshPage(store.query)
        XCTAssertNil(store.page.value)
        for language in [AppLanguage.english, .japanese] {
            XCTAssertEqual(store.page.failure?.text(language: language),
                           AppStrings.text(.assetDSLInvalidExpression, language: language))
        }

        store.search(#"domain=="fixture.example.test""#)
        try client.enqueue(["count": 0, "total": 0, "assets": []])
        await store.refreshPage(store.query)
        XCTAssertNil(store.page.failure)
        XCTAssertEqual(store.page.value?.total, 0)

        store.search("")
        try client.enqueue(["error": "fixture unrelated bad request"], status: 400)
        await store.refreshPage(store.query)
        XCTAssertEqual(store.page.failure?.text(language: .english),
                       AppErrorText.text(BackendAPIError.status(400), language: .english))
    }

    @MainActor func testServiceLinkRequiresHTTPServiceWithAbsoluteWebURL() throws {
        func destination(_ url: String, serviceType: String = "http", type: String = "service") throws -> URL? {
            let response = try ChatTestTransport.response([
                "id": 1, "type": type, "service_type": serviceType, "url": url,
                "last_seen": "2026-10-22T10:00:00Z"
            ])
            return try BackendJSONCoding.decode(AssetCatalogRow.self, from: response.body).httpServiceDestination
        }
        XCTAssertEqual(try destination("https://example.test/status?q=1")?.absoluteString,
                       "https://example.test/status?q=1")
        XCTAssertNotNil(try destination("http://192.0.2.17:8080/"))
        for unsafe in ["file:///tmp/report", "javascript:alert(1)", "/status", "https://",
                       "https://name:secret@example.test/", "https://example.test/a b"] {
            XCTAssertNil(try destination(unsafe), unsafe)
        }
        XCTAssertNil(try destination("https://example.test", serviceType: "other"))
        XCTAssertNil(try destination("https://example.test", type: "endpoint"))
    }

    @MainActor func testServerFailureStaysDistinctFromEmptyResultsAndRefreshesSameQuery() async throws {
        let client = ChatTestTransport()
        let store = AssetCatalogStore(service: AssetCatalogService(client: client))
        store.select(.rootDomain)
        store.search(#"domain=="fixture-26.example.test""#)
        let query = store.query

        try client.enqueue(["error": "Synthetic asset list failure"], status: 500)
        await store.refreshPage(query)
        XCTAssertNil(store.page.value)
        XCTAssertTrue(store.page.isStale)
        XCTAssertEqual(store.page.failure?.text(language: .english),
                       AppErrorText.text(BackendAPIError.status(500), language: .english))

        try client.enqueue([
            "count": 1, "total": 1, "assets": [[
                "id": 9026, "type": "root_domain", "domain": "fixture-26.example.test",
                "last_seen": "2026-10-22T10:00:00Z"
            ]]
        ])
        await store.refreshPage(store.query)
        XCTAssertEqual(store.query, query)
        XCTAssertNil(store.page.failure)
        XCTAssertFalse(store.page.isStale)
        XCTAssertEqual(store.page.value?.assets.map(\.id), [9026])
        XCTAssertEqual(client.calls.count, 2)
        XCTAssertEqual(client.calls.first?.path, client.calls.last?.path)
    }

    @MainActor func testUnconfirmedDeletionRefreshesWithoutResendingMutation() async throws {
        let client = ChatTestTransport()
        let store = AssetCatalogStore(service: AssetCatalogService(client: client))
        store.select(.rootDomain)
        func page(_ ids: [Int]) -> [String: Any] {
            ["count": ids.count, "total": ids.count, "assets": ids.map {
                ["id": $0, "type": "root_domain", "last_seen": "2026-10-22T10:00:00Z"]
            }]
        }

        try client.enqueue(page([9026, 9025]))
        await store.refreshPage(store.query)
        XCTAssertEqual(store.page.value?.assets.map(\.id), [9026, 9025])

        try client.enqueue(["error": "Synthetic asset delete receipt lost"], status: 500)
        await store.deleteAssets(ids: [9026])
        XCTAssertTrue(store.deletionUnconfirmed)
        XCTAssertNil(store.deletedCount)
        XCTAssertNil(store.page.value)
        XCTAssertTrue(store.page.isStale)

        try client.enqueue(page([9025]))
        await store.refreshPage(store.query)
        XCTAssertEqual(store.page.value?.assets.map(\.id), [9025])
        XCTAssertTrue(store.deletionUnconfirmed)
        XCTAssertEqual(client.calls.map(\.method), ["GET", "DELETE", "GET"])
    }

}

import Foundation

@MainActor package protocol EvidenceDestinationChoosing: AnyObject {
    func choose(suggestedFilename: String) async -> URL?
    func cancel()
}

import Foundation
import Observation

/// SwiftUI task identity must not equate canonically equivalent but distinct input bytes.
public struct ChatUserBodyKey: Hashable, Sendable {
    private let conversationID: Int64
    private let sequence: Int64
    private let summary: Data
    private let inline: Data?
    public init(conversationID: Int64, activity: ChatActivity) {
        self.conversationID = conversationID; sequence = activity.seq
        summary = Data(activity.summary.utf8)
        inline = activity.detail.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
    }
}

@MainActor @Observable public final class ChatUserBodyStore {
    public private(set) var body: ChatUserBody
    public private(set) var isLoading = false
    public private(set) var error: String?
    @ObservationIgnored private var key: ChatUserBodyKey?
    @ObservationIgnored private var generation = UUID()
    public init(summary: String, detail: String? = nil) {
        body = ChatUserBody(rawBody: detail.flatMap { $0.isEmpty ? nil : $0 } ?? summary)
    }
    public func load(conversationID: Int64, activity: ChatActivity,
                     detail: @MainActor (Int64, Int64) async throws -> String) async {
        guard !Task.isCancelled else { return }
        let next = ChatUserBodyKey(conversationID: conversationID, activity: activity)
        let inline = activity.detail.flatMap { $0.isEmpty ? nil : $0 }
        let ticket = UUID(); generation = ticket
        if key != next {
            key = next; body = ChatUserBody(rawBody: inline ?? activity.summary)
        }
        error = nil; isLoading = false
        guard conversationID > 0, activity.seq > 0, activity.kind == "user" else { return }
        if let inline { body = ChatUserBody(rawBody: inline); return }
        isLoading = true
        defer { if generation == ticket { isLoading = false } }
        do {
            let text = try await detail(conversationID, activity.seq)
            guard generation == ticket, !Task.isCancelled else { return }
            body = ChatUserBody(rawBody: text.isEmpty ? activity.summary : text)
        } catch {
            guard generation == ticket, !Task.isCancelled, !(error is CancellationError) else { return }
            body = ChatUserBody(rawBody: activity.summary)
            self.error = "メッセージ本文を取得できませんでした。"
        }
    }
    public func stop() { generation = UUID(); isLoading = false }
}

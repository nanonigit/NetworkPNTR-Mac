/// Both availability and geometry must participate in scroll observation equality.
public struct AuthTermsViewport: Equatable, Sendable {
    public let documentLoaded: Bool
    public let atEnd: Bool
    public init(documentLoaded: Bool, atEnd: Bool) {
        self.documentLoaded = documentLoaded; self.atEnd = atEnd
    }
}

/// Per-open reading latch, matching the pinned browser across locale changes.
public struct AuthTermsReadingProgress: Sendable {
    public private(set) var hasReadToEnd = false
    public init() {}
    public mutating func observe(_ viewport: AuthTermsViewport) {
        if viewport.documentLoaded && viewport.atEnd { hasReadToEnd = true }
    }
    public func canAgree(documentLoaded: Bool) -> Bool { documentLoaded && hasReadToEnd }
}

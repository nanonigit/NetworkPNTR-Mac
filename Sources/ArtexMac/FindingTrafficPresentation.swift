import Foundation

enum FindingTrafficPresentation {
    static func captureDate(seconds: Int64) -> Date { Date(timeIntervalSince1970:Double(seconds)) }
}

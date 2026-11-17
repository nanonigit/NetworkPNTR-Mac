import Foundation
import NetworkPNTRCore

enum FindingTrafficPresentation {
    static func recordedDate(_ raw: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        if let date = parser.date(from:raw) { return date }
        parser.formatOptions = [.withInternetDateTime]; return parser.date(from:raw)
    }
    static func captureDate(seconds: Int64) -> Date { Date(timeIntervalSince1970:Double(seconds)) }
    static func roleLabel(_ raw: String,language: AppLanguage) -> String {
        let key: AppStringKey? = switch FindingTrafficRole(rawValue:raw) {
        case .baseline: .evidenceUIBaseline
        case .proof: .evidenceUIProof
        case .verification: .evidenceUIVerification
        case .supporting: .evidenceUISupporting
        case nil: nil
        }
        return key.map { AppStrings.text($0,language:language) } ?? raw
    }
}

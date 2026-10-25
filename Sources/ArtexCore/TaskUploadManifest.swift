import Foundation

public enum TaskUploadManifest {
    /// Match the pinned browser's appendUploads; language changes never rewrite existing text.
    public static func appending(to description: String, attachments: [TaskStagedAttachment], language: AppLanguage) -> String {
        guard !attachments.isEmpty else { return description }
        let marker = AppStrings.text(.taskUploadMarker, language: language)
        let bullets = attachments.map { "- " + $0.absolutePath + " (" + bytes($0.size) + ")" }.joined(separator: "\n")
        let tailTrimmed = ChatText.trimmingEnd(description)
        // JS includes uses exact code units, unlike Swift canonical-equivalence matching.
        if Data(description.utf8).range(of: Data(marker.utf8)) != nil { return tailTrimmed + "\n" + bullets + "\n" }
        let head = ChatText.trim(description).isEmpty ? "" : tailTrimmed + "\n\n"
        return head + marker + " " + AppStrings.text(.taskUploadHint, language: language) + "\n" + bullets + "\n"
    }
    private static func bytes(_ value: Int64) -> String {
        guard value >= 1024 else { return "\(value) B" }
        let unit: Int64 = value >= 1048576 ? 1048576 : 1024
        // Sizes are validated <=128MiB. Integer ties round upward as JS toFixed(1).
        let tenths = (value * 10 + unit / 2) / unit
        return "\(tenths / 10).\(tenths % 10) " + (unit == 1024 ? "KB" : "MB")
    }
}

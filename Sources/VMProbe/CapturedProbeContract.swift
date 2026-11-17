#if DEBUG
import NetworkPNTRCore
import Foundation

/// Independent native expectations for the fixed guest fixture; original bytes are never localized.
enum CapturedProbeContract {
    static let prefix = "http://127.0.0.1:8799/f5-captured/"
    static let literal = Data("\u{FEFF}e\u{301} English Japanese 日本語 中文 한국어\r\n".utf8)
    static let note = "F5 edited \u{FEFF}e\u{301} English Japanese 日本語 中文 한국어\u{FEFF}"
    static func require(_ condition: Bool) throws { guard condition else { throw RuntimeError.integrity("captured native probe") } }
    static func ordinal(_ url: String) throws -> Int {
        let bytes = Data(url.utf8), base = Data(prefix.utf8)
        try require(bytes.starts(with:base) && bytes.count == base.count+2)
        let suffix = bytes.suffix(2);try require(suffix.allSatisfy{(48...57).contains($0)})
        guard let value=Int(String(decoding:suffix,as:UTF8.self)), (0..<29).contains(value) else { throw RuntimeError.integrity("captured fixed URL") }
        return value
    }
    static func bytes(_ index: Int,side: FindingEvidenceSide) throws -> Data {
        try require((0..<29).contains(index))
        if side == .request { return index%2 == 0 ? Data():literal+Data(String(index).utf8) }
        switch index {
        case 0:return Data()
        case 1:return literal
        case 2,4:
            var value=Data();for _ in 0..<(index==2 ? 256:1025) { value.append(contentsOf:(0...255).map{UInt8($0)}) }
            value.append(Data((index==2 ? "END":"Z").utf8));return value
        case 3:return Data(String(repeating:"e\u{301}",count:3001).utf8)
        default:return Data(String(format:"F5 captured ordinal %02d\r\n",index).utf8)
        }
    }
    static func validate(_ value: FindingEvidencePreview,data: Data,offset: Int64) throws -> [String:Any] {
        try require(offset>=0 && offset<=data.count)
        var raw=Data(data.dropFirst(Int(offset)).prefix(8192))
        if offset+Int64(raw.count)<data.count,raw.count>=4,String(data:raw,encoding:.utf8)==nil {
            for trim in 1...3 where raw.count>trim {
                let candidate=Data(raw.dropLast(trim))
                if String(data:candidate,encoding:.utf8) != nil {raw=candidate;break}
            }
        }
        let binary=raw.contains(0) || (offset==0 && String(data:raw,encoding:.utf8)==nil)
        let content=binary ? "[二进制正文，\(data.count) 字节；请下载查看]":String(decoding:raw,as:UTF8.self)
        let next=offset+Int64(raw.count),truncated=next<data.count
        try require(Data(value.content.utf8)==Data(content.utf8) && value.offset==offset && value.total==data.count && value.nextOffset==next && value.binary==binary && value.truncated==truncated)
        return ["offset":offset,"next_offset":next,"binary":binary,"truncated":truncated,"content_sha256":ArtifactIntegrity.sha256(Data(value.content.utf8))]
    }
    static func editedBinding(_ value: FindingTraffic,first: String,second: String) throws -> FindingTrafficBinding {
        try require(value.bindings.map(\.id)==[first,second])
        guard let binding=value.bindings.first else {throw RuntimeError.integrity("captured edited membership")}
        return binding
    }
    static func normalized(_ value: FindingTraffic) throws -> [String:Any] {
        let bindings=try value.bindings.map { row -> [String:Any] in
            let snapshot=row.snapshot
            return ["ordinal":try ordinal(snapshot.url),"role":row.role,"note_sha256":ArtifactIntegrity.sha256(Data(row.note.utf8)),"position":row.position,"req_len":snapshot.requestLength,"resp_len":snapshot.responseLength,"req_hash":snapshot.requestHash,"resp_hash":snapshot.responseHash]
        }
        return ["version":value.version,"report_version":value.reportVersion,"bindings":bindings]
    }
    struct Completion {
        let boots,cooperativeStops,cleanAudits: Int
        let sourceVerified,referenceEqual,persistence,uncertaintyRecovered,machineStopped: Bool
        func validate() throws {
            try CapturedProbeContract.require(boots==2 && cooperativeStops==2 && cleanAudits==2 && sourceVerified && referenceEqual && persistence && uncertaintyRecovered && machineStopped)
        }
    }
}
#endif

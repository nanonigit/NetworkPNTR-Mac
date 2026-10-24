import Darwin
import Foundation

public enum ChatUploadBodyError: LocalizedError {
    case invalidFile, invalidFraming, tooLarge, changedFile, readFailure
    public var errorDescription: String? { AppErrorText.text(self, language: .japanese) }
}

/// Immutable file/framing preflight that may cross to a dedicated transfer worker.
public struct ChatMultipartPlan: Sendable {
    public static let maximumBytes: Int64 = 128 * 1024 * 1024
    public let contentType: String
    public let contentLength: Int64
    fileprivate struct Stamp: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int
        init(_ info: stat) {
            device = info.st_dev; inode = info.st_ino; size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec; changedNanos = info.st_ctimespec.tv_nsec
        }
    }
    fileprivate struct Source: Sendable { let url: URL; let stamp: Stamp; let header: Data }
    fileprivate let sources: [Source]
    fileprivate let ending: Data
    public init(files: [URL], boundary: String = "ArtexMac-" + UUID().uuidString) throws {
        guard !files.isEmpty else { throw ChatUploadBodyError.invalidFile }
        guard (1...70).contains(boundary.utf8.count), boundary.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { throw ChatUploadBodyError.invalidFraming }
        var prepared: [Source] = [], total: Int64 = 0
        func account(_ count: Int64) throws {
            guard count >= 0, count <= Self.maximumBytes - total else { throw ChatUploadBodyError.tooLarge }
            total += count
        }
        for url in files {
            try Task.checkCancellation()
            guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
                  !url.path.utf8.contains(0) else { throw ChatUploadBodyError.invalidFile }
            let name = url.lastPathComponent
            guard !name.isEmpty, name != ".", name != ".." else { throw ChatUploadBodyError.invalidFile }
            let fd = try Self.open(url)
            let stamp: Stamp
            do { stamp = try Self.stamp(fd); Darwin.close(fd) }
            catch { Darwin.close(fd); throw error }
            // Form-data escapes quotes and newlines rather than allowing new headers.
            let escaped = name.replacingOccurrences(of: "\r", with: "%0D")
                .replacingOccurrences(of: "\n", with: "%0A").replacingOccurrences(of: "\"", with: "%22")
            let header = Data(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"" + escaped + "\"\r\nContent-Type: application/octet-stream\r\n\r\n").utf8)
            try account(Int64(header.count)); try account(stamp.size); try account(2)
            prepared.append(Source(url: url, stamp: stamp, header: header))
        }
        ending = Data(("--" + boundary + "--\r\n").utf8)
        try account(Int64(ending.count))
        sources = prepared; contentLength = total
        contentType = "multipart/form-data; boundary=" + boundary
    }
    fileprivate static func open(_ url: URL) throws -> Int32 {
        // O_NONBLOCK prevents a selected FIFO/device from blocking preflight before fstat.
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ChatUploadBodyError.invalidFile }
        return fd
    }
    fileprivate static func stamp(_ fd: Int32) throws -> Stamp {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
            throw ChatUploadBodyError.invalidFile
        }
        return Stamp(info)
    }
}

/// A single-consumer multipart body; construct and read on the transfer worker.
/// Does not open sockets, retain content buffers, or own security-scoped bookmarks.
public final class ChatMultipartBody {
    public static let maximumBytes = ChatMultipartPlan.maximumBytes
    public static let chunkBytes = 65536
    public var contentType: String { plan.contentType }
    public var contentLength: Int64 { plan.contentLength }
    private let plan: ChatMultipartPlan
    private var sources: [ChatMultipartPlan.Source] { plan.sources }
    private var ending: Data { plan.ending }
    private enum Stage { case header, file, separator, closing }
    private enum State { case active, finished, cancelled, failed }
    private var stage = Stage.header
    private var state = State.active
    private var index = 0
    private var offset = 0
    private var fileOffset: Int64 = 0
    private var descriptor: Int32 = -1

    public init(plan: ChatMultipartPlan) { self.plan = plan }
    public convenience init(files: [URL], boundary: String = "ArtexMac-" + UUID().uuidString) throws {
        self.init(plan: try ChatMultipartPlan(files: files, boundary: boundary))
    }
    deinit { releaseDescriptor() }

    /// Cancels this reader permanently. The owner must not call concurrently with read.
    public func close() { releaseDescriptor(); state = .cancelled }

    /// Returns at most64KiB; nil only after the complete declared body has been read.
    public func read(maximum: Int = ChatMultipartBody.chunkBytes) throws -> Data? {
        switch state {
        case .finished: return nil
        case .cancelled: throw CancellationError()
        case .failed: throw ChatUploadBodyError.readFailure
        case .active: break
        }
        do {
            try Task.checkCancellation()
            guard (1...Self.chunkBytes).contains(maximum) else { throw ChatUploadBodyError.invalidFraming }
            while true {
                switch stage {
                case .header:
                    let bytes = take(sources[index].header, maximum: maximum)
                    if offset == sources[index].header.count { offset = 0; stage = .file }
                    return bytes
                case .file:
                    let source = sources[index]
                    if descriptor < 0 {
                        do { descriptor = try ChatMultipartPlan.open(source.url) }
                        catch { throw ChatUploadBodyError.changedFile }
                    }
                    guard try ChatMultipartPlan.stamp(descriptor) == source.stamp else { throw ChatUploadBodyError.changedFile }
                    if fileOffset == source.stamp.size {
                        var extra: UInt8 = 0
                        let count = try readBytes(&extra, count: 1)
                        guard count == 0, try ChatMultipartPlan.stamp(descriptor) == source.stamp else { throw ChatUploadBodyError.changedFile }
                        releaseDescriptor(); fileOffset = 0; stage = .separator
                        continue
                    }
                    let size = min(maximum, Int(source.stamp.size - fileOffset))
                    var bytes = Data(count: size)
                    let count = try bytes.withUnsafeMutableBytes { buffer in
                        try readBytes(buffer.baseAddress!, count: size)
                    }
                    guard count > 0, try ChatMultipartPlan.stamp(descriptor) == source.stamp else { throw ChatUploadBodyError.changedFile }
                    fileOffset += Int64(count); bytes.count = count
                    return bytes
                case .separator:
                    let bytes = take(Data("\r\n".utf8), maximum: maximum)
                    if offset == 2 {
                        offset = 0; index += 1
                        stage = index == sources.count ? .closing : .header
                    }
                    return bytes
                case .closing:
                    let bytes = take(ending, maximum: maximum)
                    if offset == ending.count { state = .finished }
                    return bytes
                }
            }
        } catch {
            releaseDescriptor(); state = error is CancellationError ? .cancelled : .failed
            throw error
        }
    }
    private func take(_ bytes: Data, maximum: Int) -> Data {
        let end = min(bytes.count, offset + maximum)
        defer { offset = end }
        return Data(bytes[offset..<end])
    }
    private func readBytes(_ buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        while true {
            let result = Darwin.read(descriptor, buffer, count)
            if result < 0, errno == EINTR { try Task.checkCancellation(); continue }
            guard result >= 0 else { throw ChatUploadBodyError.readFailure }
            return result
        }
    }
    private func releaseDescriptor() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }
}

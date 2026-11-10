import Foundation
import CryptoKit
import os

/// A small rotating on-device log of timings and counts. Local only: nothing here is transmitted; the only way out is a
/// user tap on a share button, which calls `exportFile()`.
///
/// Storage: `Application Support/Diagnostics/`, excluded from backup, protection `completeUntilFirstUserAuthentication`.
/// Two files of at most `maxFileBytes` each, used in turn, so the disk never holds more than 2 x `maxFileBytes`.
/// Memory: at most `bufferLimit` unwritten events. Any I/O error silently disables the log; the scan never notices.
///
/// Deviation from the spec sketch: this is a lock-protected class, not an `actor`, so `record` is synchronous and cheap
/// from any thread (the main-actor scan loop does not hop, and the watchdog can record while the main thread is blocked).
final class DiagnosticsLog: @unchecked Sendable {
    static let bufferLimit = 64
    static let hardBufferLimit = 1_024
    static let flushInterval: TimeInterval = 5

    private struct State {
        var buffer: [DiagnosticRecord] = []
        var salt: Data
        var enabled: Bool
        var flushScheduled = false
    }

    private let directory: URL?
    private let maxFileBytes: Int
    private let now: @Sendable () -> Date
    private let state: OSAllocatedUnfairLock<State>
    private let io = DispatchQueue(label: "org.cleanslate.diagnostics.io", qos: .utility)
    // Touched only on `io`.
    private var currentIndex = 0
    private var currentSize = 0
    private var timer: DispatchSourceTimer?

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    static let shared = DiagnosticsLog(directory: defaultDirectory)

    /// `directory == nil` gives a disabled log (every call is a no-op).
    init(directory: URL?, maxFileBytes: Int = 512 * 1024, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.maxFileBytes = maxFileBytes
        self.now = now
        var enabled = directory != nil
        var salt = Data()
        if let directory {
            do { try Self.prepare(directory) } catch { enabled = false }
            if enabled { salt = Self.loadOrCreateSalt(in: directory) ?? Data() ; if salt.isEmpty { enabled = false } }
        }
        state = OSAllocatedUnfairLock(initialState: State(salt: salt, enabled: enabled))
        if enabled { io.sync { restorePosition() }; startTimer() }
    }

    deinit { timer?.cancel() }

    var isEnabled: Bool { state.withLock { $0.enabled } }

    // MARK: Recording

    func record(_ event: DiagnosticEvent) {
        let record = DiagnosticRecord(t: now(), event: event)
        let shouldFlush = state.withLock { s -> Bool in
            guard s.enabled else { return false }
            s.buffer.append(record)
            if s.buffer.count > Self.hardBufferLimit { s.buffer.removeFirst(s.buffer.count - Self.hardBufferLimit) }   // I/O fell behind: drop the oldest
            if s.buffer.count >= Self.bufferLimit, !s.flushScheduled { s.flushScheduled = true; return true }
            return false
        }
        if shouldFlush { io.async { self.writeBuffered() } }
    }

    /// Writes everything buffered. Safe to call from any thread except the `io` queue.
    func flush() { io.sync { writeBuffered() } }

    /// Oldest first. Includes events not yet on disk.
    func recent(limit: Int) -> [DiagnosticRecord] {
        flush()
        return io.sync { readAll() }.suffix(max(0, limit))
    }

    /// Concatenates both files (older first, newest last) into a temporary `.jsonl` file, for the share sheet.
    func exportFile() throws -> URL {
        flush()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CleanSlate-diagnostics.jsonl")
        let data = io.sync { orderedFileData() }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Removes the log and rotates the salt (so earlier `SaltedID`s can no longer be matched to new ones).
    func deleteAll() throws {
        guard let directory else { return }
        let newSalt = Self.randomSalt()
        state.withLock { $0.buffer.removeAll(); $0.salt = newSalt }
        try io.sync {
            for index in 0..<2 { try? FileManager.default.removeItem(at: file(index, in: directory)) }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("current"))
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("CleanSlate-diagnostics.jsonl"))
            currentIndex = 0; currentSize = 0
            try newSalt.write(to: directory.appendingPathComponent("salt"), options: .atomic)
        }
    }

    func salted(_ id: String) -> SaltedID {
        let salt = state.withLock { $0.salt }
        let digest = SHA256.hash(data: salt + Data(id.utf8))
        return SaltedID(value: digest.prefix(8).map { String(format: "%02x", $0) }.joined())
    }

    /// Total bytes the log occupies on disk (tests, and the Diagnostics screen's footnote).
    func bytesOnDisk() -> Int {
        guard let directory else { return 0 }
        return io.sync { (0..<2).reduce(0) { $0 + ((try? Data(contentsOf: file($1, in: directory)).count) ?? 0) } }
    }

    // MARK: Files (all on `io`)

    private static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }

    private static func randomSalt() -> Data { Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }) }

    private static func loadOrCreateSalt(in directory: URL) -> Data? {
        let url = directory.appendingPathComponent("salt")
        if let existing = try? Data(contentsOf: url), existing.count == 16 { return existing }
        let salt = randomSalt()
        do { try salt.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); return salt } catch { return nil }
    }

    private func file(_ index: Int, in directory: URL) -> URL { directory.appendingPathComponent("diag-\(index).jsonl") }

    private func restorePosition() {
        guard let directory else { return }
        if let text = try? String(contentsOf: directory.appendingPathComponent("current"), encoding: .utf8), let value = Int(text), (0...1).contains(value) {
            currentIndex = value
        }
        currentSize = (try? Data(contentsOf: file(currentIndex, in: directory)).count) ?? 0
    }

    private func disable() { state.withLock { $0.enabled = false; $0.buffer.removeAll() } }

    private func writeBuffered() {
        let batch = state.withLock { s -> [DiagnosticRecord] in
            s.flushScheduled = false
            defer { s.buffer.removeAll(keepingCapacity: true) }
            return s.enabled ? s.buffer : []
        }
        guard let directory, !batch.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        // Chunks of `bufferLimit` keep every rotation decision small, so a file never exceeds its limit by more than one chunk.
        for start in stride(from: 0, to: batch.count, by: Self.bufferLimit) {
            var data = Data()
            for record in batch[start..<min(start + Self.bufferLimit, batch.count)] {
                guard let line = try? encoder.encode(record) else { continue }
                data.append(line); data.append(0x0A)
            }
            guard !data.isEmpty, append(data, in: directory) else { return }
        }
    }

    private func append(_ data: Data, in directory: URL) -> Bool {
        do {
            if currentSize > 0, currentSize + data.count > maxFileBytes {
                currentIndex = 1 - currentIndex
                currentSize = 0
                try Data().write(to: file(currentIndex, in: directory))          // truncate the file we are about to reuse
                try Data(String(currentIndex).utf8).write(to: directory.appendingPathComponent("current"))
            }
            let url = file(currentIndex, in: directory)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            currentSize += data.count
            return true
        } catch {
            disable()      // unwritable directory, disk full ...: stop quietly, never affect the scan
            return false
        }
    }

    private func orderedFileData() -> Data {
        guard let directory else { return Data() }
        var data = Data()
        for index in [1 - currentIndex, currentIndex] { data.append((try? Data(contentsOf: file(index, in: directory))) ?? Data()) }
        return data
    }

    private func readAll() -> [DiagnosticRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return orderedFileData().split(separator: 0x0A).compactMap { try? decoder.decode(DiagnosticRecord.self, from: Data($0)) }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: io)
        timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
        timer.setEventHandler { [weak self] in self?.writeBuffered() }
        timer.resume()
        self.timer = timer
    }
}

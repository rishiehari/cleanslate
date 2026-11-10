import XCTest
import CleanSlateCore
@testable import CleanSlate

/// F02 acceptance: the exported diagnostics file of a real (fake-library) scan contains NO photo
/// information — none of the fixture's asset ids, original filenames or capture dates (as strings
/// or as JSON numbers) — and every JSON key in the file is on the allow-list.
@MainActor
final class DiagnosticsLeakTests: XCTestCase {
    private var dir: URL!
    private let iso = ISO8601DateFormatter()

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-leak-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testExportedDiagnosticsAfterRecent100ScanContainNoPhotoInformation() async throws {
        let (library, expected) = FakePhotoLibrary.recent100Scenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        let log = DiagnosticsLog(directory: dir)
        let model = try ScanTestRig.model(library: library, diagnostics: log)
        await model.runScan()
        XCTAssertEqual(model.statistics.photosEnumerated, 100, "the leak test scans the real recent100 scenario")
        log.flush()
        let data = try Data(contentsOf: log.exportFile())
        XCTAssertFalse(data.isEmpty, "the scan produced diagnostics to audit")

        let snapshots = library.assets.values.map(\.snapshot)
        XCTAssertEqual(Set(snapshots.map(\.id)), Set(expected.all), "every fixture asset was enumerated")

        // Ids and filenames: plain byte search.
        for snapshot in snapshots {
            XCTAssertFalse(data.contains(Data(snapshot.id.utf8)), "asset id '\(snapshot.id)' leaked into the diagnostics file")
            if let name = snapshot.originalFilename {
                XCTAssertFalse(data.contains(Data(name.utf8)), "filename '\(name)' leaked into the diagnostics file")
            }
        }
        // The words of a filename can appear inside an id; ids were checked above, but also check the IMG_ prefix pattern.
        XCTAssertFalse(data.contains(Data("IMG_".utf8)), "no original filename pattern appears in the file")

        // Capture dates: ISO-8601 string form (byte search) and seconds-since-1970 numeric form (parsed values).
        let captureTimes = Set(snapshots.compactMap { $0.capturedAt?.timeIntervalSince1970 })
        XCTAssertTrue(snapshots.allSatisfy { $0.capturedAt != nil }, "every fixture photo has a capture date to protect")
        XCTAssertEqual(captureTimes.count, 95, "exact pairs share a timestamp by design; 95 unique times")
        for snapshot in snapshots {
            if let captured = snapshot.capturedAt {
                XCTAssertFalse(data.contains(Data(iso.string(from: captured).utf8)), "capture date of \(snapshot.id) leaked (ISO string)")
            }
        }
        for line in data.split(separator: 0x0A) {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            for (_, value) in object {
                assertNoCaptureDate(in: value, captureTimes: captureTimes)
            }
        }

        // Every JSON key in the file must be on the event allow-list.
        var keys: Set<String> = []
        func collect(_ value: Any) {
            if let object = value as? [String: Any] { for (key, inner) in object { keys.insert(key); collect(inner) } }
            else if let array = value as? [Any] { array.forEach(collect) }
        }
        for line in data.split(separator: 0x0A) { collect(try JSONSerialization.jsonObject(with: Data(line))) }
        XCTAssertFalse(keys.isEmpty)
        XCTAssertTrue(keys.isSubset(of: DiagnosticEvent.allowedKeys), "unexpected keys: \(keys.subtracting(DiagnosticEvent.allowedKeys))")
    }

    /// Walks a decoded JSON value; no number anywhere may equal a photo's capture timestamp.
    private func assertNoCaptureDate(in value: Any, captureTimes: Set<Double>, file: StaticString = #filePath, line: UInt = #line) {
        if let number = value as? NSNumber {
            XCTAssertFalse(captureTimes.contains(number.doubleValue), "capture timestamp \(number) leaked as a JSON number", file: file, line: line)
        } else if let object = value as? [String: Any] {
            for (_, inner) in object { assertNoCaptureDate(in: inner, captureTimes: captureTimes, file: file, line: line) }
        } else if let array = value as? [Any] {
            for inner in array { assertNoCaptureDate(in: inner, captureTimes: captureTimes, file: file, line: line) }
        }
    }
}

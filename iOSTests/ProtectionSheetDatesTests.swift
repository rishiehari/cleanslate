import XCTest
@testable import CleanSlate

@MainActor
final class ProtectionSheetDatesTests: XCTestCase {
    func testReadsEachDistinctPhotoOnceIncludingUnavailablePhotos() async throws {
        let library = FakePhotoLibrary()
        library.add("a", at: 100)
        library.add("b", at: 200)
        var reads: [String] = []
        let dates = await ProtectionSheetDates.load(ids: ["a", "missing", "b", "a", "missing"]) { id in
            reads.append(id)
            return library.snapshot(id: id, inspectAlbums: false)
        }
        XCTAssertEqual(reads, ["a", "missing", "b"])
        XCTAssertEqual(dates?["a"], Date(timeIntervalSince1970: 100))
        XCTAssertEqual(dates?["b"], Date(timeIntervalSince1970: 200))
        XCTAssertNil(dates?["missing"])
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testCancellationBeforeLoadingDoesNoMetadataWork() async {
        var reads = 0
        let work = Task {
            await ProtectionSheetDates.load(ids: ["a", "b"]) { _ in reads += 1; return nil }
        }
        work.cancel()
        let result = await work.value
        XCTAssertNil(result)
        XCTAssertEqual(reads, 0)
    }
}

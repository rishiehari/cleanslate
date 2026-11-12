import XCTest
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class ScopedScanTests: XCTestCase {
    func testFirstScanDefaultAndUserChoicesAreBounded() throws {
        let model = try ScanTestRig.model(library: FakePhotoLibrary())
        XCTAssertEqual(model.currentScanScope, .recentMonth)
        XCTAssertEqual(ScanScope.recentMonth.maximumItems, 2_000)
        XCTAssertEqual(ScanScope.recentTwoMonths.maximumItems, 2_000)
        XCTAssertFalse(ScanScope.userScopes.contains(.all))
        XCTAssertFalse(ScanScope.userScopes.contains(.album))
    }

    func testDatePredicateExcludesOldFutureAndUndatedAssets() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = ScanScope.recentMonth.inventoryRequest(now: now, calendar: calendar)
        let library = FakePhotoLibrary()
        library.add("inside", at: Int64(now.addingTimeInterval(-86400).timeIntervalSince1970))
        library.add("old", at: Int64(calendar.date(byAdding: .month, value: -3, to: now)!.timeIntervalSince1970))
        library.add("future", at: Int64(now.addingTimeInterval(86400).timeIntervalSince1970))
        XCTAssertFalse(request.includes(PhotoSnapshot(id: "undated", record: AssetRecord(id: "undated", revision: "v1"),
            capturedAt: nil, burstID: nil, width: 100, height: 100)))
        let page = try await library.scanInventoryPage(offset: 0, limit: 25, request: request)
        XCTAssertEqual(page.photos.map(\.id), ["inside"])
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(library.thumbnailCalls, 0)
        XCTAssertTrue(library.digestCalls.isEmpty)
    }

    func testCountCapPrunesWiderIndexBeforeEveryAnalysisIncludingRepeatedScan() async throws {
        let library = FakePhotoLibrary()
        for i in 0..<2_100 { library.add("p\(i)", flags: [.favorite], content: "unique\(i)", at: Int64(i), isVideo: true) }
        let store = try LibraryStore(path: nil)
        try await store.upsert(library.assets.values.map(\.snapshot))
        let model = try ScanTestRig.model(library: library, store: store)
        await model.runScan(with: .start2000)
        XCTAssertEqual(model.statistics.photosEnumerated, 2_000)
        XCTAssertTrue(library.pageRequests.allSatisfy { $0 < 2_000 })
        await model.runScan(with: .recent100)
        XCTAssertEqual(model.statistics.photosEnumerated, 100)
        let indexed = await store.assetCount()
        XCTAssertEqual(indexed, 100)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testOverviewDoesNoImageOrDigestWorkAndDoesNotScan() async throws {
        let library = FakePhotoLibrary()
        library.add("a", at: Int64(Date().timeIntervalSince1970))
        let model = try ScanTestRig.model(library: library)
        await model.loadActivityOverview()
        XCTAssertEqual(model.activityOverview?.sampledCount, 1)
        XCTAssertEqual(library.thumbnailCalls, 0)
        XCTAssertTrue(library.digestCalls.isEmpty)
        XCTAssertTrue(library.pageRequests.isEmpty)
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.phase, .idle)
    }

    func testBackgroundWaiterUsesCancellableSharedScanOwner() async throws {
        let library = FakePhotoLibrary()
        library.add("stuck", at: Int64(Date().timeIntervalSince1970 - 60))
        library.stuckThumbnailIDs = ["stuck"]
        let model = try ScanTestRig.model(library: library)
        let work = Task { await model.runSelectedScan() }
        for _ in 0..<100 {
            if library.thumbnailsInFlight > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isScanning)
        model.stop()
        await work.value
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testSuggestedWeekScansOnlyItsDateRange() async throws {
        let library = FakePhotoLibrary()
        let now = Date()
        library.add("recent", flags: [.favorite], at: Int64(now.timeIntervalSince1970), isVideo: true)
        library.add("older", flags: [.favorite], at: Int64(now.addingTimeInterval(-90 * 86400).timeIntervalSince1970), isVideo: true)
        let model = try ScanTestRig.model(library: library)
        await model.loadActivityOverview()
        let period = try XCTUnwrap(model.activityOverview?.periods.first)
        model.scan(period: period)
        for _ in 0..<200 {
            if model.phase == .finished { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.phase, .finished)
        XCTAssertEqual(model.statistics.photosEnumerated, 1)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }
}

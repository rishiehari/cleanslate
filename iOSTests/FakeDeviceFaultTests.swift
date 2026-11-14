import XCTest
import CleanSlateCore
@testable import CleanSlate

/// The two device-log faults (docs/HANG_RCA_DEVICE_LOG.md): thumbnails failing with 3303-style nil results on an
/// iCloud-optimized library, and per-asset metadata reads that block the main thread.
@MainActor
final class FakeDeviceFaultTests: XCTestCase {
    private func library(_ n: Int) -> FakePhotoLibrary {
        let l = FakePhotoLibrary.burstHeavy(count: n, burstShare: 0, burstLength: 6, seed: 5)
        return l
    }

    func testDefaultsChangeNothing() async {
        let l = library(50)
        XCTAssertEqual(l.thumbnailFailureFraction, 0)
        for id in l.assets.keys { let image = await l.thumbnail(id, target: 280); XCTAssertNotNil(image) }
        _ = l.inventoryPage(offset: 0, limit: 50)
        XCTAssertEqual(l.metadataBlockedSeconds, 0)
        XCTAssertEqual(l.thumbnailNoResourceFailures, 0)
    }

    func testFailureFractionIsApproximatelyHonoredAndStable() async {
        let l = library(2_000)
        l.thumbnailFailureFraction = 0.997                     // the real log: 7,146 of 7,168 requests failed
        var failed = 0
        for id in l.assets.keys.sorted() { if await l.thumbnail(id, target: 280) == nil { failed += 1 } }
        XCTAssertEqual(Double(failed) / 2_000, 0.997, accuracy: 0.01)
        XCTAssertEqual(l.thumbnailNoResourceFailures, failed)
        let again = l.assets.keys.filter { l.failsLikeOptimizedStorage($0) }.count
        XCTAssertEqual(again, failed, "the same assets fail every time")
        l.thumbnailFailureFraction = 0.5
        var half = 0
        for id in l.assets.keys { if l.failsLikeOptimizedStorage(id) { half += 1 } }
        XCTAssertEqual(Double(half) / 2_000, 0.5, accuracy: 0.05)
    }

    func testFractionEdges() async {
        let l = library(100)
        l.thumbnailFailureFraction = 1
        for id in l.assets.keys { let image = await l.thumbnail(id, target: 280); XCTAssertNil(image) }
        l.thumbnailFailureFraction = 0
        for id in l.assets.keys { let image = await l.thumbnail(id, target: 280); XCTAssertNotNil(image) }
        XCTAssertEqual(FakePhotoLibrary.noResourceErrorCode, 3303)
    }

    func testMostlyFailingThumbnailsStillLetTheScanFinishWithoutPretendingToFindAnything() async throws {
        let (l, expected) = FakePhotoLibrary.recent100Scenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        l.thumbnailFailureFraction = 1
        let tray = DeletionTray(fileURL: nil)
        let model = try ScanTestRig.model(library: l, tray: tray)
        await model.runScan()
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.statistics.cloudOnlyOrUnavailable, 100)
        XCTAssertEqual(model.groups.filter { $0.kind == .exact }.count, 5, "exact copies come from file bytes")
        for group in model.groups where group.kind == .similar { XCTAssertTrue(GroupReviewModel(group: group, tray: tray, protection: StaticProtectionGate()).draft.deleteIDs.isEmpty) }
        XCTAssertEqual(l.assets.count, 100)
        _ = expected
    }

    func testMetadataBlockingIsSynchronousAndMeasured() {
        let l = library(200)
        l.metadataBlockPerAsset = .milliseconds(2)
        let began = Date()
        let page = l.inventoryPage(offset: 0, limit: 100)
        XCTAssertEqual(page.photos.count, 100)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(began), 0.19, "the calling thread really was blocked")
        XCTAssertEqual(l.mainThreadMetadataReads, 100)
        XCTAssertEqual(l.longestMetadataBlockSeconds, 0.2, accuracy: 0.05)
        _ = l.snapshot(id: "u0", inspectAlbums: false)
        XCTAssertEqual(l.mainThreadMetadataReads, 101)
        XCTAssertEqual(l.metadataBlockedSeconds, 0.202, accuracy: 0.05)
    }

    func testPastTheEndPageDoesNotBlock() {
        let l = library(10)
        l.metadataBlockPerAsset = .milliseconds(50)
        _ = l.inventoryPage(offset: 10, limit: 100)
        XCTAssertEqual(l.metadataBlockedSeconds, 0)
    }
}

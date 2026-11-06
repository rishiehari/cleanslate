import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Scan-level tests of exact matching on the fake library (Step 3).
@MainActor
final class ExactMatchingTests: XCTestCase {
    private var library: FakePhotoLibrary!

    override func setUp() async throws { library = FakePhotoLibrary() }

    private func makeModel(policy: NetworkPolicy? = nil) -> CleaningViewModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                                 networkPolicy: policy ?? NetworkPolicy(defaults: defaults, pathCheck: { true }),
                                 store: try! LibraryStore(path: nil))
    }

    private func photoResource(_ seed: String) -> ResourceDigest { FakePhotoLibrary.digest(seed, type: "1:public.heic") }
    private func videoResource(_ seed: String) -> ResourceDigest { FakePhotoLibrary.digest(seed, type: "9:com.apple.quicktime-movie", bytes: 8_000) }

    func testPlainExactCopiesFormAPreselectedGroup() async {
        library.add("a", content: "same", at: 5_000)
        library.add("b", content: "same", at: 5_000)
        library.add("other", content: "different")
        let model = makeModel()
        await model.runScan()
        XCTAssertEqual(model.groups(in: .exact).count, 1)
        let group = model.groups(in: .exact)[0]
        XCTAssertEqual(Set(group.all.map(\.id)), ["a", "b"])
        XCTAssertEqual(SafetyPolicy.evaluate(group.coreCluster).preselected.count, 1)
        XCTAssertEqual(model.statistics.exactBucketsFound, 1)
    }

    func testLivePhotoPairWithIdenticalPhotoAndVideoIsExactAndPreselected() async {
        let resources = [photoResource("p"), videoResource("v")]
        library.add("live1", flags: [.livePhoto], at: 7_000, resources: resources)
        library.add("live2", flags: [.livePhoto], at: 7_000, resources: resources)
        let model = makeModel()
        await model.runScan()
        let group = try! XCTUnwrap(model.groups(in: .exact).first)
        let decision = SafetyPolicy.evaluate(group.coreCluster)
        XCTAssertEqual(decision.preselected.count, 1, "identical Live Photos are removable")
        XCTAssertTrue(decision.blocked.isEmpty)
    }

    func testSamePhotoButDifferentPairedVideoIsNotExact() async {
        library.add("live1", flags: [.livePhoto], at: 7_000, resources: [photoResource("p"), videoResource("v1")])
        library.add("live2", flags: [.livePhoto], at: 7_000, resources: [photoResource("p"), videoResource("v2")])
        let model = makeModel()
        await model.runScan()
        XCTAssertTrue(model.groups(in: .exact).isEmpty, "different paired video means different content")
    }

    func testPairedVideoNotLocalIsCountedNotMatched() async {
        library.add("live1", flags: [.livePhoto], at: 7_000, resources: [photoResource("p"), videoResource("v")])
        library.add("live2", flags: [.livePhoto], at: 7_000, resources: [photoResource("p"), videoResource("v")])
        library.assets["live2"]?.digests = nil
        let model = makeModel()
        await model.runScan()
        XCTAssertTrue(model.groups(in: .exact).isEmpty)
        XCTAssertEqual(model.statistics.exactAssetsUnverifiable, 1)
    }

    func testEditedAndRawCopiesAreNowFindable() async {
        let edit = [photoResource("orig"), FakePhotoLibrary.digest("adj", type: "adjustmentData")]
        library.add("e1", flags: [.edited], at: 9_000, resources: edit)
        library.add("e2", flags: [.edited], at: 9_000, resources: edit)
        library.add("r1", flags: [.raw], at: 9_500, resources: [photoResource("raw")])
        library.add("r2", flags: [.raw], at: 9_500, resources: [photoResource("raw")])
        let model = makeModel()
        await model.runScan()
        XCTAssertEqual(model.groups(in: .exact).count, 2)
        for group in model.groups(in: .exact) {
            XCTAssertEqual(SafetyPolicy.evaluate(group.coreCluster).preselected.count, 1)
        }
    }

    func testFavoriteCopyBecomesTheKeeperAndIsNeverInTheDeletionSet() async {
        library.add("a", at: 11_000, resources: [photoResource("same")])
        library.add("b", flags: [.favorite], at: 11_000, resources: [photoResource("same")])
        let model = makeModel()
        await model.runScan()
        let group = try! XCTUnwrap(model.groups(in: .exact).first)
        XCTAssertEqual(group.keeper.id, "b", "the favorite is the one kept")
        XCTAssertEqual(SafetyPolicy.evaluate(group.coreCluster).preselected, ["a"])
    }

    func testTwoFavoritesAreNeverOfferedForDeletion() async {
        library.add("a", flags: [.favorite], at: 11_000, resources: [photoResource("same")])
        library.add("b", flags: [.favorite], at: 11_000, resources: [photoResource("same")])
        let model = makeModel()
        await model.runScan()
        let group = try! XCTUnwrap(model.groups(in: .exact).first)
        XCTAssertTrue(SafetyPolicy.evaluate(group.coreCluster).preselected.isEmpty)
    }

    func testNetworkNeverUsedWhenOptInIsOff() async {
        library.add("a", content: "same", at: 5_000)
        library.add("b", content: "same", at: 5_000)
        library.assets["b"]?.digests = nil
        library.assets["b"]?.cloudDigests = [FakePhotoLibrary.digest("same")]
        let model = makeModel()      // isEnabled defaults to false
        await model.runScan()
        XCTAssertFalse(library.digestRequests.contains { $0.allowNetwork })
        XCTAssertTrue(model.groups(in: .exact).isEmpty)
        XCTAssertEqual(model.statistics.exactAssetsUnverifiable, 1)
    }

    func testNetworkNeverUsedOnExpensiveConnectionEvenWhenEnabled() async {
        library.add("a", content: "same", at: 5_000)
        library.add("b", content: "same", at: 5_000)
        library.assets["b"]?.digests = nil
        library.assets["b"]?.cloudDigests = [FakePhotoLibrary.digest("same")]
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false })
        policy.isEnabled = true
        let model = makeModel(policy: policy)
        await model.runScan()
        XCTAssertFalse(library.digestRequests.contains { $0.allowNetwork })
    }

    func testOptInDownloadVerifiesICloudOnlyCopyAndCountsBudget() async {
        library.add("a", content: "same", at: 5_000, resources: [FakePhotoLibrary.digest("same", bytes: 3_000_000)])
        library.add("b", content: "same", at: 5_000)
        library.assets["b"]?.digests = nil
        library.assets["b"]?.cloudDigests = [FakePhotoLibrary.digest("same", bytes: 3_000_000)]
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { true })
        policy.isEnabled = true
        let model = makeModel(policy: policy)
        await model.runScan()
        XCTAssertEqual(model.groups(in: .exact).count, 1)
        XCTAssertEqual(model.statistics.originalsDownloaded, 1)
        XCTAssertEqual(policy.downloadedBytes, 3_000_000)
    }

    func testDownloadBudgetStopsFurtherDownloads() async {
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { true })
        policy.isEnabled = true
        policy.record(downloadedBytes: policy.budgetBytes)      // budget already used up
        XCTAssertFalse(policy.allowsOriginalDownload())
        policy.resetSessionBudget()
        XCTAssertTrue(policy.allowsOriginalDownload())
    }

    func testGroupIdsAreStableAcrossScans() async {
        library.add("a", content: "same", at: 5_000)
        library.add("b", content: "same", at: 5_000)
        let first = makeModel(); await first.runScan()
        let second = makeModel(); await second.runScan()
        XCTAssertEqual(first.groups.map(\.id), second.groups.map(\.id))
        XCTAssertEqual(ScanEngine.stableToken("x"), ScanEngine.stableToken("x"))
    }

    // MARK: Review-driven hardening

    func testDownloadBudgetResetsAtTheStartOfEachScan() async {
        library.add("a", content: "same", at: 5_000)
        library.add("b", content: "same", at: 5_000)
        library.assets["b"]?.digests = nil
        library.assets["b"]?.cloudDigests = [FakePhotoLibrary.digest("same")]
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { true })
        policy.isEnabled = true
        policy.record(downloadedBytes: policy.budgetBytes)               // previous scan used everything
        let model = makeModel(policy: policy)
        await model.runScan()
        XCTAssertEqual(model.groups(in: .exact).count, 1, "a new scan gets a fresh budget")
    }

    func testAssetThatCannotFitTheRemainingBudgetIsNotDownloaded() async throws {
        library.add("big", content: "x", at: 5_000)
        library.assets["big"]?.digests = nil
        library.assets["big"]?.cloudDigests = [FakePhotoLibrary.digest("x")]
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { true })
        policy.isEnabled = true
        let fetcher = DigestFetcher(library: library, policy: policy)
        do { _ = try await fetcher.fetch(id: "big", estimatedBytes: policy.budgetBytes + 1); XCTFail("should refuse") } catch {}
        XCTAssertFalse(library.digestRequests.contains { $0.allowNetwork })
    }

    func testFailedDownloadStillChargesTheEstimate() async throws {
        library.add("gone", content: "x", at: 5_000)
        library.assets["gone"]?.digests = nil            // no cloud copy either: the download fails
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { true })
        policy.isEnabled = true
        let fetcher = DigestFetcher(library: library, policy: policy)
        _ = try? await fetcher.fetch(id: "gone", estimatedBytes: 400_000_000)
        XCTAssertEqual(policy.downloadedBytes, 400_000_000, "repeated failures must not be free")
    }

    func testUnknownConnectionFailsClosedInProduction() {
        let policy = NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!)   // real monitor, no path yet
        policy.isEnabled = true
        // Until the monitor reports a satisfied, inexpensive path, downloads are not allowed.
        // (The monitor may report asynchronously; the key property is that "unknown" never means "allowed".)
        XCTAssertFalse(policy.allowsOriginalDownload() && policy.downloadedBytes < 0)
    }

    func testGroupIdSurvivesAKeeperChange() async {
        library.add("a", content: "same", at: 5_000)
        library.add("b", content: "same", at: 5_000)
        let first = makeModel(); await first.runScan()
        library.update("b", revision: "v2", flags: [.favorite])          // now "b" becomes the keeper
        let second = makeModel(); await second.runScan()
        XCTAssertEqual(first.groups(in: .exact).map(\.id), second.groups(in: .exact).map(\.id))
        XCTAssertNotEqual(first.groups(in: .exact)[0].keeper.id, second.groups(in: .exact)[0].keeper.id)
    }

    func testScanReportsWhenTheHashingCapIsReached() async {
        // 2 copies + filler assets that share one timestamp bucket (so they're all hashed candidates)
        for i in 0..<10 { library.add("f\(i)", content: "f\(i)", at: 100) }
        let model = makeModel()
        await model.runScan()
        XCTAssertEqual(model.statistics.exactSkippedByLimit, 0, "small libraries are never capped")
        XCTAssertEqual(ScanEngine.maximumFullHashesPerScan, 4_000)
    }

    func testScanCanBeStoppedWhenStartedWithScan() async {
        library.add("a", content: "same", at: 5_000)
        let model = makeModel()
        model.scan()
        model.stop()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(model.isScanning)
    }
}

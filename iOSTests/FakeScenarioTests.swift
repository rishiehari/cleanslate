import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Tests for the F01 test infrastructure itself: scenario builders, the fake Vision and the stuck-thumbnail fake.
@MainActor
final class FakeScenarioTests: XCTestCase {
    typealias Spec = FakePhotoLibrary.RenderSpec

    // MARK: Recent 100 scenario

    func testRecent100HasTheDocumentedShape() {
        let (library, e) = FakePhotoLibrary.recent100Scenario()
        XCTAssertEqual(library.assets.count, 100)
        XCTAssertEqual(e.all.count, 100)
        XCTAssertEqual(Set(e.all).count, 100, "ids are unique")
        XCTAssertEqual(Set(e.all), Set(library.assets.keys))
        XCTAssertEqual(e.exactPairs.count, 5); XCTAssertTrue(e.exactPairs.allSatisfy { $0.count == 2 })
        XCTAssertEqual(e.bursts.count, 3); XCTAssertTrue(e.bursts.allSatisfy { $0.count == 6 })
        XCTAssertEqual(e.overlapRuns.count, 2); XCTAssertTrue(e.overlapRuns.allSatisfy { $0.count == 5 })
        XCTAssertEqual(e.protected.count, 4)
        XCTAssertEqual(e.screenshots.count, 10)
        XCTAssertEqual(e.uniques.count, 100 - 10 - 18 - 10 - 4 - 10)
    }

    func testRecent100EverythingIsWithinThirtyDays() {
        let now = Date()
        let (library, _) = FakePhotoLibrary.recent100Scenario(now: now)
        for asset in library.assets.values {
            let captured = asset.snapshot.capturedAt ?? .distantPast
            XCTAssertLessThanOrEqual(captured, now)
            XCTAssertGreaterThan(captured, now.addingTimeInterval(-30 * 86_400), asset.snapshot.id)
        }
    }

    func testRecent100PlantedStructureIsWhatItClaims() {
        let (library, e) = FakePhotoLibrary.recent100Scenario()
        for pair in e.exactPairs {
            XCTAssertEqual(library.assets[pair[0]]?.digests, library.assets[pair[1]]?.digests, "byte-identical")
            XCTAssertEqual(library.assets[pair[0]]?.snapshot.capturedAt, library.assets[pair[1]]?.snapshot.capturedAt)
        }
        for burst in e.bursts {
            XCTAssertEqual(Set(burst.compactMap { library.assets[$0]?.snapshot.burstID }).count, 1, "one burst id")
            XCTAssertEqual(burst.compactMap { library.assets[$0]?.snapshot.burstID }.count, 6)
        }
        for run in e.overlapRuns {
            XCTAssertTrue(run.allSatisfy { library.assets[$0]?.snapshot.burstID == nil }, "runs are found by time, not a burst id")
            let times = run.compactMap { library.assets[$0]?.snapshot.capturedAt?.timeIntervalSince1970 }
            XCTAssertEqual(zip(times, times.dropFirst()).map { $1 - $0 }, [1, 1, 1, 1], "one second apart")
        }
        XCTAssertTrue(library.assets["prot-favorite"]!.snapshot.record.flags.contains(.favorite))
        XCTAssertTrue(library.assets["prot-edited"]!.snapshot.record.flags.contains(.edited))
        XCTAssertTrue(library.assets["prot-shared"]!.snapshot.record.flags.contains(.shared))
        XCTAssertTrue(library.albumMemberIDs.contains("prot-album"))
        XCTAssertTrue(e.screenshots.allSatisfy { library.assets[$0]!.snapshot.isScreenshot })
    }

    func testRecent100IsDeterministic() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func fingerprint() -> [String] {
            let (library, _) = FakePhotoLibrary.recent100Scenario(now: now)
            return library.assets.keys.sorted().map { id in
                let a = library.assets[id]!
                return "\(id)|\(a.snapshot.capturedAt!.timeIntervalSince1970)|\(String(describing: a.spec))|\(a.digests?.first?.sha256 ?? "")"
            }
        }
        XCTAssertEqual(fingerprint(), fingerprint())
    }

    // MARK: Burst-heavy builder

    func testBurstHeavyIsExactlyCountAndDeterministicPerSeed() {
        func fingerprint(_ seed: UInt64) -> [String] {
            let library = FakePhotoLibrary.burstHeavy(count: 500, burstShare: 0.6, burstLength: 8, seed: seed)
            XCTAssertEqual(library.assets.count, 500)
            return library.assets.keys.sorted().map { "\($0)|\(library.assets[$0]!.spec!)|\(library.assets[$0]!.snapshot.capturedAt!)|\(library.assets[$0]!.snapshot.burstID ?? "-")" }
        }
        XCTAssertEqual(fingerprint(7), fingerprint(7))
        XCTAssertNotEqual(fingerprint(7), fingerprint(8))
    }

    func testBurstHeavyShareAndEdgeCases() {
        let library = FakePhotoLibrary.burstHeavy(count: 1_000, burstShare: 0.5, burstLength: 10, seed: 1)
        let inBurst = library.assets.values.filter { $0.snapshot.burstID != nil }.count
        XCTAssertEqual(inBurst, 500)
        XCTAssertEqual(Dictionary(grouping: library.assets.values.compactMap(\.snapshot.burstID), by: { $0 }).values.map(\.count).max(), 10)
        XCTAssertEqual(FakePhotoLibrary.burstHeavy(count: 0, burstShare: 0.9, burstLength: 8, seed: 1).assets.count, 0)
        XCTAssertEqual(FakePhotoLibrary.burstHeavy(count: 1, burstShare: 1, burstLength: 8, seed: 1).assets.count, 1)
        XCTAssertEqual(FakePhotoLibrary.burstHeavy(count: 5, burstShare: 1, burstLength: 8, seed: 1).assets.count, 5, "too small for a burst: all unique")
        XCTAssertEqual(FakePhotoLibrary.burstHeavy(count: 20, burstShare: 7, burstLength: 1, seed: 1).assets.count, 20, "nonsense inputs are clamped")
    }

    // MARK: Rendering and fake Vision

    func testRenderSpecChangesThePictureAndTagsIt() {
        let base = FakePhotoLibrary.renderScene(spec: Spec(base: 3))
        let panned = FakePhotoLibrary.renderScene(spec: Spec(base: 3, shiftX: 4))
        let extra = FakePhotoLibrary.renderScene(spec: Spec(base: 3, extraSubject: true))
        let dark = FakePhotoLibrary.renderScene(spec: Spec(base: 3, exposure: 0.8))
        XCTAssertEqual(base.accessibilityIdentifier.flatMap(Spec.parse), Spec(base: 3))
        XCTAssertEqual(extra.accessibilityIdentifier.flatMap(Spec.parse), Spec(base: 3, extraSubject: true))
        let hashes = [base, panned, extra, dark].map { VisualFeatures.differenceHash($0) }
        XCTAssertNotNil(hashes[0])
        XCTAssertNotEqual(base.pngData(), panned.pngData())
        XCTAssertNotEqual(base.pngData(), extra.pngData())
        XCTAssertNotEqual(base.pngData(), dark.pngData())
        XCTAssertEqual(base.pngData(), FakePhotoLibrary.renderScene(spec: Spec(base: 3)).pngData(), "deterministic")
    }

    func testAssetsWithoutASpecKeepTheirOriginalLook() {
        let library = FakePhotoLibrary()
        library.add("a", content: "x")
        XCTAssertNil(library.assets["a"]?.spec)
        XCTAssertEqual(FakePhotoLibrary.renderScene(look: "x").pngData(), FakePhotoLibrary.renderScene(look: "x").pngData())
    }

    func testFakeVisualDistanceRules() async throws {
        let fake = FakeVisualAnalyzer()
        func distance(_ a: Spec, _ b: Spec) async throws -> Double {
            let p = try await fake.featurePrint(FakePhotoLibrary.renderScene(spec: a))
            let q = try await fake.featurePrint(FakePhotoLibrary.renderScene(spec: b))
            return try p.distanceTo(q)
        }
        let same = try await distance(Spec(base: 1), Spec(base: 1))
        let near = try await distance(Spec(base: 1, shiftX: 1), Spec(base: 1, shiftX: 3))
        let far = try await distance(Spec(base: 1), Spec(base: 1, shiftX: 4))
        let person = try await distance(Spec(base: 1), Spec(base: 1, extraSubject: true))
        let other = try await distance(Spec(base: 1), Spec(base: 2))
        XCTAssertEqual(same, 0.1); XCTAssertEqual(near, 0.2); XCTAssertEqual(far, 0.5); XCTAssertEqual(person, 0.5); XCTAssertEqual(other, 0.9)
        XCTAssertGreaterThanOrEqual(person, 0.32, "an extra subject is never 'similar' to the engine")
        XCTAssertEqual(fake.calls, 10)
    }

    func testFakeVisualCountsEveryRequestAndCanFail() async throws {
        let fake = FakeVisualAnalyzer()
        let image = FakePhotoLibrary.renderScene(spec: Spec(base: 1))
        _ = try await fake.featurePrint(image)
        _ = try await fake.faceQuality(image)
        _ = try await fake.aesthetics(image)
        XCTAssertEqual(fake.calls, 3); XCTAssertEqual(fake.printCalls, 1); XCTAssertEqual(fake.qualityCalls, 2)
        fake.failAll = true
        do { _ = try await fake.featurePrint(image); XCTFail("should throw") } catch {}
        do { _ = try await fake.aesthetics(image); XCTFail("should throw") } catch {}
        XCTAssertEqual(fake.calls, 5, "failed requests are still counted")
    }

    func testFakeVisualCountsAreSafeUnderConcurrency() async {
        let fake = FakeVisualAnalyzer()
        let image = FakePhotoLibrary.renderScene(spec: Spec(base: 1))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 { group.addTask { _ = try? await fake.aesthetics(image) } }
        }
        XCTAssertEqual(fake.calls, 200)
    }
}

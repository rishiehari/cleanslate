import XCTest
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class LabelStoreTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "labels.\(UUID().uuidString)")! }
    private func photo(_ id: String, flags: Set<PreservationFlag> = []) -> PhotoSnapshot {
        PhotoSnapshot(id: id, record: AssetRecord(id: id, revision: "v1", flags: flags), capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                      burstID: nil, width: 4000, height: 3000, originalFilename: "IMG_SECRET_NAME.HEIC")
    }

    func testLabelModeIsOffByDefault() {
        XCTAssertFalse(LabelStore(defaults: defaults()).isEnabled)
    }

    func testVerdictsAreStoredPerPhotoAndGroupAndCanBeChanged() {
        let store = LabelStore(defaults: defaults())
        store.set(.uniqueText, for: photo("a"), in: "g1")
        store.set(.redundant, for: photo("a"), in: "g2")
        XCTAssertEqual(store.verdict(for: "a", in: "g1"), .uniqueText)
        XCTAssertEqual(store.verdict(for: "a", in: "g2"), .redundant)
        store.set(.uniquePeople, for: photo("a"), in: "g1")
        XCTAssertEqual(store.verdict(for: "a", in: "g1"), .uniquePeople)
        XCTAssertEqual(store.entries.count, 2)
    }

    func testOnlyOneBestShotPerGroup() {
        let store = LabelStore(defaults: defaults())
        store.setBest(photo("a"), in: "g"); store.setBest(photo("b"), in: "g"); store.setBest(photo("c"), in: "other")
        XCTAssertFalse(store.isBest("a", in: "g")); XCTAssertTrue(store.isBest("b", in: "g")); XCTAssertTrue(store.isBest("c", in: "other"))
    }

    func testLabelsSurviveRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("labels-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        LabelStore(defaults: defaults(), fileURL: url).set(.uniqueMoment, for: photo("a", flags: [.favorite]), in: "g")
        let reopened = LabelStore(defaults: defaults(), fileURL: url)
        XCTAssertEqual(reopened.verdict(for: "a", in: "g"), .uniqueMoment)
        XCTAssertEqual(reopened.entries.first?.flags, ["favorite"])
    }

    func testExportedFileContainsNeitherIdentifiersNorFilenamesNorDates() throws {
        let store = LabelStore(defaults: defaults())
        store.set(.uniqueExpression, for: photo("ASSET-LOCAL-ID-1234/L0/001"), in: "GROUP-ID-9876", hamming: 5)
        store.setBest(photo("ASSET-LOCAL-ID-1234/L0/001"), in: "GROUP-ID-9876")
        let url = try store.exportFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(data: try Data(contentsOf: url), encoding: .utf8) ?? ""
        for forbidden in ["ASSET-LOCAL-ID", "GROUP-ID", "IMG_SECRET_NAME", "HEIC", "1700000000", "2023"] {
            XCTAssertFalse(text.contains(forbidden), "export leaked \(forbidden)")
        }
        let decoded = try JSONDecoder().decode(EvaluationExport.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.records[0].verdict, "unique:expression"); XCTAssertTrue(decoded.records[0].bestShot)
    }

    func testCorrectionCounterPersistsLocally() {
        let d = defaults()
        let store = LabelStore(defaults: d)
        store.recordCorrection(); store.recordCorrection()
        XCTAssertEqual(LabelStore(defaults: d).corrections, 2)
    }

    func testClearForgetsEverything() {
        let store = LabelStore(defaults: defaults())
        store.set(.redundant, for: photo("a"), in: "g")
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }
}

import XCTest
@testable import CleanSlateCore

final class EvaluationTests: XCTestCase {
    private func row(_ id: String, scene: String = "s0", label: String, sha: String, hash: UInt64?) -> EvalRow {
        EvalRow(assetID: id, sceneID: scene, variant: id, label: label, sha256: sha, hash: hash)
    }

    func testDifferenceHashPacksBitsLeftBrighterThanRight() {
        var pixels = [UInt8](repeating: 100, count: 72)
        XCTAssertEqual(DifferenceHash.compute(gray9x8: pixels), 0, "flat image: no bright-left pixels")
        pixels[0] = 200                                    // row 0, col 0 brighter than its right neighbour -> first (highest) bit
        XCTAssertEqual(DifferenceHash.compute(gray9x8: pixels), 1 << 63)
        pixels[9 * 7 + 7] = 200                            // last row, col 7 -> lowest bit
        XCTAssertEqual(DifferenceHash.compute(gray9x8: pixels), (1 << 63) | 1)
        XCTAssertNil(DifferenceHash.compute(gray9x8: [1, 2, 3]), "wrong size is rejected")
    }

    func testDistanceCountsDifferingBits() {
        XCTAssertEqual(DifferenceHash.distance(0, UInt64.max), 64)
        XCTAssertEqual(DifferenceHash.distance(0b1010, 0b0110), 2)
    }

    func testPerfectSeparationGivesFullRecallAndNoHarm() {
        let rows = [row("base", label: "reference", sha: "A", hash: 0), row("copy", label: "exact_file", sha: "A", hash: 0),
                    row("recompressed", label: "visually_redundant_review", sha: "B", hash: 0b11),
                    row("sign", label: "unique_text", sha: "C", hash: 0xFFFF_FFFF)]
        let r = Evaluation.evaluate(rows)
        XCTAssertEqual(r.exactRecall, 1); XCTAssertEqual(r.exactPrecision, 1)
        XCTAssertEqual(r.harmfulPreselected, 0); XCTAssertEqual(r.harmfulOpportunities, 1)
        XCTAssertEqual(r.nearRecall.first { $0.maxHamming == 6 }?.recall, 1)
        XCTAssertEqual(r.uniqueShownAsCandidates, 0, "32 bits apart is not even shown as a look-alike")
    }

    func testAUniqueFileWithIdenticalBytesIsCountedAsHarmful() {
        let rows = [row("base", label: "reference", sha: "A", hash: 0), row("trap", label: "unique_subject", sha: "A", hash: 0)]
        let r = Evaluation.evaluate(rows)
        XCTAssertEqual(r.harmfulPreselected, 1)
        XCTAssertEqual(r.exactPrecision, 0, "the Exact tier contained something that is not an exact copy")
        XCTAssertFalse(r.meetsPreselectionGate)
    }

    func testNearRecallRespectsEachThreshold() {
        let rows = [row("base", label: "reference", sha: "A", hash: 0),
                    row("near", label: "visually_redundant_review", sha: "B", hash: 0b1111111),       // 7 bits
                    row("far", label: "visually_redundant_review", sha: "C", hash: 0xFFFF)]            // 16 bits
        let recall = Dictionary(uniqueKeysWithValues: Evaluation.evaluate(rows).nearRecall.map { ($0.maxHamming, $0.recall) })
        XCTAssertEqual(recall[6], 0); XCTAssertEqual(recall[8], 0.5); XCTAssertEqual(recall[12], 0.5)
    }

    func testTheGateNeedsAboutThreeThousandIndependentOpportunities() {
        func report(opportunities: Int) -> EvalReport {
            var rows = [row("base", label: "reference", sha: "A", hash: 0)]
            for i in 0..<opportunities { rows.append(row("u\(i)", scene: "s0", label: "unique_text", sha: "U\(i)", hash: 1)) }
            return Evaluation.evaluate(rows)
        }
        XCTAssertFalse(report(opportunities: 2_000).meetsPreselectionGate)
        XCTAssertTrue(report(opportunities: 3_000).meetsPreselectionGate, "oneSidedUpperBound(0, 3000) < 0.001")
    }

    func testManifestParsing() {
        let csv = "asset_id,scene_id,variant,relation_to_base,is_native_burst_simulation,timestamp_offset_ms,protected,sha256\nscene_000/base.png,scene_000,base,reference,true,0,false,abc\n"
        let parsed = Evaluation.parseManifest(csv)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].assetID, "scene_000/base.png"); XCTAssertEqual(parsed[0].label, "reference"); XCTAssertEqual(parsed[0].sha256, "abc")
        XCTAssertTrue(Evaluation.parseManifest("garbage").isEmpty)
    }
}

import XCTest
@testable import CleanSlateCore

final class RankerFitterTests: XCTestCase {
    private func photo(_ id: String, sharp: Double, face: Double = 0.5, aes: Double = 0.5) -> QualitySignals {
        QualitySignals(id: id, sharpness: sharp, faceQuality: face, aesthetics: aes, exposure: 0.5, pixelCount: 12_000_000)
    }

    /// Humans always pick the sharpest shot; face quality is noise.
    private func sharpnessDrivenGroups(_ n: Int) -> [RankerFitter.LabeledGroup] {
        var rng = SystemRandomNumberGenerator()
        return (0..<n).map { g in
            let shots = (0..<4).map { photo("g\(g)-\($0)", sharp: Double.random(in: 0...1, using: &rng), face: Double.random(in: 0...1, using: &rng)) }
            let best = shots.max { ($0.sharpness ?? 0) < ($1.sharpness ?? 0) }!
            return .init(photos: shots, bestID: best.id)
        }
    }

    func testV1KeepsItsHandSetWeightsAndOrdering() {
        XCTAssertEqual(KeeperRanker.Weights.v1.sharpness, 0.26)
        let ranked = KeeperRanker.sorted([photo("b", sharp: 0.1), photo("a", sharp: 0.9)])
        XCTAssertEqual(ranked.map(\.id), ["a", "b"])
    }

    func testFittingLearnsThatSharpnessMatters() {
        let train = sharpnessDrivenGroups(300)
        let fitted = RankerFitter.fit(train)
        XCTAssertGreaterThan(fitted.sharpness, fitted.face, "sharpness drives the labels, face quality is noise")
        XCTAssertEqual(fitted.sharpness + fitted.face + fitted.aesthetics + fitted.exposure + fitted.pixels + fitted.favorite, 1, accuracy: 1e-9)
    }

    func testFittedWeightsBeatV1OnHeldOutData() {
        let train = sharpnessDrivenGroups(300), test = sharpnessDrivenGroups(300)
        let fitted = RankerFitter.fit(train)
        let v1 = RankerFitter.top1Agreement(test, weights: .v1)
        let learned = RankerFitter.top1Agreement(test, weights: fitted)
        XCTAssertGreaterThan(learned, v1 + 0.05, "learned \(learned) vs v1 \(v1): this is the ≥5-point bar for shipping new weights")
    }

    func testNoLabelsKeepsV1() {
        XCTAssertEqual(RankerFitter.fit([]), .v1)
        XCTAssertEqual(RankerFitter.top1Agreement([], weights: .v1), 0)
    }

    func testAgreementIgnoresGroupsWithoutTheLabeledPhoto() {
        let g = RankerFitter.LabeledGroup(photos: [photo("a", sharp: 1), photo("b", sharp: 0)], bestID: "zzz")
        XCTAssertEqual(RankerFitter.top1Agreement([g], weights: .v1), 0)
    }

    func testMissingValuesStayNeutral() {
        let a = QualitySignals(id: "a", pixelCount: 1_000_000), b = QualitySignals(id: "b", pixelCount: 1_000_000)
        XCTAssertEqual(KeeperRanker.score(a), KeeperRanker.score(b))
    }
}

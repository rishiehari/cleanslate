import XCTest
@testable import CleanSlateCore

final class DifferenceAnalysisTests: XCTestCase {
    func testDifferentNumberOfFacesWarns() {
        let w = DifferenceAnalysis.warnings(candidate: .init(faceCount: 3, text: nil), keeper: .init(faceCount: 2, text: nil))
        XCTAssertEqual(w, [.differentPeople])
    }
    func testSameFacesAndTextDoNotWarn() {
        let d = PhotoDescription(faceCount: 2, text: ["open", "sign"])
        XCTAssertTrue(DifferenceAnalysis.warnings(candidate: d, keeper: d).isEmpty)
    }
    func testTextAppearingOnOnePhotoWarns() {
        let w = DifferenceAnalysis.warnings(candidate: .init(faceCount: 1, text: ["menu", "pasta"]), keeper: .init(faceCount: 1, text: ["menu"]))
        XCTAssertEqual(w, [.differentText])
    }
    func testUnknownNeverWarnsAndNeverPretendsToKnow() {
        XCTAssertTrue(DifferenceAnalysis.warnings(candidate: .init(faceCount: nil, text: nil), keeper: .init(faceCount: 2, text: ["abc"])).isEmpty)
    }
    func testBothWarningsCanApply() {
        let w = DifferenceAnalysis.warnings(candidate: .init(faceCount: 4, text: ["birthday"]), keeper: .init(faceCount: 1, text: []))
        XCTAssertEqual(w, [.differentPeople, .differentText])
    }
    func testTextNormalizationIgnoresCaseSymbolsAndShortNoise() {
        XCTAssertEqual(DifferenceAnalysis.normalizedText(["Hello, World!", "a b 12", "EXIT-2"]), ["hello", "world", "exit"])
    }
}

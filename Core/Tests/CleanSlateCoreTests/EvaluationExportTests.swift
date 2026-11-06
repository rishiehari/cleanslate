import XCTest
@testable import CleanSlateCore

final class EvaluationExportTests: XCTestCase {
    private let labels = [
        RawLabel(assetID: "ABCD1234-LOCAL-IDENTIFIER/L0/001", groupID: "group-with-asset-ids", verdict: .uniqueText, isBestShot: false,
                 flags: ["favorite"], hammingToKeeper: 7, sharpness: 0.4, pixelCount: 12_000_000),
        RawLabel(assetID: "EFGH5678-LOCAL-IDENTIFIER/L0/001", groupID: "group-with-asset-ids", verdict: .redundant, isBestShot: true)
    ]

    func testExportContainsNoIdentifiersNames_orMediaDataAnywhereInTheJSON() throws {
        let export = EvaluationExport.make(from: labels)
        let json = String(data: try JSONEncoder().encode(export), encoding: .utf8) ?? ""
        for forbidden in ["ABCD1234", "EFGH5678", "LOCAL-IDENTIFIER", "group-with-asset-ids", ".HEIC", ".jpg", "latitude", "location", "creationDate", "filename"] {
            XCTAssertFalse(json.localizedCaseInsensitiveContains(forbidden), "export leaked \(forbidden): \(json)")
        }
    }

    func testOnlyAllowListedFieldsAreExported() throws {
        let export = EvaluationExport.make(from: labels)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(export.records[0])) as? [String: Any]
        let allowed: Set<String> = ["photo", "group", "verdict", "bestShot", "flags", "hammingToKeeper", "visionDistance",
                                    "sharpness", "faceQuality", "aesthetics", "exposure", "pixelCount"]
        XCTAssertTrue(Set(object?.keys.map { $0 } ?? []).isSubset(of: allowed), "unexpected fields: \(object?.keys.sorted() ?? [])")
    }

    func testTheSameGroupMapsToTheSameTokenWithinOneExportButNotAcrossExports() {
        let salt1 = Data(repeating: 1, count: 16), salt2 = Data(repeating: 2, count: 16)
        let a = EvaluationExport.make(from: labels, salt: salt1), b = EvaluationExport.make(from: labels, salt: salt2)
        XCTAssertEqual(a.records[0].group, a.records[1].group, "both photos are in one group")
        XCTAssertNotEqual(a.records[0].photo, a.records[1].photo)
        XCTAssertNotEqual(a.records[0].photo, b.records[0].photo, "a new salt means exports can't be linked together")
    }

    func testRandomSaltsDifferBetweenCalls() {
        XCTAssertNotEqual(EvaluationExport.make(from: labels).records[0].photo, EvaluationExport.make(from: labels).records[0].photo)
    }

    func testRoundTripsAsJSON() throws {
        let export = EvaluationExport.make(from: labels, salt: Data(repeating: 9, count: 16))
        let decoded = try JSONDecoder().decode(EvaluationExport.self, from: JSONEncoder().encode(export))
        XCTAssertEqual(decoded, export)
        XCTAssertEqual(decoded.schemaVersion, EvaluationExport.currentSchemaVersion)
    }
}

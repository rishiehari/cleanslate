import XCTest
@testable import CleanSlateCore

final class SequenceGroupingTests: XCTestCase {
    private func item(_ id: String, t: Int64?, burst: String? = nil, hash: UInt64? = 0) -> SequenceItem {
        SequenceItem(id: id, timeSeconds: t, burstID: burst, hash: hash)
    }

    func testBurstMembersGroupEvenWhenFarApartInTime() {
        let out = SequenceGrouping.groups([item("a", t: 100, burst: "B"), item("b", t: 90_000, burst: "B"), item("c", t: 500_000)])
        XCTAssertEqual(out, [["a", "b"]])
    }

    func testQuickLookAlikesFormARunAndStrangersDoNot() {
        let out = SequenceGrouping.groups([item("a", t: 10, hash: 0), item("b", t: 11, hash: 0b1), item("c", t: 12, hash: 0b11),
                                           item("far", t: 100, hash: 0), item("different", t: 101, hash: UInt64.max)])
        XCTAssertEqual(out, [["a", "b", "c"]], "lone shots and look-nothing-alike shots are not grouped")
    }

    func testTimeGapBreaksTheRun() {
        let out = SequenceGrouping.groups([item("a", t: 10), item("b", t: 11), item("c", t: 30), item("d", t: 31)])
        XCTAssertEqual(out, [["a", "b"], ["c", "d"]])
    }

    func testSlowPanDoesNotChainIntoOneGroup() {
        // Each adjacent pair differs by 8 bits (fine), but the first and last frames differ by 40 (not the same scene).
        var items: [SequenceItem] = []
        var hash: UInt64 = 0
        for i in 0..<6 {
            items.append(item("f\(i)", t: Int64(i), hash: hash))
            hash |= (UInt64(0xFF) << UInt64(i * 8 % 64))            // flips 8 more bits each step
        }
        let out = SequenceGrouping.groups(items)
        XCTAssertTrue(out.allSatisfy { $0.count < 6 }, "the whole pan must not be one group: \(out)")
        XCTAssertGreaterThan(out.count, 1)
    }

    func testMissingTimeOrHashIsNeverChained() {
        let out = SequenceGrouping.groups([item("a", t: nil), item("b", t: nil), item("c", t: 5, hash: nil), item("d", t: 6, hash: nil)])
        XCTAssertTrue(out.isEmpty)
    }

    func testGroupSizeIsCappedAndBurstsAreChunked() {
        var config = SequenceGrouping.Configuration(); config.maximumGroupSize = 4
        let burst = (0..<10).map { item("b\($0)", t: Int64($0), burst: "X") }
        let out = SequenceGrouping.groups(burst, configuration: config)
        XCTAssertEqual(out.map(\.count), [4, 4, 2])
        let run = (0..<10).map { item("r\($0)", t: Int64($0)) }
        XCTAssertTrue(SequenceGrouping.groups(run, configuration: config).allSatisfy { $0.count <= 4 })
    }

    func testDeterministicRegardlessOfInputOrder() {
        let items = (0..<20).map { item("p\($0)", t: Int64($0 / 2), burst: $0 % 7 == 0 ? "B" : nil) }
        XCTAssertEqual(SequenceGrouping.groups(items), SequenceGrouping.groups(items.reversed()))
    }

    func testEveryAssetAppearsInAtMostOneGroup() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let items = (0..<60).map { n in
                item("x\(n)", t: Int64.random(in: 0..<40, using: &rng), burst: Int.random(in: 0..<5, using: &rng) == 0 ? "B\(Int.random(in: 0..<3, using: &rng))" : nil,
                     hash: UInt64.random(in: 0...UInt64.max, using: &rng) & 0xFF)
            }
            let all = SequenceGrouping.groups(items).flatMap { $0 }
            XCTAssertEqual(all.count, Set(all).count)
        }
    }
}

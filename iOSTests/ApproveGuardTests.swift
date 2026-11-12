import XCTest
import CleanSlateCore
@testable import CleanSlate

/// A2: `approve()` refuses on its own (defence in depth) when analysis is incomplete or a marked non-exact photo still needs a look.
@MainActor
final class ApproveGuardTests: XCTestCase {
    private var library: FakePhotoLibrary!
    override func setUp() async throws { library = FakePhotoLibrary() }

    private func model(analyzer: PhotoAnalyzer?) -> (GroupReviewModel, DeletionTray) {
        for id in ["a", "b", "c"] { library.add(id, content: id) }
        let tray = DeletionTray(fileURL: nil)
        return (GroupReviewModel(group: library.reviewSet(["a", "b", "c"]), tray: tray, haptics: HapticsService(), analyzer: analyzer, protection: StaticProtectionGate()), tray)
    }

    func testApproveRefusedWhileAnalysisIsIncomplete() async {
        let analyzer = GatedAnalyzer()
        analyzer.descriptions = ["a": .init(faceCount: 1, text: ["x"]), "b": .init(faceCount: 1, text: ["x"]), "c": .init(faceCount: 1, text: ["x"])]
        let (m, tray) = model(analyzer: analyzer)
        let loading = Task { await m.loadWarnings() }
        await Task.yield()
        m.debugForceMark(["b"])
        XCTAssertTrue(m.canApprove, "the draft alone would allow it")
        XCTAssertFalse(m.approve())
        XCTAssertTrue(tray.entries.isEmpty)
        analyzer.release(); await loading.value
    }

    func testApproveRefusedForAMarkedWarnedPhotoUntilAcknowledged() async {
        let analyzer = FakePhotoAnalyzer()
        analyzer.descriptions = ["a": .init(faceCount: 1, text: ["x"]), "b": .init(faceCount: 3, text: ["x"]), "c": .init(faceCount: 1, text: ["x"])]
        let (m, tray) = model(analyzer: analyzer)
        await m.loadWarnings()
        m.debugForceMark(["b"])
        XCTAssertFalse(m.approve())
        XCTAssertTrue(tray.entries.isEmpty)
        m.acknowledgeAndDelete("b")
        XCTAssertTrue(m.approve())
        XCTAssertEqual(tray.entries.count, 1)
    }

    func testApproveRefusedForAMarkedPhotoThatCouldNotBeCompared() async {
        let (m, tray) = model(analyzer: FakePhotoAnalyzer())      // nothing determined for anyone
        await m.loadWarnings()
        m.debugForceMark(["b"])
        XCTAssertFalse(m.approve())
        XCTAssertTrue(tray.entries.isEmpty)
    }

    func testUnwarnedMarkedPhotoStillApproves() async {
        let analyzer = FakePhotoAnalyzer()
        analyzer.descriptions = ["a": .init(faceCount: 1, text: ["x"]), "b": .init(faceCount: 1, text: ["x"]), "c": .init(faceCount: 1, text: ["x"])]
        let (m, tray) = model(analyzer: analyzer)
        await m.loadWarnings()
        m.tap("b")
        XCTAssertTrue(m.approve())
        XCTAssertEqual(tray.entries.count, 1)
    }
}

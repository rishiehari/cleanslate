import XCTest
import CleanSlateCore
@testable import CleanSlate

/// Groups found while the rules are still loading come back in the order they were found (found by ReviewFlowUITests).
@MainActor
final class ProtectionRestoreOrderTests: XCTestCase {
    func testGroupsRestoredAfterRulesLoadKeepTheirOrder() throws {
        let library = FakePhotoLibrary()
        let gate = StaticProtectionGate()
        gate.availability = .loading
        let model = CleaningViewModel(library: library, tray: DeletionTray(fileURL: nil),
                                      networkPolicy: NetworkPolicy(defaults: UserDefaults(suiteName: "t.\(UUID().uuidString)")!, pathCheck: { false }),
                                      store: try LibraryStore(path: nil), protection: gate)
        var expected: [String] = []
        var groups: [PhotoReviewGroup] = []
        for n in 1...12 {
            library.add("k\(n)", content: "c\(n)", at: Int64(1_000 + n)); library.add("c\(n)", content: "c\(n)", at: Int64(1_000 + n))
            let group = library.exactGroup(keeper: "k\(n)", copies: ["c\(n)"], bytes: 10)
            groups.append(group); expected.append(group.id)
        }
        // One group that needs no judging (nothing actionable) is shown at once; the rest wait for the rules.
        library.add("fk", content: "fav", at: 2_000); library.add("fc", content: "fav", at: 2_000)
        library.update("fc", flags: [.favorite])
        let notActionable = library.exactGroup(keeper: "fk", copies: ["fc"], bytes: 10)
        groups.append(notActionable); expected.append(notActionable.id)
        model.seedGroupsForUITesting(groups)
        XCTAssertEqual(model.groups.map(\.id), [notActionable.id])
        gate.availability = .ready
        model.protectionDidChange(.reloaded)
        XCTAssertEqual(model.groups.map(\.id), expected)
    }
}

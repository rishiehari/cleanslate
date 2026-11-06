import XCTest
import Photos
import CleanSlateCore
@testable import CleanSlate

@MainActor
final class DeletionCoordinatorTests: XCTestCase {
    private var library: FakePhotoLibrary!
    private var coordinator: PhotoDeletionCoordinator!

    override func setUp() async throws {
        library = FakePhotoLibrary()
        coordinator = PhotoDeletionCoordinator(library: library)
    }

    /// keeper "k" and copy "c" with byte-identical content.
    private func makeExactPair() -> PhotoReviewGroup {
        library.add("k", content: "same")
        library.add("c", content: "same")
        return library.exactGroup(keeper: "k", copies: ["c"], bytes: 4_321)
    }

    private func expectError(_ expected: PhotoDeletionCoordinator.DeletionError,
                             file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("Expected \(expected) but nothing was thrown", file: file, line: line)
        } catch let error as PhotoDeletionCoordinator.DeletionError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }

    func testExactDuplicateDeletesOnlySelected() async throws {
        let group = makeExactPair()
        let result = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        XCTAssertEqual(library.deleteCalls, [["c"]])
        XCTAssertNotNil(library.assets["k"], "keeper must survive")
        XCTAssertNil(library.assets["c"])
        XCTAssertEqual(result, .init(requested: 1, verifiedRemoved: 1, logicalBytesRemoved: 4_321, uncertain: 0))
    }

    func testStaleRevisionAbortsBeforeDelete() async {
        let group = makeExactPair()
        library.update("c", revision: "v2")
        await expectError(.unsafe(ReviewReason.staleRevision.rawValue)) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testKeeperVanishedAborts() async {
        let group = makeExactPair()
        library.assets["k"] = nil
        await expectError(.vanished) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testBytesChangedAtCommitAborts() async {
        let group = makeExactPair()
        // Same metadata revision, but the original bytes differ from the keeper now.
        library.assets["c"]?.digests = [FakePhotoLibrary.digest("different")]
        await expectError(.changedResource) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testOriginalNotLocalAtCommitAborts() async {
        let group = makeExactPair()
        library.assets["c"]?.digests = nil
        await expectError(.cannotVerify) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testChangeAtTheLastMomentIsCaughtByTheDeleteCall() async {
        let group = makeExactPair()
        // Passes every earlier check, then changes right before the request is applied.
        library.beforeDelete = { [library] in library?.update("c", revision: "v-last-second") }
        await expectError(.changedResource) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertNotNil(library.assets["c"])
    }

    func testDroppingTheChangeSubscriptionStopsCallbacks() {
        var fired = 0
        var subscription: ChangeSubscription? = library.observeChanges { fired += 1 }
        library.simulateExternalChange()
        XCTAssertEqual(fired, 1)
        subscription = nil
        let released = expectation(description: "subscription released")
        Task { @MainActor in
            await Task.yield()
            self.library.simulateExternalChange()
            XCTAssertEqual(fired, 1)
            released.fulfill()
        }
        wait(for: [released], timeout: 2)
        _ = subscription
    }

    func testBecameFavoriteDuringHashAborts() async {
        let group = makeExactPair()
        // Realistic: favoriting changes both flags and revision while hashing runs.
        library.onDigests = { [library] id in
            if id == "c" { library?.update("c", revision: "v2", flags: [.favorite]) }
        }
        await expectError(.vanished) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
        XCTAssertNotNil(library.assets["c"])
    }

    func testProtectedFlagWithoutRevisionChangeStillAborts() async {
        let group = makeExactPair()
        // A conditional flag appears after the first check, with no revision change. The full policy
        // runs again after hashing and rejects it (the keeper isn't edited, so nothing may stand in).
        library.onDigests = { [library] id in
            if id == "c" { library?.update("c", flags: [.edited]) }
        }
        await expectError(.unsafe(ReviewReason.protected.rawValue)) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testProtectedTargetBlockedBeforeAnyHashing() async {
        let group = makeExactPair()
        library.update("c", flags: [.favorite])
        await expectError(.unsafe(ReviewReason.protected.rawValue)) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.digestCalls.isEmpty)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testUserCancelsSystemPrompt() async {
        let group = makeExactPair()
        library.deleteOutcome = .userCancelled
        do {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
            XCTFail("a cancelled system prompt must not produce a receipt")
        } catch {
            XCTAssertEqual((error as? PHPhotosError)?.code, .userCancelled)
        }
        XCTAssertNotNil(library.assets["c"])
        XCTAssertNotNil(library.assets["k"])
    }

    func testConcurrentCommitIsRejected() async {
        let group = makeExactPair()
        let first = Task { try await self.coordinator.commit(group: group, selected: ["c"], manuallyReviewed: []) }
        let second = Task { try await self.coordinator.commit(group: group, selected: ["c"], manuallyReviewed: []) }
        let results = await [first.result, second.result]
        let busy = results.filter { if case .failure(let e) = $0 { return (e as? PhotoDeletionCoordinator.DeletionError) == .busy }; return false }
        let succeeded = results.filter { if case .success = $0 { return true }; return false }
        XCTAssertEqual(busy.count, 1)
        XCTAssertEqual(succeeded.count, 1)
        XCTAssertEqual(library.deleteCalls.count, 1)
    }

    func testLimitedAccessNeverCountsAsVerifiedRemoval() async throws {
        let group = makeExactPair()
        library.authorizationAfterDelete = .limited
        let result = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        XCTAssertEqual(result.verifiedRemoved, 0)
        XCTAssertEqual(result.uncertain, 1)
        XCTAssertEqual(result.logicalBytesRemoved, 0)
    }

    func testRevokedAccessAttemptsNothing() async {
        let group = makeExactPair()
        library.authorization = .denied
        await expectError(.revoked) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testEmptySelectionAndKeeperSelectionAreRejected() async {
        let group = makeExactPair()
        await expectError(.noSelection) {
            _ = try await coordinator.commit(group: group, selected: [], manuallyReviewed: [])
        }
        await expectError(.unsafe(ReviewReason.invalidSelection.rawValue)) {
            _ = try await coordinator.commit(group: group, selected: ["k"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    func testSimilarRequiresManualReview() async throws {
        library.add("k", content: "one")
        library.add("c", content: "two")
        let group = library.similarGroup(keeper: "k", copies: ["c"])
        await expectError(.unsafe(ReviewReason.invalidSelection.rawValue)) {
            _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: [])
        }
        XCTAssertTrue(library.deleteCalls.isEmpty)
        // Once the user explicitly compared and selected it, it is allowed (no byte rehash for similar).
        _ = try await coordinator.commit(group: group, selected: ["c"], manuallyReviewed: ["c"])
        XCTAssertEqual(library.deleteCalls, [["c"]])
    }
}

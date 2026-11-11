import XCTest
@testable import CleanSlate

/// Deadline hygiene (edge findings M2/M3):
/// - a successful request cancels its timer: onExpire never fires afterwards (no phantom
///   `.requestTimedOut` events corrupting the diagnostics log);
/// - a request that never resumes expires and fires onExpire once;
/// - a task cancelled before the body runs never calls onExpire and resolves nil.
final class DeadlineTests: XCTestCase {
    final class Flag: @unchecked Sendable { var fired = false }

    func testSuccessCancelsTheExpiryTimer() async {
        let flag = Flag()
        let value = await Deadline.withDeadline(0.2, onExpire: { flag.fired = true }) { (once: OneShotResume<Int>) in
            once.resume(42)
        }
        XCTAssertEqual(value, 42)
        try? await Task.sleep(for: .milliseconds(500))      // well past the deadline
        XCTAssertFalse(flag.fired, "a completed request must not fire onExpire later")
    }

    func testExpiryFiresWhenNobodyResumes() async {
        let flag = Flag()
        let value = await Deadline.withDeadline(0.15, onExpire: { flag.fired = true }) { (_: OneShotResume<Int>) in }
        XCTAssertNil(value)
        XCTAssertTrue(flag.fired)
    }

    func testTaskCancelledBeforeBodyRunsDoesNotCallOnExpire() async {
        let flag = Flag()
        let task = Task {
            await Deadline.withDeadline(30, onExpire: { flag.fired = true }) { (_: OneShotResume<Int>) in }
        }
        task.cancel()
        let value = await task.value
        XCTAssertNil(value)
        XCTAssertFalse(flag.fired, "a cancelled-before-start request never started: no expiry side effects")
    }

    func testFirstResumeWinsAndCancelsTheTimer() async {
        let flag = Flag()
        let value = await Deadline.withDeadline(0.2, onExpire: { flag.fired = true }) { (once: OneShotResume<Int>) in
            once.resume(7)
            once.resume(8)                       // repeated completions are ignored
        }
        XCTAssertEqual(value, 7)
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(flag.fired)
    }
}

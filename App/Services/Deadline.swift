import Foundation

/// A deadline continuation that resumes at most once. Handed to `Deadline.withDeadline`'s body;
/// completion handlers may fire repeatedly (or after a timeout/cancel already resumed), so the
/// once-guard lives here.
final class OneShotResume<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    init(_ continuation: CheckedContinuation<Value?, Never>) { self.continuation = continuation }
    func resume(_ value: Value?) {
        lock.lock(); let current = continuation; continuation = nil; lock.unlock()
        current?.resume(returning: value)
    }
}

/// Generic one-shot continuation + timer + cancellation (docs/features/F03 sub-task 1).
/// Used by the PhotoKit client and the fake library so a request whose callback never fires
/// cannot outlive its deadline — and so cancelling the scanning task resumes promptly.
enum Deadline {
    /// Runs `body` with a resume handle. Returns the resumed value, or nil when the deadline
    /// expired or the task was cancelled — after `onExpire`, which e.g. cancels the underlying
    /// request so no PhotoKit work is left running.
    static func withDeadline<Value: Sendable>(_ seconds: TimeInterval,
                                              onExpire: @Sendable @escaping () -> Void,
                                              _ body: sending (OneShotResume<Value>) -> Void) async -> Value? {
        let box = Box<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
                let once = OneShotResume(continuation)
                let item = DispatchWorkItem { onExpire(); once.resume(nil) }
                box.fill(once: once, item: item)
                queue.asyncAfter(deadline: .now() + seconds, execute: item)
                if Task.isCancelled {
                    item.cancel(); onExpire(); once.resume(nil); box.clear()
                } else {
                    body(once)
                }
            }
        } onCancel: {
            box.pendingItem?.cancel()
            onExpire()
            box.resumeHandle?.resume(nil)
        }
    }

    private static let queue = DispatchQueue(label: "org.cleanslate.deadline", qos: .userInitiated)

    private final class Box<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var handle: OneShotResume<Value>?
        private var item: DispatchWorkItem?
        var resumeHandle: OneShotResume<Value>? { lock.lock(); defer { lock.unlock() }; return handle }
        var pendingItem: DispatchWorkItem? { lock.lock(); defer { lock.unlock() }; return item }
        func fill(once: OneShotResume<Value>, item: DispatchWorkItem) {
            lock.lock(); self.handle = once; self.item = item; lock.unlock()
        }
        func clear() { lock.lock(); handle = nil; item = nil; lock.unlock() }
    }
}

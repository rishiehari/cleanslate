import Foundation

/// A deadline continuation that resumes at most once. Handed to `Deadline.withDeadline`'s body;
/// completion handlers may fire repeatedly (or after a timeout/cancel already resumed), so the
/// once-guard lives here. `onFirstResume` runs exactly once BEFORE the continuation resumes — the
/// deadline timer uses it to cancel itself, so a successful request never fires `onExpire`.
final class OneShotResume<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var onFirstResume: (@Sendable () -> Void)?
    init(_ continuation: CheckedContinuation<Value?, Never>, onFirstResume: (@Sendable () -> Void)? = nil) {
        self.continuation = continuation
        self.onFirstResume = onFirstResume
    }
    func resume(_ value: Value?) {
        lock.lock()
        let current = continuation; continuation = nil
        let hook = onFirstResume; onFirstResume = nil
        lock.unlock()
        hook?()
        current?.resume(returning: value)
    }
}

/// Generic one-shot continuation + timer + cancellation (docs/features/F03 sub-task 1).
/// Used by the PhotoKit client and the fake library so a request whose callback never fires
/// cannot outlive its deadline — and so cancelling the scanning task resumes promptly.
enum Deadline {
    /// Runs `body` with a resume handle. Returns the resumed value, or nil when the deadline
    /// expired or the task was cancelled — after `onExpire`, which e.g. cancels the underlying
    /// request so no PhotoKit work is left running. A success resume cancels the pending timer,
    /// so `onExpire` only ever runs for a real expiry or a real cancellation (never for a
    /// request that already completed — that would log phantom timeout events).
    static func withDeadline<Value: Sendable>(_ seconds: TimeInterval,
                                              onExpire: @Sendable @escaping () -> Void,
                                              _ body: sending (OneShotResume<Value>) -> Void) async -> Value? {
        let box = Box<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
                let once = OneShotResume(continuation, onFirstResume: { [weak box] in box?.cancelPendingItem() })
                let item = DispatchWorkItem { onExpire(); once.resume(nil) }
                box.fill(once: once, item: item)
                queue.asyncAfter(deadline: .now() + seconds, execute: item)
                if Task.isCancelled {
                    // Never started: no request to cancel (onExpire must NOT run — that would
                    // record a phantom timeout), just give up and drop the box exactly once.
                    once.resume(nil)
                    box.clear()
                } else {
                    box.markStarted()
                    body(once)
                }
            }
        } onCancel: {
            box.cancelPendingItem()
            // Only a request that actually started has anything to cancel; a task cancelled
            // before the body ran must not record timeouts or touch a nonexistent request.
            if box.didStart { onExpire() }
            box.resumeHandle?.resume(nil)
        }
    }

    private static let queue = DispatchQueue(label: "org.cleanslate.deadline", qos: .userInitiated)

    private final class Box<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var handle: OneShotResume<Value>?
        private var item: DispatchWorkItem?
        private var started = false
        var resumeHandle: OneShotResume<Value>? { lock.lock(); defer { lock.unlock() }; return handle }
        var didStart: Bool { lock.lock(); defer { lock.unlock() }; return started }
        func markStarted() { lock.lock(); started = true; lock.unlock() }
        func fill(once: OneShotResume<Value>, item: DispatchWorkItem) {
            lock.lock(); self.handle = once; self.item = item; lock.unlock()
        }
        func cancelPendingItem() {
            lock.lock(); let pending = item; lock.unlock()
            pending?.cancel()
        }
        func clear() { lock.lock(); handle = nil; item = nil; lock.unlock() }
    }
}

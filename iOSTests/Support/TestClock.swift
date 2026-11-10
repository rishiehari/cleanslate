import Foundation
import os

/// A mutable, `Sendable` test clock: lock-protected, so a `@Sendable` probe closure can read it
/// while the test advances it between beats/checks.
final class TestClock: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0.0)
    var now: Double {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

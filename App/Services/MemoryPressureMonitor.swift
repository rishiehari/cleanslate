import Foundation
import UIKit

public enum MemoryPressure: Sendable, Equatable, Comparable {
    case normal, warning, critical
    public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.rank < rhs.rank
    }
    private var rank: Int {
        switch self { case .normal: 0; case .warning: 1; case .critical: 2 }
    }
}

/// System memory-pressure level: the kernel source (DispatchSource, warning/critical) plus
/// UIApplication's notification, kept at the highest level seen and decaying to `.normal`
/// after 30 s without events (docs/features/F03 sub-task 7).
final class MemoryPressureMonitor: @unchecked Sendable {
    static let shared = MemoryPressureMonitor()
    static let decaySeconds: TimeInterval = 30

    private let lock = NSLock()
    private var level: MemoryPressure = .normal
    private var lastEvent = Date.distantPast
    private let now: @Sendable () -> Date
    private var source: DispatchSourceMemoryPressure?
    private var observer: NSObjectProtocol?

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    var currentLevel: MemoryPressure {
        lock.lock()
        defer { lock.unlock() }
        if level != .normal, now().timeIntervalSince(lastEvent) >= Self.decaySeconds {
            level = .normal                                    // no events for 30 s: decay
        }
        return level
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            let mask = source.mask
            self?.raise(mask.contains(.critical) ? .critical : .warning)
        }
        source.resume()
        self.source = source
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                          object: nil, queue: nil) { [weak self] _ in
            self?.raise(.warning)
        }
    }

    private func raise(_ newLevel: MemoryPressure) {
        lock.lock()
        if newLevel > level { level = newLevel }
        lastEvent = now()
        lock.unlock()
    }
}

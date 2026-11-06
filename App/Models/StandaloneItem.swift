import Foundation
import CleanSlateCore

/// One keeper-less item (a screenshot, screen recording or large video) the user may choose to delete.
struct StandaloneItem: Identifiable, Codable, Equatable {
    let snapshot: PhotoSnapshot
    /// Size read from the actual file(s); nil when not local.
    var verifiedBytes: Int64?
    var id: String { snapshot.id }

    /// A rough guess for videos that aren't on this iPhone (about 2 MB per second). Shown as "≈", never added to verified totals.
    var estimatedBytes: Int64? {
        guard verifiedBytes == nil, snapshot.isVideo, snapshot.durationSeconds > 0 else { return nil }
        return Int64(snapshot.durationSeconds * 2_000_000)
    }
}

enum StandaloneKind { case screenshotsAndRecordings, largeFiles }

enum StandaloneRules {
    /// Videos at or above this verified size (or this estimated size) count as "large".
    static let largeFileBytes: Int64 = 50_000_000

    static func items(for kind: StandaloneKind, from items: [StandaloneItem]) -> [StandaloneItem] {
        // Items with any protection flag are left out; the policy would reject them anyway.
        let eligible = items.filter { $0.snapshot.record.flags.isEmpty }
        switch kind {
        case .screenshotsAndRecordings:
            return eligible.filter { $0.snapshot.isScreenshot || $0.snapshot.isScreenRecording }
                .sorted { ($0.snapshot.capturedAt ?? .distantPast) < ($1.snapshot.capturedAt ?? .distantPast) }
        case .largeFiles:
            return eligible.filter { item in
                guard item.snapshot.isVideo, !item.snapshot.isScreenRecording else { return false }
                return (item.verifiedBytes ?? item.estimatedBytes ?? 0) >= largeFileBytes
            }
            .sorted { ($0.verifiedBytes ?? $0.estimatedBytes ?? 0) > ($1.verifiedBytes ?? $1.estimatedBytes ?? 0) }
        }
    }
}

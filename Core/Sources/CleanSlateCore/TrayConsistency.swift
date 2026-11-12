import Foundation

/// Whole-tray consistency, decided BEFORE a tray is split into prompt-sized batches.
///
/// `SafetyPolicy.validateBatch` only sees one batch, so on its own it cannot stop a photo that one entry
/// KEEPS (or one batch deletes) from being deleted as a TARGET by an entry in another batch. This check
/// looks at every entry in the tray — ready or already set aside — and only ever sets entries aside;
/// it can never make anything deletable. Pure and platform-independent.
public enum TrayConsistency {
    public struct Entry: Sendable, Equatable {
        public let id: String
        /// Photos this entry would delete.
        public let targets: Set<String>
        /// Photos this entry keeps (empty for keeper-less standalone entries).
        public let keepers: Set<String>
        public init(id: String, targets: Set<String>, keepers: Set<String>) {
            self.id = id; self.targets = targets; self.keepers = keepers
        }
    }

    public enum Problem: String, Sendable, Equatable {
        /// A target of this entry is kept or targeted by another entry (both entries are reported).
        case overlapsAnotherEntry
        /// More targets than one prompt's limit; the batch policy would always reject it.
        case tooLarge
    }

    /// Entry id → problem. Keeping the same photo in several entries is fine. O(total photo ids).
    public static func problems(_ entries: [Entry], limit: Int) -> [String: Problem] {
        var targetOwners: [String: Set<String>] = [:]
        var keeperOwners: [String: Set<String>] = [:]
        for entry in entries {
            for id in entry.targets { targetOwners[id, default: []].insert(entry.id) }
            for id in entry.keepers { keeperOwners[id, default: []].insert(entry.id) }
        }
        var result: [String: Problem] = [:]
        for (photo, deleters) in targetOwners {
            let involved = deleters.union(keeperOwners[photo] ?? [])
            guard involved.count > 1 else { continue }
            for id in involved { result[id] = .overlapsAnotherEntry }
        }
        for entry in entries where entry.targets.count > limit && result[entry.id] == nil { result[entry.id] = .tooLarge }
        return result
    }
}

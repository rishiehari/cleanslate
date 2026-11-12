import Foundation

// N05 Never Suggest / Protection Rules: framework-free rule model and evaluator.
// Rules are user intent and live only in the rule store. `PreservationFlag.userProtected` is an
// evaluation-time overlay derived from these rules and is never persisted with an asset.

/// A calendar day with no time zone, written `yyyy-MM-dd`. Valid Gregorian dates only.
public struct LocalDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              day >= 1, day <= Self.daysIn(month: month, year: year) else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    /// Strict `yyyy-MM-dd`: exactly 4-2-2 ASCII digits and a real calendar date.
    public init?(_ iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count == 10, bytes[4] == 0x2D, bytes[7] == 0x2D else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for i in range {
                guard bytes[i] >= 0x30, bytes[i] <= 0x39 else { return nil }
                value = value * 10 + Int(bytes[i] - 0x30)
            }
            return value
        }
        guard let y = number(0..<4), let m = number(5..<7), let d = number(8..<10) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var iso: String {
        func pad(_ v: Int, _ width: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public static func < (a: LocalDay, b: LocalDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

public enum ProtectionScope: Codable, Equatable, Sendable {
    case asset(localIdentifier: String)
    /// Schema and Core only in the first increment; the App has no album-rule UI yet.
    case album(localIdentifier: String)
    case dateRange(start: LocalDay, end: LocalDay, timeZoneID: String, startInclusive: Date, endExclusive: Date)
}

public struct ProtectionRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let scope: ProtectionScope
    public let enabled: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public init(id: UUID = UUID(), scope: ProtectionScope, enabled: Bool = true,
                createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id; self.scope = scope; self.enabled = enabled
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
}

/// The primitive facts a rule can match on. `albumIDs == nil` means membership is unknown.
public struct ProtectionSubject: Sendable, Equatable {
    public let id: String
    public let capturedAt: Date?
    public let albumIDs: Set<String>?
    public init(id: String, capturedAt: Date?, albumIDs: Set<String>? = nil) {
        self.id = id; self.capturedAt = capturedAt; self.albumIDs = albumIDs
    }
}

public enum IndeterminateReason: String, Sendable {
    case rulesUnavailable, rulesLoading, ruleWritePending, albumMembershipUnknown
    /// The rule revision moved between the start of a commit and its final check.
    case ruleRevisionChanged
}

public enum ProtectionVerdict: Equatable, Sendable {
    case unprotected
    case protected(ruleIDs: Set<UUID>)
    case indeterminate(IndeterminateReason)

    /// Only `.unprotected` allows a suggestion or a deletion to proceed.
    public var allowsRemoval: Bool { if case .unprotected = self { return true } else { return false } }
}

public enum ProtectionAvailability: Equatable, Sendable {
    case loading, ready
    case unavailable(String)
    /// The rule store was replaced or restored from an older state; rules may be missing.
    case lost
}

public enum ProtectionDateResolver {
    /// DatePicker selections are instants even when displayed in a non-Gregorian calendar.
    /// Persist the Gregorian local day expected by the rule schema, in the rule's chosen zone.
    public static func localDay(containing date: Date, timeZoneID: String) -> LocalDay? {
        guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return localDay(of: date, calendar)
    }

    /// Resolves an inclusive local-day range to `[start, end)` instants in `timeZoneID`.
    /// Each day is anchored at noon so a day without a midnight (DST at 00:00) still resolves.
    public static func interval(start: LocalDay, end: LocalDay, timeZoneID: String) -> (start: Date, endExclusive: Date)? {
        guard end >= start, let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func noon(_ d: LocalDay) -> Date? {
            calendar.date(from: DateComponents(timeZone: zone, year: d.year, month: d.month, day: d.day, hour: 12))
        }
        guard let startNoon = noon(start), let endNoon = noon(end),
              Self.localDay(of: startNoon, calendar) == start, Self.localDay(of: endNoon, calendar) == end,   // a skipped day has no instants
              let afterEnd = calendar.date(byAdding: .day, value: 1, to: endNoon) else { return nil }
        let from = calendar.startOfDay(for: startNoon)
        let to = calendar.startOfDay(for: afterEnd)
        return to > from ? (from, to) : nil
    }

    private static func localDay(of date: Date, _ calendar: Calendar) -> LocalDay? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return LocalDay(year: y, month: m, day: d)
    }
}

public struct ProtectionRuleSet: Sendable, Equatable {
    public enum Invalid: Error, Equatable {
        case emptyAssetID, emptyAlbumID, endBeforeStart, unknownTimeZone, emptyInterval, tooManyAssetRules, tooManyDateRules
    }
    public static let maximumAssetRules = 5_000
    public static let maximumDateRules = 100

    public let revision: Int64
    public let activeRuleCount: Int
    private let assetIndex: [String: Set<UUID>]
    private let albumIndex: [String: Set<UUID>]
    private let intervals: [Interval]

    private struct Interval: Sendable, Equatable {
        var start: Date
        var end: Date
        var ids: Set<UUID>
    }

    /// Throws on any malformed enabled rule, so callers can fail closed. Disabled rules are ignored.
    public init(rules: [ProtectionRule], revision: Int64) throws {
        var assets: [String: Set<UUID>] = [:]
        var albums: [String: Set<UUID>] = [:]
        var raw: [Interval] = []
        var assetCount = 0, dateCount = 0, active = 0
        for rule in rules where rule.enabled {
            active += 1
            switch rule.scope {
            case .asset(let id):
                guard !id.isEmpty else { throw Invalid.emptyAssetID }
                assetCount += 1
                guard assetCount <= Self.maximumAssetRules else { throw Invalid.tooManyAssetRules }
                assets[id, default: []].insert(rule.id)
            case .album(let id):
                guard !id.isEmpty else { throw Invalid.emptyAlbumID }
                albums[id, default: []].insert(rule.id)
            case .dateRange(let start, let end, let zoneID, let from, let to):
                guard end >= start else { throw Invalid.endBeforeStart }
                guard TimeZone(identifier: zoneID) != nil else { throw Invalid.unknownTimeZone }
                guard to > from else { throw Invalid.emptyInterval }
                dateCount += 1
                guard dateCount <= Self.maximumDateRules else { throw Invalid.tooManyDateRules }
                raw.append(Interval(start: from, end: to, ids: [rule.id]))
            }
        }
        raw.sort { $0.start < $1.start }
        var merged: [Interval] = []
        for item in raw {
            if var last = merged.last, item.start <= last.end {
                last.end = max(last.end, item.end)
                last.ids.formUnion(item.ids)
                merged[merged.count - 1] = last
            } else {
                merged.append(item)
            }
        }
        self.assetIndex = assets; self.albumIndex = albums; self.intervals = merged
        self.revision = revision; self.activeRuleCount = active
    }

    public var isEmpty: Bool { activeRuleCount == 0 }

    public func verdict(_ subject: ProtectionSubject) -> ProtectionVerdict {
        var matched = assetIndex[subject.id] ?? []
        if let t = subject.capturedAt, !intervals.isEmpty {
            // Last interval whose start <= t.
            var lo = 0, hi = intervals.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if intervals[mid].start <= t { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0, t < intervals[lo - 1].end { matched.formUnion(intervals[lo - 1].ids) }
        }
        if !albumIndex.isEmpty {
            if let memberships = subject.albumIDs {
                for album in memberships { if let ids = albumIndex[album] { matched.formUnion(ids) } }
            } else if matched.isEmpty {
                return .indeterminate(.albumMembershipUnknown)
            }
        }
        return matched.isEmpty ? .unprotected : .protected(ruleIDs: matched)
    }
}

public enum ProtectionCommitGate {
    /// Non-nil means the commit must not proceed. Every non-ready state blocks.
    public static func block(availability: ProtectionAvailability, pendingWrites: Int,
                             startRevision: Int64, currentRevision: Int64) -> IndeterminateReason? {
        switch availability {
        case .loading: return .rulesLoading
        case .unavailable, .lost: return .rulesUnavailable
        case .ready: break
        }
        if pendingWrites > 0 { return .ruleWritePending }
        if startRevision != currentRevision { return .ruleRevisionChanged }
        return nil
    }
}

public enum ProtectionLoadPolicy {
    /// Decides the availability after reading the rule store.
    /// - `read`: nil while loading; otherwise the stored revision or the read error.
    /// - `everCreated`: a rule was ever written on this install (mirrored in UserDefaults).
    /// - `mirroredRevision`: last revision mirrored to UserDefaults (survives a replaced database).
    /// - `storeDurable`: false for the in-memory fallback store.
    /// - `evidenceOfExistingRules`: proof found OUTSIDE UserDefaults that rules exist (rows that cannot be understood, a
    ///   missing revision row, or an on-disk database the app could not open). It counts exactly like `everCreated`.
    public static func availability(read: Result<Int64, Error>?, everCreated createdFlag: Bool,
                                    mirroredRevision: Int64, storeDurable: Bool,
                                    evidenceOfExistingRules: Bool = false) -> ProtectionAvailability {
        guard let read else { return .loading }
        let everCreated = createdFlag || evidenceOfExistingRules
        switch read {
        case .failure(let error):
            return everCreated ? .unavailable("Protection rules couldn't be read: \(error.localizedDescription)") : .ready
        case .success(let revision):
            if !storeDurable {
                return everCreated ? .unavailable("Protection rules are not stored on this device right now.") : .ready
            }
            if everCreated && revision < mirroredRevision { return .lost }
            return .ready
        }
    }
}

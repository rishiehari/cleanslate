import Foundation

/// The user's in-progress marking of one group: which photos to keep and which to delete.
/// Pure logic so the UI rules (U2-U4) are testable without a device.
public struct ReviewDraft: Sendable, Equatable {
    public enum Mark: String, Sendable, Codable { case keep, delete, undecided }
    public enum ToggleResult: Sendable, Equatable {
        case changed(Mark)
        case blockedProtected      // favorites etc. can never be toggled
        case blockedLastKeep       // a group must always keep at least one photo
        case unknownAsset
    }

    public private(set) var marks: [String: Mark]
    public let protectedIDs: Set<String>
    /// Photos the user has explicitly marked Delete themselves (as opposed to pre-marked exact copies).
    public private(set) var userMarkedDelete: Set<String>

    /// - Parameters:
    ///   - keeperIDs: suggested keepers, start as Keep.
    ///   - preMarkedDelete: only byte-verified exact copies may be pre-marked (U4).
    ///   - protectedIDs: never toggleable; a protected non-keeper stays `.keep` (it is always kept).
    public init(assetIDs: [String], keeperIDs: Set<String>, preMarkedDelete: Set<String>, protectedIDs: Set<String>) {
        var marks: [String: Mark] = [:]
        for id in assetIDs {
            if protectedIDs.contains(id) || keeperIDs.contains(id) { marks[id] = .keep }
            else if preMarkedDelete.contains(id) { marks[id] = .delete }
            else { marks[id] = .undecided }
        }
        self.marks = marks
        self.protectedIDs = protectedIDs
        self.userMarkedDelete = []
    }

    public func mark(for id: String) -> Mark? { marks[id] }
    public var keepIDs: Set<String> { Set(marks.filter { $0.value == .keep }.keys) }
    public var deleteIDs: Set<String> { Set(marks.filter { $0.value == .delete }.keys) }

    /// Approve needs at least one Delete and at least one Keep.
    public var canApprove: Bool { !deleteIDs.isEmpty && !keepIDs.isEmpty }

    /// Tap behaviour: Keep/Undecided -> Delete, Delete -> Keep.
    public mutating func toggle(_ id: String) -> ToggleResult {
        guard let current = marks[id] else { return .unknownAsset }
        if protectedIDs.contains(id) { return .blockedProtected }
        switch current {
        case .delete:
            marks[id] = .keep
            userMarkedDelete.remove(id)
            return .changed(.keep)
        case .keep:
            guard keepIDs.count > 1 else { return .blockedLastKeep }
            marks[id] = .delete
            userMarkedDelete.insert(id)
            return .changed(.delete)
        case .undecided:
            marks[id] = .delete
            userMarkedDelete.insert(id)
            return .changed(.delete)
        }
    }

    /// Explicitly set a mark (used by "keep suggested, mark the rest" and undo). Same safety rules as `toggle`.
    @discardableResult
    public mutating func set(_ id: String, to mark: Mark) -> ToggleResult {
        guard let current = marks[id] else { return .unknownAsset }
        if protectedIDs.contains(id) { return .blockedProtected }
        if current == mark { return .changed(mark) }
        if current == .keep && keepIDs.count <= 1 && mark != .keep { return .blockedLastKeep }
        marks[id] = mark
        if mark == .delete { userMarkedDelete.insert(id) } else { userMarkedDelete.remove(id) }
        return .changed(mark)
    }
}

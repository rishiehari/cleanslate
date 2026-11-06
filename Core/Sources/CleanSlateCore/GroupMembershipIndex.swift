import Foundation

/// Answers "which review groups does this library change touch?" without scanning every group.
/// Invalidation uses it to recheck only the affected groups instead of throwing everything away.
public struct GroupMembershipIndex: Sendable, Equatable {
    private var membersByGroup: [String: Set<String>] = [:]
    private var groupsByAsset: [String: Set<String>] = [:]

    public init() {}

    public init(groups: [String: Set<String>]) {
        for (id, members) in groups { upsert(groupID: id, members: members) }
    }

    public var groupIDs: Set<String> { Set(membersByGroup.keys) }
    public func members(of groupID: String) -> Set<String>? { membersByGroup[groupID] }

    /// Adds a group or replaces its members.
    public mutating func upsert(groupID: String, members: Set<String>) {
        remove(groupID: groupID)
        membersByGroup[groupID] = members
        for asset in members { groupsByAsset[asset, default: []].insert(groupID) }
    }

    public mutating func remove(groupID: String) {
        guard let members = membersByGroup.removeValue(forKey: groupID) else { return }
        for asset in members {
            groupsByAsset[asset]?.remove(groupID)
            if groupsByAsset[asset]?.isEmpty == true { groupsByAsset[asset] = nil }
        }
    }

    /// Every group that contains at least one of these assets (changed, inserted or deleted).
    public func groupsAffected(by assetIDs: Set<String>) -> Set<String> {
        assetIDs.reduce(into: Set<String>()) { result, asset in
            if let groups = groupsByAsset[asset] { result.formUnion(groups) }
        }
    }
}

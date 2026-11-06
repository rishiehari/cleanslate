import Foundation
import CleanSlateCore

extension PreservationFlag {
    /// Plain-words reason shown when a protected photo is tapped (U3).
    var userFacingReason: String {
        switch self {
        case .favorite: "Favorite — always kept"
        case .hidden: "Hidden — always kept"
        case .edited: "Edited — kept, since the other copy isn't an identical edit"
        case .raw: "RAW photo — kept, since the other copy isn't identical"
        case .livePhoto: "Live Photo — kept, since the other copy isn't identical"
        case .shared: "Shared — always kept"
        case .userBurstPick: "Your burst pick — always kept"
        case .curatedAlbum: "In one of your albums — kept"
        case .incompleteResources: "Not fully on this iPhone — kept"
        case .unknownOwnership, .uncertainMetadata: "Can't be sure — kept"
        }
    }
}

/// State for reviewing ONE group. Haptics are fired here, never from the view (U9).
@MainActor
final class GroupReviewModel: ObservableObject {
    let group: PhotoReviewGroup
    @Published private(set) var draft: ReviewDraft
    @Published var notice: String?
    private let tray: DeletionTray
    private let haptics: HapticsService
    private let protectedReasons: [String: String]

    init(group: PhotoReviewGroup, tray: DeletionTray, haptics: HapticsService = .shared) {
        self.group = group
        self.tray = tray
        self.haptics = haptics
        let decision = SafetyPolicy.evaluate(group.coreCluster)
        var reasons: [String: String] = [:]
        for id in decision.blocked.keys {
            let flag = group.candidates.first { $0.id == id }?.record.flags.sorted { $0.rawValue < $1.rawValue }.first
            reasons[id] = flag?.userFacingReason ?? "Can't be removed safely — kept"
        }
        protectedReasons = reasons
        // Only byte-verified exact copies are pre-marked (U4). Similar groups start with nothing marked.
        draft = ReviewDraft(assetIDs: group.all.map(\.id), keeperIDs: [group.keeper.id],
                            preMarkedDelete: group.kind == .exact ? decision.preselected : [],
                            protectedIDs: Set(decision.blocked.keys))
    }

    var isExact: Bool { group.kind == .exact }
    var canApprove: Bool { draft.canApprove }
    var approvedBytes: Int64 { draft.deleteIDs.reduce(Int64(0)) { $0 + (group.verifiedCandidateBytes[$1] ?? 0) } }

    func decision(for id: String) -> Decision {
        if let reason = protectedReasons[id] { return .protected(reason: reason) }
        switch draft.mark(for: id) {
        case .keep: return .keep
        case .delete: return .delete
        default: return .undecided
        }
    }

    func tap(_ id: String) {
        switch draft.toggle(id) {
        case .changed: notice = nil; haptics.fire(.toggle)
        case .blockedProtected: notice = protectedReasons[id] ?? "This photo is always kept."; haptics.fire(.blocked)
        case .blockedLastKeep: notice = "Keep at least one photo in each group."; haptics.fire(.blocked)
        case .unknownAsset: break
        }
    }

    func set(_ id: String, to mark: ReviewDraft.Mark) {
        switch draft.set(id, to: mark) {
        case .changed: notice = nil; haptics.fire(.toggle)
        case .blockedProtected: notice = protectedReasons[id] ?? "This photo is always kept."; haptics.fire(.blocked)
        case .blockedLastKeep: notice = "Keep at least one photo in each group."; haptics.fire(.blocked)
        case .unknownAsset: break
        }
    }

    /// Moves the marked photos into the tray. Never deletes anything (U1).
    @discardableResult
    func approve() -> Bool {
        guard draft.canApprove else { haptics.fire(.blocked); return false }
        tray.approve(group: group, selected: draft.deleteIDs,
                     manuallyReviewed: isExact ? [] : draft.userMarkedDelete)
        haptics.fire(.approve)
        return true
    }

    func skip() {
        tray.skip(groupID: group.id)
        haptics.fire(.skip)
    }

    var evidence: [Evidence] {
        var items: [Evidence] = [isExact ? .identicalFile : .looksSimilar]
        if let burst = group.keeper.burstID, group.candidates.contains(where: { $0.burstID == burst }) { items.append(.sameBurst) }
        return items
    }
}

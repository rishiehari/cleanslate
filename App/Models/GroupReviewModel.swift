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
        case .cinematicVideo: "Cinematic video — kept"
        case .spatialMedia: "Spatial photo or video — kept"
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
    /// Photos that differ from the suggested keeper in a way that matters (faces, text). Advisory (Step 7.3).
    @Published private(set) var warnings: [String: Set<DifferenceWarning>] = [:]
    /// Photos whose warnings the user has looked at and accepted.
    @Published private(set) var acknowledged: Set<String> = []
    /// The photo whose warning sheet is open (tapping it asked "are you sure?").
    @Published var warningPromptFor: String?
    /// Previous states, newest last (at most 20), for Undo.
    private var history: [ReviewDraft] = []
    private let tray: DeletionTray
    private let haptics: HapticsService
    private let analyzer: PhotoAnalyzer?
    private let protectedReasons: [String: String]
    static let historyLimit = 20

    init(group: PhotoReviewGroup, tray: DeletionTray, haptics: HapticsService = .shared, analyzer: PhotoAnalyzer? = nil) {
        self.group = group
        self.tray = tray
        self.haptics = haptics
        self.analyzer = analyzer
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

    var canUndo: Bool { !history.isEmpty }

    private func remember() {
        history.append(draft)
        if history.count > Self.historyLimit { history.removeFirst() }
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        draft = previous; notice = nil
        haptics.fire(.undo)
    }

    /// Looks for faces/text that differ from the suggested keeper. Runs once, in the background.
    func loadWarnings() async {
        guard let analyzer, warnings.isEmpty else { return }
        let keeperDescription = await analyzer.describe(assetID: group.keeper.id)
        for photo in group.candidates {
            let found = DifferenceAnalysis.warnings(candidate: await analyzer.describe(assetID: photo.id), keeper: keeperDescription)
            if !found.isEmpty { warnings[photo.id] = found }
        }
    }

    func isAwaitingAcknowledgement(_ id: String) -> Bool {
        !(warnings[id] ?? []).isEmpty && !acknowledged.contains(id)
    }

    /// The user looked at the warning and still wants this photo removed.
    func acknowledgeAndDelete(_ id: String) {
        acknowledged.insert(id)
        warningPromptFor = nil
        set(id, to: .delete)
    }

    /// "Keep the suggested photo, mark the rest": marks, it never approves. Photos with an unacknowledged
    /// warning stay undecided so nothing important is marked for deletion without a look.
    func markEverythingElseForDeletion() {
        remember()
        var changed = false
        for photo in group.candidates where !isAwaitingAcknowledgement(photo.id) && draft.mark(for: photo.id) != .delete {
            if case .changed = draft.set(photo.id, to: .delete) { changed = true }
        }
        if !changed { history.removeLast() } else { notice = nil; haptics.fire(.toggle) }
    }

    func tap(_ id: String) {
        if draft.mark(for: id) != .delete, isAwaitingAcknowledgement(id) {
            warningPromptFor = id; haptics.fire(.blocked); return
        }
        remember()
        let before = draft
        defer { if draft == before, !history.isEmpty { history.removeLast() } }
        switch draft.toggle(id) {
        case .changed: notice = nil; haptics.fire(.toggle)
        case .blockedProtected: notice = protectedReasons[id] ?? "This photo is always kept."; haptics.fire(.blocked)
        case .blockedLastKeep: notice = "Keep at least one photo in each group."; haptics.fire(.blocked)
        case .unknownAsset: break
        }
    }

    func set(_ id: String, to mark: ReviewDraft.Mark) {
        remember()
        let before = draft
        defer { if draft == before, !history.isEmpty { history.removeLast() } }
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
                     manuallyReviewed: isExact ? [] : draft.userMarkedDelete, keepers: draft.keepIDs)
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

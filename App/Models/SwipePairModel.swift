import Foundation
import CleanSlateCore

/// Presentation queue only: reuse complete, directly compared scan pairs. Never make new groups.
@MainActor
enum SwipePairFeed {
    static func groups(in model: CleaningViewModel) -> [PhotoReviewGroup] {
        guard [.authorized, .limited].contains(model.authorization),
              model.library.authorization == model.authorization, !model.tray.isDeleting else { return [] }
        let occupied = Set(model.tray.entries.flatMap { $0.involvedIDs })
            .union(model.tray.standaloneEntries.flatMap { $0.items.map(\.id) })
        var used = occupied
        return model.groups.sorted { $0.id < $1.id }.filter { group in
            guard eligible(group), !model.tray.reviewedGroupIDs.contains(group.id),
                  !model.recheckingGroupIDs.contains(group.id),
                  used.isDisjoint(with: group.all.map(\.id)) else { return false }
            used.formUnion(group.all.map(\.id))
            return true
        }
    }

    static func eligible(_ group: PhotoReviewGroup) -> Bool {
        // seq-* edges describe burst/time grouping, rather than an individual Vision comparison.
        guard group.id.hasPrefix("near-"), group.kind == .similar, group.candidates.count == 1,
              group.keeper.id != group.candidates[0].id,
              group.all.allSatisfy({ !$0.isVideo && !$0.record.revision.isEmpty && $0.id == $0.record.id }) else { return false }
        return group.evidence.count == 1 && group.evidence.allSatisfy {
            $0.joins(group.keeper.id, group.candidates[0].id) && $0.relation == .visuallySimilar && !$0.uniqueContentDetected
        }
    }

    /// Includes evidence, protections, membership and revisions, so a changed pair gets fresh warning state.
    static func token(_ group: PhotoReviewGroup) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(group).base64EncodedString()) ?? group.id
    }
}

/// Either orientation uses the normal review model, including its protection and warning gates.
/// A swipe only marks a choice. A separate Approve action adds it to the shared tray.
@MainActor
final class SwipePairModel: ObservableObject {
    enum Side { case left, right }
    let original: PhotoReviewGroup
    let keepLeft: GroupReviewModel
    let keepRight: GroupReviewModel
    @Published private(set) var side: Side?
    @Published private(set) var notice: String?
    private let cleaning: CleaningViewModel

    init(group: PhotoReviewGroup, cleaning: CleaningViewModel) {
        original = group
        self.cleaning = cleaning
        keepLeft = GroupReviewModel(group: group, tray: cleaning.tray, analyzer: cleaning.analyzer)
        let reversed = PhotoReviewGroup(id: group.id, kind: group.kind, keeper: group.candidates[0],
                                       candidates: [group.keeper], evidence: group.evidence,
                                       verifiedCandidateBytes: group.verifiedCandidateBytes)
        keepRight = GroupReviewModel(group: reversed, tray: cleaning.tray, analyzer: cleaning.analyzer)
    }

    var review: GroupReviewModel { side == .right ? keepRight : keepLeft }

    var isCurrent: Bool {
        guard [.authorized, .limited].contains(cleaning.authorization),
              cleaning.library.authorization == cleaning.authorization, !cleaning.tray.isDeleting,
              !cleaning.tray.reviewedGroupIDs.contains(original.id),
              !cleaning.recheckingGroupIDs.contains(original.id),
              let current = cleaning.groups.first(where: { $0.id == original.id }),
              SwipePairFeed.token(current) == SwipePairFeed.token(original) else { return false }
        let members = Set(original.all.map(\.id))
        return cleaning.tray.entries.allSatisfy { members.isDisjoint(with: $0.involvedIDs) }
            && cleaning.tray.standaloneEntries.allSatisfy { members.isDisjoint(with: $0.items.map(\.id)) }
    }

    func choose(_ side: Side) {
        guard isCurrent else { notice = "These photos changed. Choose again after scanning."; return }
        self.side = side
        notice = nil
        let target = review.group.candidates[0].id
        // tap, rather than set(.delete), preserves the warning acknowledgement gate.
        if !review.draft.deleteIDs.contains(target) { review.tap(target) }
    }

    func undoChoice() {
        keepLeft.set(keepLeft.group.candidates[0].id, to: .undecided)
        keepRight.set(keepRight.group.candidates[0].id, to: .undecided)
        keepLeft.warningPromptFor = nil
        keepRight.warningPromptFor = nil
        side = nil
        notice = nil
        HapticsService.shared.fire(.undo)
    }

    @discardableResult
    func approve() -> Bool {
        guard side != nil, isCurrent, freshSnapshotsMatch else {
            notice = "These photos changed. Scan again before approving."
            return false
        }
        return review.approve()
    }

    func keepBoth() {
        guard isCurrent else { return }
        undoChoice()
        keepLeft.skip()
    }

    private var freshSnapshotsMatch: Bool {
        original.all.allSatisfy { photo in
            guard let fresh = cleaning.library.snapshot(id: photo.id, inspectAlbums: true) else { return false }
            return fresh.record == photo.record
        }
    }
}

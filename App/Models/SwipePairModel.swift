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
            // Product feed remains the directly compared similar-pair V1. Exact-pair
            // model support does not silently expand the approved feed contract.
            guard group.kind == .similar, group.id.hasPrefix("near-"), eligible(group), !model.tray.reviewedGroupIDs.contains(group.id),
                  !model.recheckingGroupIDs.contains(group.id),
                  used.isDisjoint(with: group.all.map(\.id)) else { return false }
            used.formUnion(group.all.map(\.id))
            return true
        }
    }

    static func eligible(_ group: PhotoReviewGroup) -> Bool {
        // Support both exact and similar pairs
        guard group.kind == .similar || group.kind == .exact,
              group.candidates.count == 1,
              group.keeper.id != group.candidates[0].id,
              group.all.allSatisfy({ !$0.isVideo && !$0.record.revision.isEmpty && $0.id == $0.record.id }) else { return false }
        
        // For similar pairs, check that they are directly compared
        if group.kind == .similar {
            return group.evidence.count == 1 && group.evidence.allSatisfy {
                $0.joins(group.keeper.id, group.candidates[0].id) && $0.relation == .visuallySimilar && !$0.uniqueContentDetected
            }
        }
        
        // For exact pairs, check that they are exactly equal
        if group.kind == .exact {
            return group.evidence.count == 1 && group.evidence.allSatisfy {
                $0.joins(group.keeper.id, group.candidates[0].id) && $0.relation == .exactResources && $0.completeResourceEquality
            }
        }
        
        return false
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
    enum ChoiceType { case keepLeft, keepRight, keepBoth }
    
    let original: PhotoReviewGroup
    let keepLeft: GroupReviewModel
    let keepRight: GroupReviewModel
    @Published private(set) var side: Side?
    @Published private(set) var choiceType: ChoiceType?
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
        choiceType = side == .left ? .keepLeft : .keepRight
        notice = nil
        let target = review.group.candidates[0].id
        // tap, rather than set(.delete), preserves the warning acknowledgement gate.
        if !review.draft.deleteIDs.contains(target) { review.tap(target) }
    }

    func chooseKeepBoth() {
        guard isCurrent else { return }
        undoChoice()
        choiceType = .keepBoth
        keepLeft.skip()
    }

    func undoChoice() {
        keepLeft.set(keepLeft.group.candidates[0].id, to: .undecided)
        keepRight.set(keepRight.group.candidates[0].id, to: .undecided)
        keepLeft.warningPromptFor = nil
        keepRight.warningPromptFor = nil
        side = nil
        choiceType = nil
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

    func keepBoth() { chooseKeepBoth() }

    private var freshSnapshotsMatch: Bool {
        original.all.allSatisfy { photo in
            guard let fresh = cleaning.library.snapshot(id: photo.id, inspectAlbums: true) else { return false }
            return fresh.record == photo.record
        }
    }
    
    /// Returns whether this is an exact pair (byte-for-byte identical)
    var isExactPair: Bool {
        original.kind == .exact
    }
}

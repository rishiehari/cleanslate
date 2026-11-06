import SwiftUI
import CleanSlateCore

/// Review one group: the Keep photo on top, the others below. Tap a photo to flip Keep/Delete.
/// Approve moves the Delete-marked photos into the tray. It never deletes (U1).
struct ReviewGroupView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @StateObject private var review: GroupReviewModel
    @ScaledMetric(relativeTo: .body) private var barClearance = Spacing.barClearance
    @State private var explaining: Evidence?
    @State private var comparing: PhotoSnapshot?

    /// Called after Approve or Skip so the next group can open (or the session can end).
    private let onFinished: () -> Void
    private let position: String?

    init(group: PhotoReviewGroup, tray: DeletionTray, position: String? = nil, onFinished: @escaping () -> Void) {
        _review = StateObject(wrappedValue: GroupReviewModel(group: group, tray: tray))
        self.position = position
        self.onFinished = onFinished
    }

    private var others: [PhotoSnapshot] { review.group.candidates }
    /// The library changed under this group; Approve waits until it has been rechecked.
    private var isRechecking: Bool { model.recheckingGroupIDs.contains(review.group.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                intro
                chips
                PhotoTile(assetID: review.group.keeper.id,
                          decision: review.decision(for: review.group.keeper.id), target: 900,
                          traits: review.group.keeper.record.flags)
                    .onTapGesture { review.tap(review.group.keeper.id) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Keep, suggested photo, photo 1 of \(review.group.all.count)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("tile.\(review.group.keeper.id)")
                Text(review.isExact ? "Copies" : "Other shots")
                    .appText(.groupTitle).foregroundStyle(Color.textPrimary)
                LazyVGrid(columns: columns, spacing: Spacing.m) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, photo in
                        tile(photo, index: index)
                    }
                }
                if let notice = review.notice {
                    Label(notice, systemImage: "lock.fill")
                        .appText(.secondary).foregroundStyle(Color.textSecondary)
                        .padding(Spacing.s + Spacing.xs)
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Radius.m))
                        .accessibilityIdentifier("review.notice")
                }
            }
            .padding(Spacing.m)
            .padding(.bottom, barClearance * 1.6)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)   // separates the floating bar from scrolling photos
        .background(Color.surfaceBackground)
        .navigationTitle(position ?? "\(review.group.all.count) photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Compare", systemImage: "square.split.2x1") { comparing = others.first }
                    .accessibilityIdentifier("review.compare")
            }
        }
        .safeAreaInset(edge: .bottom) {
            ApprovalBar(approveTitle: isRechecking ? "Rechecking…" : approveTitle, subtitle: isRechecking ? nil : subtitle,
                        canApprove: review.canApprove && !isRechecking,
                        onSkip: { review.skip(); onFinished() },
                        onApprove: { if review.approve() { onFinished() } })
        }
        .sheet(item: $explaining) { evidence in
            EvidenceExplanation(evidence: evidence)
        }
        .fullScreenCover(item: $comparing) { photo in
            CompareView(keeperID: review.group.keeper.id, otherID: photo.id,
                        otherChoices: others.map(\.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.screen")
    }

    private var columns: [GridItem] {
        others.count <= 2 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var intro: some View {
        Text(review.isExact
             ? "These files are identical. The copies are marked Delete — approve to add them to your tray."
             : "These look alike, but only you can tell which to remove. Tap the photos you want to delete.")
            .appText(.secondary).foregroundStyle(Color.textSecondary)
    }

    private var chips: some View {
        HStack(spacing: Spacing.s) {
            ForEach(review.evidence) { item in EvidenceChip(evidence: item) { explaining = item } }
        }
    }

    private var approveTitle: String {
        let n = review.draft.deleteIDs.count
        return n == 0 ? "Approve" : "Approve \(n) \(n == 1 ? "photo" : "photos")"
    }

    private var subtitle: String? {
        review.approvedBytes > 0 ? review.approvedBytes.friendlyBytes : nil
    }

    private func tile(_ photo: PhotoSnapshot, index: Int) -> some View {
        let decision = review.decision(for: photo.id)
        return PhotoTile(assetID: photo.id, decision: decision, target: 700,
                         caption: review.group.verifiedCandidateBytes[photo.id]?.friendlyBytes,
                         traits: photo.record.flags)
            .onTapGesture { review.tap(photo.id) }
            .contextMenu {
                Button("Compare with the Keep photo", systemImage: "square.split.2x1") { comparing = photo }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: decision, index: index))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Keep") { review.set(photo.id, to: .keep) }
            .accessibilityAction(named: "Delete") { review.set(photo.id, to: .delete) }
            .accessibilityAction(named: "Compare") { comparing = photo }
            .accessibilityIdentifier("tile.\(photo.id)")
    }

    private func accessibilityLabel(for decision: Decision, index: Int) -> String {
        let state: String
        switch decision {
        case .keep: state = "Keep"
        case .delete: state = "Delete"
        case .undecided: state = "Not decided"
        case .protected(let reason): state = reason
        }
        return "\(state), photo \(index + 2) of \(review.group.all.count)"
    }
}

private struct EvidenceExplanation: View {
    let evidence: Evidence
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label(evidence.title, systemImage: evidence.symbol).appText(.title)
            Text(evidence.explanation).appText(.body)
            Spacer()
        }
        .padding(Spacing.l)
        .presentationDetents([.fraction(0.3)])
    }
}

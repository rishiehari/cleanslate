import SwiftUI
import CleanSlateCore

/// Review one group: the Keep photo on top, the others below. Tap a photo to flip Keep/Delete.
/// Approve moves the Delete-marked photos into the tray. It never deletes (U1).
struct ReviewGroupView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var labels: LabelStore
    @StateObject private var review: GroupReviewModel
    @ScaledMetric(relativeTo: .body) private var barClearance = Spacing.barClearance
    @State private var explaining: Evidence?
    @State private var comparing: PhotoSnapshot?

    /// Called after Approve or Skip so the next group can open (or the session can end).
    private let onFinished: () -> Void
    private let position: String?

    init(group: PhotoReviewGroup, tray: DeletionTray, analyzer: PhotoAnalyzer? = nil, position: String? = nil,
         onFinished: @escaping () -> Void) {
        _review = StateObject(wrappedValue: GroupReviewModel(group: group, tray: tray, analyzer: analyzer))
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
                HStack {
                    Text(review.isExact ? "Copies" : "Other shots")
                        .appText(.groupTitle).foregroundStyle(Color.textPrimary)
                    Spacer()
                    if !review.isExact && others.count >= 2 {
                        Button("Mark the rest") { review.markEverythingElseForDeletion() }
                            .appText(.secondary).buttonStyle(.bordered)
                            .accessibilityHint("Marks every other shot for deletion. Nothing is deleted until you approve.")
                            .accessibilityIdentifier("review.markrest")
                    }
                }
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
            if review.canUndo {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { review.undo() }
                        .accessibilityIdentifier("review.undo")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Compare", systemImage: "square.split.2x1") { comparing = others.first }
                    .accessibilityIdentifier("review.compare")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("This suggestion was wrong", systemImage: "hand.thumbsdown") { labels.recordCorrection() }
                        .accessibilityIdentifier("review.wrong")
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
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
        .sheet(item: Binding(get: { review.warningPromptFor.map(WarningPrompt.init) }, set: { review.warningPromptFor = $0?.id })) { prompt in
            WarningSheet(warnings: review.warnings[prompt.id] ?? [], couldntCompare: review.couldntCompare.contains(prompt.id),
                         onRemoveAnyway: { review.acknowledgeAndDelete(prompt.id) },
                         onCancel: { review.warningPromptFor = nil })
        }
        .task { await review.loadWarnings() }
        .fullScreenCover(item: $comparing) { photo in
            CompareView(keeperID: review.group.keeper.id, otherID: photo.id,
                        otherChoices: others.map(\.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.screen")
    }

    private var columns: [GridItem] {
        let count = others.count <= 2 ? 1 : (others.count <= 6 ? 2 : 3)        // photos stay big for small groups
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.s + Spacing.xs), count: count)
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
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            tileImage(photo, decision: decision, index: index)
            if labels.isEnabled && !review.isExact { labelMenu(for: photo) }
            if let found = review.warnings[photo.id], !found.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ForEach(found.sorted { $0.rawValue < $1.rawValue }, id: \.self) { warning in
                        EvidenceChip(evidence: warning == .differentPeople ? .differentPeople : .differentText) { review.warningPromptFor = photo.id }
                    }
                }
            }
            if review.couldntCompare.contains(photo.id) {
                EvidenceChip(evidence: .couldntCompare) { review.warningPromptFor = photo.id }
            }
        }
    }

    /// Testers only: what is this photo really, compared with the suggested keeper?
    private func labelMenu(for photo: PhotoSnapshot) -> some View {
        Menu {
            ForEach(RawLabel.Verdict.allCases, id: \.self) { verdict in
                Button(verdict.rawValue) { labels.set(verdict, for: photo, in: review.group.id) }
            }
            Button("Best shot of the group", systemImage: "star") { labels.setBest(photo, in: review.group.id) }
        } label: {
            Label(labels.verdict(for: photo.id, in: review.group.id)?.rawValue ?? "Label this photo",
                  systemImage: labels.isBest(photo.id, in: review.group.id) ? "star.fill" : "tag")
                .appText(.chip)
        }
        .accessibilityIdentifier("label.\(photo.id)")
    }

    private func tileImage(_ photo: PhotoSnapshot, decision: Decision, index: Int) -> some View {
        PhotoTile(assetID: photo.id, decision: decision, target: 700,
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

struct WarningPrompt: Identifiable { let id: String }

struct WarningSheet: View {
    let warnings: Set<DifferenceWarning>
    var couldntCompare = false
    let onRemoveAnyway: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label("Look closely before removing this", systemImage: "exclamationmark.triangle").appText(.title)
            ForEach(warnings.sorted { $0.rawValue < $1.rawValue }, id: \.self) { warning in
                Text(warning == .differentPeople ? Evidence.differentPeople.explanation : Evidence.differentText.explanation).appText(.body)
            }
            if couldntCompare { Text(Evidence.couldntCompare.explanation).appText(.body) }
            Spacer()
            Button(action: onRemoveAnyway) { Text("I've looked, mark it for deletion").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.glassProminent).tint(Color.deleteAccent)
                .accessibilityIdentifier("warning.confirm")
            Button("Keep it", role: .cancel, action: onCancel).frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("warning.cancel")
        }
        .padding(Spacing.l)
        .presentationDetents([.medium])
        .presentationBackground(Color.surfaceBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("warning.sheet")
    }
}

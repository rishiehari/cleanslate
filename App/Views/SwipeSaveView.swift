import SwiftUI

/// A small daily review session over the scanner's original, directly compared pairs.
struct SwipeSaveView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    @State private var showTray = false
    @State private var pairs: [PhotoReviewGroup] = []
    @State private var queueRevision = 0

    var body: some View {
        NavigationStack {
            ContentStateView(state: state) { group in
                SwipePairCard(group: group, cleaning: model)
                    .id(SwipePairFeed.token(group))
            }
            .background(Color.surfaceBackground)
            .navigationTitle("Swipe n Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TrayButton(count: tray.photoCount) { showTray = true }
                }
            }
            .sheet(isPresented: $showTray) { TrayView(tray: tray) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("swipe.screen")
        }
        // Rebuild only when queue inputs change, not on scan progress ticks or drag updates.
        .onReceive(model.$groups) { _ in queueRevision += 1 }
        .onReceive(model.$recheckingGroupIDs) { _ in queueRevision += 1 }
        .onReceive(model.$authorization) { _ in queueRevision += 1 }
        .onReceive(tray.$reviewedGroupIDs) { _ in queueRevision += 1 }
        .onReceive(tray.$entries) { _ in queueRevision += 1 }
        .onReceive(tray.$standaloneEntries) { _ in queueRevision += 1 }
        .onReceive(tray.$isDeleting) { _ in queueRevision += 1 }
        .task(id: queueRevision) {
            await Task.yield() // @Published emits before the model's property is updated.
            guard !Task.isCancelled else { return }
            pairs = SwipePairFeed.groups(in: model)
        }
        .task(id: pairs.prefix(4).map(\.id).joined(separator: "|")) {
            model.library.prefetchThumbnails(pairs.prefix(4).flatMap { $0.all.map(\.id) }, target: 600)
        }
        .onDisappear { model.library.prefetchThumbnails([], target: 600) }
    }

    private var state: ContentState<PhotoReviewGroup> {
        if ![.authorized, .limited].contains(model.authorization) {
            return .permission(message: "Allow Photos access from Home to find pairs to review.")
        }
        if let first = pairs.first { return .loaded(first) }
        if model.isScanning { return .loading(progress: model.progress, message: "Looking for similar pairs. You can start when a pair is ready.") }
        return .empty(title: "No pairs ready", message: "Scan from Home to find closely similar pairs. Larger groups stay in the regular review list. Come back for a few minutes whenever you like.")
    }
}

private struct SwipePairCard: View {
    @StateObject private var pair: SwipePairModel

    init(group: PhotoReviewGroup, cleaning: CleaningViewModel) {
        _pair = StateObject(wrappedValue: SwipePairModel(group: group, cleaning: cleaning))
    }

    var body: some View {
        SwipePairContent(pair: pair, review: pair.review)
            .task {
                await pair.keepLeft.loadWarnings()
                await pair.keepRight.loadWarnings()
            }
    }
}

private struct SwipePairContent: View {
    @ObservedObject var pair: SwipePairModel
    @ObservedObject var review: GroupReviewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGSize = .zero
    @State private var comparing = false
    @State private var explaining = false

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.m)) : AnyLayout(HStackLayout(spacing: Spacing.s))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("A few minutes. A little more room.").appText(.groupTitle)
                Text("Swipe left to keep the left photo, or right to keep the right. Choose Keep both to move on. Then approve your choice to add one photo to the tray.")
                    .appText(.secondary).foregroundStyle(Color.textSecondary)
                Button { explaining = true } label: {
                    Label("Looks similar", systemImage: "square.on.square").frame(minHeight: 44)
                }
                    .appText(.chip).accessibilityIdentifier("swipe.evidence")
                layout {
                    photo(pair.original.keeper, side: .left, name: "Left")
                    photo(pair.original.candidates[0], side: .right, name: "Right")
                }
                .offset(x: reduceMotion ? 0 : dragOffset.width / 4)
                .gesture(
                    DragGesture(minimumDistance: Spacing.l)
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            // Check if it's a horizontal swipe (left or right)
                            if abs(value.translation.width) > IconSize.hero,
                               abs(value.translation.width) > abs(value.translation.height) {
                                // Horizontal swipe - keep left or right
                                pair.choose(value.translation.width < 0 ? .left : .right)
                            } else if abs(value.translation.height) > IconSize.hero,
                                      value.translation.height < 0 {
                                // Up swipe - keep both
                                pair.chooseKeepBoth()
                            }
                        }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("swipe.pair")
                choices
                if let notice = pair.notice ?? review.notice {
                    Text(notice).appText(.secondary).foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("swipe.notice")
                }
                Text("Approving never deletes. Your tray has a separate confirmation, followed by Apple's prompt.")
                    .appText(.caption).foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.m)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Compare", systemImage: "square.split.2x1") { comparing = true }
                    .accessibilityIdentifier("swipe.compare")
            }
            if pair.choiceType != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo choice", systemImage: "arrow.uturn.backward") { pair.undoChoice() }
                        .accessibilityIdentifier("swipe.undo")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: Spacing.m) {
                Button { pair.approve() } label: {
                    Text("Approve 1 photo").appText(.groupTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent).tint(Color.actionPrimary)
                .disabled(pair.choiceType == nil || !review.canApprove || review.isCheckingPhotos || !pair.isCurrent)
                .accessibilityHint("Adds the Delete-marked photo to your tray. Does not delete it.")
                .accessibilityIdentifier("swipe.approve")
            }
            .padding(Spacing.m)
        }
        .fullScreenCover(isPresented: $comparing) {
            CompareView(keeperID: pair.original.keeper.id, otherID: pair.original.candidates[0].id, otherChoices: [])
        }
        .sheet(isPresented: $explaining) {
            Text(Evidence.looksSimilar.explanation).appText(.body).padding(Spacing.l)
                .presentationDetents([.medium])
        }
        .sheet(item: Binding(get: { review.warningPromptFor.map(WarningPrompt.init) }, set: { review.warningPromptFor = $0?.id })) { prompt in
            WarningSheet(warnings: review.warnings[prompt.id] ?? [], couldntCompare: review.couldntCompare.contains(prompt.id),
                          onRemoveAnyway: { review.acknowledgeAndDelete(prompt.id) },
                          onCancel: { review.warningPromptFor = nil })
        }
    }

    private var choices: some View {
        VStack(spacing: Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { keepLeft; keepBoth; keepRight }
                VStack(spacing: Spacing.s) { keepLeft; keepBoth; keepRight }
            }
            if review.isCheckingPhotos {
                ProgressView("Checking faces and text…").appText(.caption)
                    .accessibilityIdentifier("swipe.checking")
            }
        }
        .buttonStyle(.bordered)
    }

    private var keepLeft: some View {
        Button { pair.choose(.left) } label: { Label("Keep left", systemImage: "arrow.left").frame(minHeight: 44) }
            .accessibilityIdentifier("swipe.left")
    }
    private var keepBoth: some View {
        Button { pair.chooseKeepBoth() } label: { Label("Keep both", systemImage: "checkmark.circle").frame(minHeight: 44) }
            .accessibilityHint("Keeps both photos and moves to the next pair. You can undo this.")
            .accessibilityIdentifier("swipe.both")
    }
    private var keepRight: some View {
        Button { pair.choose(.right) } label: { Label("Keep right", systemImage: "arrow.right").frame(minHeight: 44) }
            .accessibilityIdentifier("swipe.right")
    }

    private func photo(_ photo: PhotoSnapshot, side: SwipePairModel.Side, name: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("\(name) photo").appText(.secondary)
            PhotoTile(assetID: photo.id, decision: decision(photo) == .undecided ? nil : decision(photo), target: 600, traits: photo.record.flags)
                .accessibilityIgnoresInvertColors()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name) photo")
                .accessibilityValue(decisionText(photo))
                .accessibilityAction(named: "Keep this photo") { pair.choose(side) }
                .accessibilityAction(named: "Compare") { comparing = true }
                .accessibilityIdentifier("swipe.photo.\(photo.id)")
        }
    }

    private func decision(_ photo: PhotoSnapshot) -> Decision {
        // Each member is evaluated as a candidate in one orientation, including the original keeper.
        let protection = photo.id == pair.original.keeper.id
            ? pair.keepRight.decision(for: photo.id) : pair.keepLeft.decision(for: photo.id)
        if case .protected = protection { return protection }
        if pair.choiceType == nil { return photo.id == pair.original.keeper.id ? .keep : .undecided }
        return review.decision(for: photo.id)
    }

    private func decisionText(_ photo: PhotoSnapshot) -> String {
        switch decision(photo) {
        case .keep: "Keep"
        case .delete: "Delete"
        case .undecided: "Not decided"
        case .protected(let reason): reason
        }
    }
}

#if DEBUG
private struct SwipeSavePreview: View {
    @StateObject private var model: CleaningViewModel

    init(empty: Bool = false) {
        let scenario = FakePhotoLibrary.uiTestScenario(swipePairs: true)
        let model = CleaningViewModel(library: scenario.library, tray: DeletionTray(fileURL: nil), store: try? LibraryStore(path: nil))
        model.seedGroupsForUITesting(empty ? [] : scenario.groups)
        model.analyzer = FakePhotoAnalyzer()
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        SwipeSaveView().environmentObject(model).environmentObject(model.tray)
            .environment(\.photoLibraryOverride, model.library)
    }
}

#Preview("Swipe pair") { SwipeSavePreview() }
#Preview("No pairs") { SwipeSavePreview(empty: true) }
#Preview("Swipe pair, dark") { SwipeSavePreview().preferredColorScheme(.dark) }
#Preview("Swipe pair, large text") { SwipeSavePreview().dynamicTypeSize(.accessibility3) }
#endif
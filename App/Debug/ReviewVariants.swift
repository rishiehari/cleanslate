#if DEBUG
import SwiftUI

/// Five divergent takes on the review screen, built on the shared design system.
/// Prototypes only (DEBUG): pick one, then the real screen carries it forward.
enum ReviewVariant: Int, CaseIterable, Identifiable {
    case cardStack = 1, heroStrip, gridTriage, sideBySide, inboxList
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .cardStack: "Card Stack"
        case .heroStrip: "Hero + Strip"
        case .gridTriage: "Grid Triage"
        case .sideBySide: "Side by Side"
        case .inboxList: "Inbox List"
        }
    }
}

struct PrototypeHost: View {
    let variant: ReviewVariant
    private let scenario = FakePhotoLibrary.uiTestScenario()

    var body: some View {
        let similar = scenario.groups.first { $0.kind == .similar }!
        let exact = scenario.groups.filter { $0.kind == .exact && !$0.keeper.isVideo }
        NavigationStack {
            Group {
                switch variant {
                case .cardStack: CardStackVariant(group: similar)
                case .heroStrip: HeroStripVariant(group: similar)
                case .gridTriage: GridTriageVariant(group: similar)
                case .sideBySide: SideBySideVariant(group: similar)
                case .inboxList: InboxListVariant(groups: exact)
                }
            }
            .background(Color.surfaceBackground)
            .navigationTitle(variant.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.photoLibraryOverride, scenario.library)
    }
}

private struct VariantBar: View {
    let title: String
    var body: some View {
        ApprovalBar(approveTitle: title, subtitle: nil, canApprove: true, onSkip: {}, onApprove: {})
    }
}

/// 1. A deck: one big card per group, swipe up to approve.
private struct CardStackVariant: View {
    let group: PhotoReviewGroup
    @State private var marked: Set<String> = []
    var body: some View {
        VStack(spacing: Spacing.m) {
            ZStack {
                ForEach(Array(group.candidates.reversed().enumerated()), id: \.element.id) { i, photo in
                    PhotoTile(assetID: photo.id, decision: marked.contains(photo.id) ? .delete : .undecided)
                        .rotationEffect(.degrees(Double(i) * 3 - 3))
                        .offset(y: CGFloat(i) * -Spacing.s)
                        .onTapGesture { if marked.contains(photo.id) { marked.remove(photo.id) } else { marked.insert(photo.id) } }
                }
                PhotoTile(assetID: group.keeper.id, decision: .keep)
                    .offset(y: Spacing.l)
            }
            .padding(Spacing.m)
            Text("Swipe up to approve · tap a shot to mark it").appText(.caption).foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .safeAreaInset(edge: .bottom) { VariantBar(title: "Approve \(marked.count)") }
    }
}

/// 2. A big Keep photo with a filmstrip of the others. Recommended for similar shots and bursts.
private struct HeroStripVariant: View {
    let group: PhotoReviewGroup
    @State private var marked: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            PhotoTile(assetID: group.keeper.id, decision: .keep, target: 900).padding(.horizontal, Spacing.m)
            Text("Other shots").appText(.groupTitle).padding(.horizontal, Spacing.m)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s + Spacing.xs) {
                    ForEach(group.candidates) { photo in
                        PhotoTile(assetID: photo.id, decision: marked.contains(photo.id) ? .delete : .undecided, target: 400)
                            .frame(width: 220)
                            .onTapGesture { if marked.contains(photo.id) { marked.remove(photo.id) } else { marked.insert(photo.id) } }
                    }
                }
                .padding(.horizontal, Spacing.m)
            }
            Spacer()
        }
        .safeAreaInset(edge: .bottom) { VariantBar(title: "Approve \(marked.count)") }
    }
}

/// 3. Everything in a grid, like the Photos app.
private struct GridTriageVariant: View {
    let group: PhotoReviewGroup
    @State private var marked: Set<String> = []
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.s + Spacing.xs) {
                ForEach(group.all) { photo in
                    let isKeeper = photo.id == group.keeper.id
                    PhotoTile(assetID: photo.id, decision: isKeeper ? .keep : (marked.contains(photo.id) ? .delete : .undecided), target: 500)
                        .onTapGesture { if !isKeeper { if marked.contains(photo.id) { marked.remove(photo.id) } else { marked.insert(photo.id) } } }
                }
            }
            .padding(Spacing.m)
        }
        .safeAreaInset(edge: .bottom) { VariantBar(title: "Approve \(marked.count)") }
    }
}

/// 4. A/B: keeper beside one other shot at a time. Best for choosing between two near-identical shots.
private struct SideBySideVariant: View {
    let group: PhotoReviewGroup
    @State private var index = 0
    var body: some View {
        let other = group.candidates[index]
        VStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                VStack { PhotoTile(assetID: group.keeper.id, decision: .keep, target: 500); Text("Keep").appText(.chip) }
                VStack { PhotoTile(assetID: other.id, decision: .delete, target: 500); Text("Remove?").appText(.chip) }
            }
            .padding(Spacing.m)
            Picker("Compare with", selection: $index) {
                ForEach(group.candidates.indices, id: \.self) { Text("Shot \($0 + 2)").tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal, Spacing.m)
            Spacer()
        }
        .safeAreaInset(edge: .bottom) { VariantBar(title: "Approve 1") }
    }
}

/// 5. A vertical list of groups with an Approve button on each row. Fastest for exact copies.
private struct InboxListVariant: View {
    let groups: [PhotoReviewGroup]
    @State private var approved: Set<String> = []
    var body: some View {
        List {
            Section {
                ForEach(groups) { group in
                    HStack(spacing: Spacing.m) {
                        PhotoThumbnailView(assetID: group.keeper.id, target: 160)
                            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: Radius.s))
                        VStack(alignment: .leading) {
                            Text("Keep 1 · delete \(group.candidates.count)").appText(.groupTitle)
                            Text(group.estimatedVerifiedBytes.friendlyBytes).appText(.secondary).foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Button(approved.contains(group.id) ? "Added" : "Approve") { approved.insert(group.id) }
                            .buttonStyle(.bordered).tint(Color.actionPrimary)
                    }
                }
            } header: {
                Text("Exact copies")
            }
        }
        .safeAreaInset(edge: .bottom) {
            ApprovalBar(approveTitle: "Approve all \(groups.count)", subtitle: nil, canApprove: true, onSkip: {}, onApprove: {})
        }
    }
}

#Preview("Card Stack") { PrototypeHost(variant: .cardStack) }
#Preview("Hero + Strip") { PrototypeHost(variant: .heroStrip) }
#Preview("Grid Triage") { PrototypeHost(variant: .gridTriage) }
#Preview("Side by Side") { PrototypeHost(variant: .sideBySide) }
#Preview("Inbox List") { PrototypeHost(variant: .inboxList) }
#endif

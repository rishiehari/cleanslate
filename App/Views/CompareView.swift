import SwiftUI

/// Two photos, one shared zoom and pan, so the same spot lines up in both (U6).
struct CompareView: View {
    let keeperID: String
    @State var otherID: String
    let otherChoices: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: Spacing.xs) {
                    pane(keeperID, label: "Keep", height: proxy.size.height / 2 - Spacing.xs)
                    pane(otherID, label: "Compare", height: proxy.size.height / 2 - Spacing.xs)
                }
                .gesture(zoomAndPan)
                .onTapGesture(count: 2) { reset() }
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("compare.done")
                }
                if otherChoices.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next photo", systemImage: "arrow.right.circle") { advance() }
                    }
                }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compare.screen")
    }

    private func pane(_ id: String, label: String, height: CGFloat) -> some View {
        PhotoThumbnailView(assetID: id, target: 1400)
            .scaleEffect(scale)
            .offset(offset)
            .frame(height: height)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(label).appText(.badge).foregroundStyle(.white)
                    .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
                    .background(.black.opacity(0.78), in: Capsule()).padding(Spacing.s)
            }
    }

    private var zoomAndPan: some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { scale = min(8, max(1, baseScale * $0.magnification)) }
                .onEnded { _ in baseScale = scale; if scale == 1 { offset = .zero; baseOffset = .zero } },
            DragGesture()
                .onChanged { offset = CGSize(width: baseOffset.width + $0.translation.width,
                                             height: baseOffset.height + $0.translation.height) }
                .onEnded { _ in baseOffset = offset })
    }

    private func reset() {
        withAnimation(reduceMotion ? nil : .snappy) { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
    }

    private func advance() {
        guard let index = otherChoices.firstIndex(of: otherID) else { return }
        otherID = otherChoices[(index + 1) % otherChoices.count]
    }
}

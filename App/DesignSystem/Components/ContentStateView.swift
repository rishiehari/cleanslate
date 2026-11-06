import SwiftUI

enum ContentState<Value> {
    case loading(progress: Double?, message: String)
    case empty(title: String, message: String)
    case failed(message: String)
    case permission(message: String)
    case loaded(Value)
}

/// Every async or list screen renders through this (U11): no bare spinners, no dead ends.
struct ContentStateView<Value, Content: View>: View {
    let state: ContentState<Value>
    var retry: (() -> Void)?
    var openSettings: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading(let progress, let message):
            VStack(spacing: Spacing.m) {
                if let progress { ProgressView(value: progress) } else { ProgressView() }
                Text(message).appText(.secondary).foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        case .empty(let title, let message):
            ContentUnavailableView(title, systemImage: "checkmark.circle", description: Text(message))
        case .failed(let message):
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let retry { Button("Try again", action: retry) }
            }
        case .permission(let message):
            ContentUnavailableView {
                Label("Photos access needed", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(message)
            } actions: {
                if let openSettings { Button("Open Settings", action: openSettings) }
            }
        case .loaded(let value):
            content(value)
        }
    }
}

#Preview("Empty") {
    ContentStateView<Int, Text>(state: .empty(title: "Nothing found yet", message: "No copies in the 182,340 photos checked.")) { Text("\($0)") }
}
#Preview("Loading") {
    ContentStateView<Int, Text>(state: .loading(progress: 0.4, message: "Looking through 182,340 photos")) { Text("\($0)") }
}

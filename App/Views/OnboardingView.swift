import SwiftUI

/// Three short screens: privacy, how deletion works, Apple's own Duplicates album.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page { let symbol: String; let title: String; let body: String }
    private let pages = [
        Page(symbol: "lock.shield", title: "Your photos stay on your iPhone",
             body: "CleanSlate looks for copies right here on your device. No account, no ads, and nothing is uploaded."),
        Page(symbol: "hand.raised", title: "You decide what goes",
             body: "Nothing is deleted until you approve it, then confirm it in Apple's own prompt. Deleted photos stay in Recently Deleted for 30 days. If iCloud Photos is on, they're removed from your other devices too."),
        Page(symbol: "square.on.square", title: "Apple Photos can merge exact copies",
             body: "In Photos, open Collections, then Utilities, then Duplicates to merge exact copies. CleanSlate adds bursts and similar shots, videos, screenshots and large files, and shows you exactly what you'd free up.")
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: pages[index].symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text(pages[index].title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text(pages[index].body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .accessibilityIdentifier("onboarding.pages")

            Button {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { onFinish() }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier(page < pages.count - 1 ? "onboarding.next" : "onboarding.done")
        }
    }
}

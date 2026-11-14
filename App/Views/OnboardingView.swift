import SwiftUI

/// Four short screens: privacy, how deletion works, start small, permission priming.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @State private var showingProtectionDemo = false
    
    // For the permission priming page
    @State private var hasRequestedPermission = false

    private struct Page { 
        let symbol: String
        let title: String
        let body: String
        let isLastPage: Bool
    }
    
    private let pages = [
        Page(symbol: "lock.shield", title: "Everything stays on this iPhone",
             body: "CleanSlate checks your photos right here. No account, no ads, no tracking, and CleanSlate has no servers to send anything to.", isLastPage: false),
        Page(symbol: "hand.raised", title: "You decide, twice",
             body: "Nothing is deleted until you approve it here and confirm it in Apple's own prompt. Deleted photos stay in Recently Deleted for 30 days. With iCloud Photos on, they're removed from your other devices too.", isLastPage: false),
        Page(symbol: "scope", title: "Start small",
             body: "Your first check looks at your 100 most recent photos. You'll see what it finds before anything can be deleted.", isLastPage: false),
        Page(symbol: "square.on.square", title: "Apple Photos can merge exact copies",
             body: "In Photos, open Collections, then Utilities, then Duplicates to merge exact copies. CleanSlate adds bursts and similar shots, videos, screenshots and large files, and shows you exactly what you'd free up.", isLastPage: false)
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    ScrollView {
                        VStack(spacing: Spacing.l) {
                            Image(systemName: pages[index].symbol)
                                .font(.system(size: IconSize.hero))
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                            
                            Text(pages[index].title)
                                .appText(.title)
                                .multilineTextAlignment(.center)
                            
                            Text(pages[index].body)
                                .appText(.body)
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            if index == 0, FeatureFlags.protectionRulesUI {
                                Button("Try protecting a sample") { showingProtectionDemo = true }
                                    .appText(.body)
                                    .frame(minHeight: 44)
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("onboarding.protectionDemo")
                            }
                            
                            // Permission priming page
                            if index == pages.count - 1 {
                                Text("Next, iOS asks to let CleanSlate see your photos.")
                                    .appText(.body)
                                    .foregroundStyle(Color.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top)
                                
                                Text("*Allow Full Access* lets it check everything. *Limit Access* lets you pick photos.")
                                    .appText(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 4)
                                
                                Button("Continue") {
                                    hasRequestedPermission = true
                                    // In a real implementation, this would call requestAccess()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                                .padding(.top)
                                .accessibilityIdentifier("onboarding.allow")
                            }
                        }
                        .frame(maxWidth: AdaptiveLayout.readableContentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.l)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .accessibilityIdentifier("onboarding.pages")

            Button {
                if page < pages.count - 1 { 
                    withAnimation { page += 1 } 
                } else { 
                    onFinish() 
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.l)
            .accessibilityIdentifier(page < pages.count - 1 ? "onboarding.next" : "onboarding.done")
        }
        .sheet(isPresented: $showingProtectionDemo) { ProtectionDemoView() }
    }
}

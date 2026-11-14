import SwiftUI

/// Permission-free practice only: no Photos, rule service, storage, or deletion authority.
struct ProtectionDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sampleProtected = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Try protecting a sample")
                        .appText(.title).foregroundStyle(Color.textPrimary)
                    Text("This is an illustration, not one of your photos. No Photos access is needed, and nothing is saved or deleted.")
                        .appText(.body).foregroundStyle(Color.textPrimary)
                }
                Section("Sample birthday photo") {
                    Image(systemName: "birthday.cake")
                        .font(.system(size: IconSize.hero))
                        .foregroundStyle(Color.actionPrimary)
                        .accessibilityHidden(true)
                    Label(sampleProtected ? "Kept safe by your rule" : "Possible duplicate",
                          systemImage: sampleProtected ? "lock.shield" : "square.on.square")
                        .appText(.groupTitle).foregroundStyle(Color.textPrimary)
                        .accessibilityIdentifier("protectionDemo.status")
                    Text(sampleProtected ? "No sample deletion suggestion" : "1 sample deletion suggestion")
                        .appText(.body).foregroundStyle(Color.textPrimary)
                        .accessibilityIdentifier("protectionDemo.suggestions")
                    Button(sampleProtected ? "Try again" : "Protect sample") {
                        sampleProtected.toggle()
                    }
                    .appText(.body)
                    .frame(minHeight: 44)
                    .buttonStyle(AccessiblePrimaryButtonStyle())
                    .accessibilityIdentifier(sampleProtected ? "protectionDemo.reset" : "protectionDemo.protect")
                }
                Section {
                    Text("With your own photos, protection rules tell CleanSlate not to suggest deleting them. Apple Photos isn't changed.")
                        .appText(.body).foregroundStyle(Color.textPrimary)
                }
            }
            .scrollEdgeEffectHidden(true, for: .bottom)
            .navigationTitle("Protection example")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("protectionDemo.done")
                }
            }
        }
        .presentationSizing(.page)
    }
}

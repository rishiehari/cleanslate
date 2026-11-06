import SwiftUI

/// Explains and controls the one optional network feature: downloading originals from iCloud
/// to check copies that aren't on this iPhone. Off by default, Wi-Fi only, with a budget.
struct VerifyICloudSheet: View {
    @ObservedObject var policy: NetworkPolicy
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Check iCloud originals", isOn: $policy.isEnabled)
                        .accessibilityIdentifier("icloud.toggle")
                } footer: {
                    Text("Some photos live only in iCloud to save space on your iPhone, so CleanSlate can't compare them. With this on, it downloads them temporarily to check for copies. Nothing is uploaded, and it only uses Wi-Fi.")
                }
                Section("Download limit per scan") {
                    Picker("Limit", selection: $policy.budgetGB) {
                        ForEach(NetworkPolicy.budgetChoicesGB, id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("icloud.budget")
                    if policy.downloadedBytes > 0 {
                        LabeledContent("Downloaded so far", value: policy.downloadedBytes.friendlyBytes)
                    }
                }
                .disabled(!policy.isEnabled)
            }
            .navigationTitle("iCloud originals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("icloud.sheet")
    }
}

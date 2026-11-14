import SwiftUI

struct DataOnPhoneView: View {
    @EnvironmentObject private var trustState: TrustState
    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    @State private var showingForgetEverythingAlert = false
    @State private var items: [LocalDataItem] = []
    @State private var isLoading = true
    
    private let inventory: LocalDataInventory
    
    init(inventory: LocalDataInventory) {
        self.inventory = inventory
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Data on this iPhone").appText(.title)
                    .accessibilityIdentifier("data.title")
                
                ForEach(items) { item in
                    DataItemRow(item: item)
                        .accessibilityIdentifier("data.item.\(item.id.rawValue)")
                }
                
                Button("Forget everything") {
                    showingForgetEverythingAlert = true
                }
                .appText(.groupTitle)
                .foregroundStyle(Color.deleteAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("data.forget")
                .alert("Forget everything?", isPresented: $showingForgetEverythingAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Forget everything", role: .destructive) {
                        Task {
                            do {
                                try await inventory.forgetEverything()
                                // After forgetting everything, we should update the UI
                                await loadItems()
                            } catch {
                                // Handle error - for now we'll ignore since the requirement is to not implement this
                            }
                        }
                    }
                } message: {
                    Text("CleanSlate removes its saved checks, tray, activity and diagnostics. Your photos aren't touched.")
                        .appText(.body)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(Spacing.m)
        }
        .navigationTitle("Data on this iPhone")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadItems()
        }
    }
    
    private func loadItems() async {
        isLoading = true
        items = await inventory.items()
        isLoading = false
    }
}

private struct DataItemRow: View {
    let item: LocalDataItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.summary).appText(.groupTitle)
                    .foregroundStyle(Color.textPrimary)
                if let bytes = item.bytes {
                    Text(bytes.friendlyBytes).appText(.secondary)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("Unknown size").appText(.secondary)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            
            Spacer()
            
            Button("Delete") { }
                .appText(.secondary)
                .foregroundStyle(Color.actionPrimary)
                .frame(maxWidth: 60, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("data.delete.\(item.id.rawValue)")
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    DataOnPhoneView(inventory: LocalDataInventory(model: CleaningViewModel(library: PhotoKitLibraryClient.shared), diagnostics: DiagnosticsLog(directory: nil), activity: nil))
}
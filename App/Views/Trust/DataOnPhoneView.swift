import SwiftUI

struct DataOnPhoneView: View {
    @ObservedObject var inventory: LocalDataInventory
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingForgetAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Data on this iPhone")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                
                // Data items
                ForEach(Task { await inventory.items() }.value ?? []) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.summary)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            if let bytes = item.bytes {
                                Text(formatBytes(bytes))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Unknown size")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Delete") {
                            Task {
                                try await inventory.delete(item.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(item.bytes == nil)
                    }
                    .padding(.vertical, 8)
                }
                
                // Forget everything button
                Button("Forget everything") {
                    showingForgetAlert = true
                }
                .buttonStyle(.borderedProminent)
                .alert("Forget everything?", 
                       isPresented: $showingForgetAlert,
                       actions: {
                    Button("Cancel", role: .cancel) {}
                    Button("Forget everything", role: .destructive) {
                        Task {
                            try await inventory.forgetEverything()
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }, message: {
                    Text("CleanSlate removes its saved checks, tray, activity and diagnostics. Your photos aren't touched.")
                })
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return "\(bytes / 1024) KB"
        } else if bytes < 1024 * 1024 * 1024 {
            return "\(bytes / (1024 * 1024)) MB"
        } else {
            return "\(bytes / (1024 * 1024 * 1024)) GB"
        }
    }
}

#Preview {
    DataOnPhoneView(inventory: LocalDataInventory(model: CleaningViewModel(), diagnostics: nil, activity: nil))
}
import SwiftUI

struct DataOnPhoneView: View {
    @EnvironmentObject private var dataInventory: LocalDataInventory
    @State private var items: [LocalDataItem] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Data on this iPhone")
                        .appText(.title)
                        .accessibilityIdentifier("data.on.phone.title")
                    
                    List(items, id: \.id) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.summary)
                                    .appText(.body)
                                if let bytes = item.bytes {
                                    Text(bytes.friendlyBytes)
                                        .appText(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .contain)
                    }
                    .listStyle(PlainListStyle())
                }
                .padding()
            }
        }
        .navigationTitle("Data on iPhone")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadItems()
        }
    }
    
    private func loadItems() async {
        items = await dataInventory.items()
        isLoading = false
    }
}

#Preview {
    DataOnPhoneView()
}
import SwiftUI

/// Scan selection screen that allows users to choose from different scan scopes
struct ScanScopeView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Select scan scope")) {
                    ForEach(ScanScope.allCases.filter { $0 != .all }, id: \.self) { scope in
                        Button(action: {
                            model.setScanScope(scope)
                            isPresented = false
                            model.runScan(with: scope)
                        }) {
                            HStack {
                                Text(scope.rawValue)
                                Spacer()
                                Text(scope.estimatedTime)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section(header: Text("Library Statistics")) {
                    if let stats = model.libraryStatistics {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total items: \(stats.totalItems.formatted())")
                            Text("Local: \(stats.localItems.formatted()) (\(String(format: "%.1f", stats.localPercentage))%)")
                            Text("In iCloud: \(stats.cloudOnlyItems.formatted()) (\(String(format: "%.1f", stats.cloudOnlyPercentage))%)")
                        }
                    }
                }
            }
            .navigationTitle("Scan Library")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ScanScopeView(isPresented: .constant(false))
}
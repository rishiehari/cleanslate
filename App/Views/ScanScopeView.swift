import SwiftUI

/// The same bounded scan choices on phone, tablet and resized windows.
struct ScanScopeView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Start with a recent part of your library. Review available results while the scan continues. Nothing is deleted by scanning.")
                        .appText(.body)
                }
                Section("Choose what to check") {
                    ForEach(ScanScope.userScopes, id: \.self) { scope in
                        Button {
                            model.setScanScope(scope)
                            isPresented = false
                            model.scan(scope: scope)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack {
                                    Text(scope.title).appText(.groupTitle)
                                    if scope == .recentMonth { Text("Recommended").appText(.caption) }
                                }
                                Text(scope == .next1000 || scope == .start2000
                                     ? "Newest first. Scanning again rechecks these items; it does not advance to an older batch."
                                     : scope.description)
                                    .appText(.secondary).foregroundStyle(Color.textSecondary)
                                Text("Up to \((scope.maximumItems ?? 2_000).formatted()) items")
                                    .appText(.caption).foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isScanning)
                        .accessibilityIdentifier("scan.scope.\(scope)")
                    }
                }
                Section {
                    Text("Photos and videos stay on this device. iCloud originals are not downloaded unless you separately enable iCloud checking. Missing previews are reported as unavailable, not assumed to be in iCloud. Older photos remain untouched and outside this scan.")
                        .appText(.caption)
                }
            }
            .navigationTitle("Start a small scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("scan.scopePicker")
    }
}

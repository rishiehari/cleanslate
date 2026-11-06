import SwiftUI
import CleanSlateCore

struct ReviewGroupView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @Environment(\.dismiss) private var dismiss
    let group: PhotoReviewGroup

    @State private var selected: Set<String>
    @State private var manuallyReviewed: Set<String> = []
    @State private var showConfirm = false
    @State private var showDetails = false

    init(group: PhotoReviewGroup) {
        self.group = group
        let decision = SafetyPolicy.evaluate(group.coreCluster)
        // Only byte-verified exact duplicates with unprotected metadata may be selected.
        _selected = State(initialValue: decision.preselected)
    }

    private var eligibleDecision: ReviewDecision { SafetyPolicy.evaluate(group.coreCluster) }
    private var selectedBytes: Int64 {
        selected.reduce(Int64(0)) { $0 + (group.verifiedCandidateBytes[$1] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(group.kind.rawValue).font(.title2.bold())
                if group.kind == .similar {
                    Label("Potential visual similarity only. No calibrated redundancy probability. You must compare both images and manually select any photo to remove.", systemImage: "eye")
                        .font(.subheadline).foregroundStyle(.orange)
                } else {
                    Label("Original file resources verified equal. Photo metadata can still be meaningful: protected photos remain unselected.", systemImage: "checkmark.shield")
                        .font(.subheadline).foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep this photo").font(.headline)
                    PhotoThumbnailView(assetID: group.keeper.id, target: 760)
                        .frame(maxWidth: .infinity).frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    if group.keeper.record.flags.isEmpty {
                        Text("Suggested keeper, not guaranteed to be the best moment.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Protected keeper: \(group.keeper.record.flags.map(\.rawValue).sorted().joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                ForEach(group.candidates) { photo in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Compare before removing").font(.headline)
                        PhotoThumbnailView(assetID: photo.id, target: 760)
                            .frame(maxWidth: .infinity).frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        if let reason = eligibleDecision.blocked[photo.id] {
                            Label("Protected: \(reason.rawValue). Not selectable.", systemImage: "lock.fill")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else if group.kind == .exact {
                            Toggle("Select redundant copy for deletion", isOn: selectionBinding(photo.id))
                                .font(.subheadline)
                        } else {
                            Toggle("I compared both photos; select this for deletion", isOn: selectionBinding(photo.id))
                                .font(.subheadline)
                            Text("Look for different faces, expressions, moments, text, and anything unique. You are the final judge.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(photo.width) × \(photo.height) · \(group.verifiedCandidateBytes[photo.id]?.friendlyBytes ?? "Byte size unknown")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(13)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(selected.count) selected for Photos deletion")
                        .font(.headline)
                    Text("Verified candidate resource bytes: \(selectedBytes.friendlyBytes). This is not confirmed iCloud or device space recovered.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { showConfirm = true } label: {
                        Label("Review deletion of \(selected.count) photos", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || model.isDeleting)
                    Text("You will also receive an Apple Photos confirmation dialog. iCloud deletion syncs to other devices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .navigationTitle("Review photos")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Confirm deletion request?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue to Apple confirmation", role: .destructive) {
                Task {
                    let succeeded = await model.delete(group: group, selected: selected, manuallyReviewed: manuallyReviewed)
                    if succeeded { dismiss() }
                }
            }
        } message: {
            Text("Request deletion of \(selected.count) selected photos. The selected files may be removed from iCloud Photos and all synchronized devices. The Photos system will ask for final authorization.")
        }
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { checked in
            guard eligibleDecision.blocked[id] == nil else { return }
            if checked {
                selected.insert(id)
                if group.kind == .similar { manuallyReviewed.insert(id) }
            } else {
                selected.remove(id)
                manuallyReviewed.remove(id)
            }
        })
    }
}

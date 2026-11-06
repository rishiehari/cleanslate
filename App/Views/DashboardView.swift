import SwiftUI
import Photos

struct DashboardView: View {
    @EnvironmentObject private var model: CleaningViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showClearCache = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if model.authorization == .notDetermined || model.authorization == .denied || model.authorization == .restricted {
                        permissionCard
                    } else {
                        storageCard
                        progressCard
                        controls
                        if let message = model.statusMessage {
                            Label(message, systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let receipt = model.deletionReceipt {
                            Label(receipt, systemImage: "checkmark.shield")
                                .font(.footnote)
                                .padding(12)
                                .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        }
                        results
                    }
                    privacyFooter
                }
                .padding(18)
            }
            .navigationTitle("CleanSlate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear local feature cache", systemImage: "trash.slash") { showClearCache = true }
                        Button("Open Photos permissions", systemImage: "hand.raised") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } label: { Image(systemName: "gearshape") }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { model.refreshPermissions() }
            }
            .alert("Clear local index?", isPresented: $showClearCache) {
                Button("Cancel", role: .cancel) {}
                Button("Clear index", role: .destructive) { model.clearIndex() }
            } message: {
                Text("Removes CleanSlate's local feature cache. It will not modify your photos.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Keep the memories. Lose the copies.")
                .font(.title2.bold())
            Text("Free, private, on-device photo cleanup. No accounts, ads, or uploads to our servers.")
                .foregroundStyle(.secondary)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your Photos stay yours", systemImage: "lock.shield")
                .font(.headline)
            Text("CleanSlate analyzes accessible photos on this iPhone. The system will ask you to confirm deletions; the app cannot silently remove pictures.")
                .font(.subheadline)
            Button("Allow Photos access") { model.requestPermission() }
                .buttonStyle(.borderedProminent)
                .disabled(model.authorization == .restricted)
            if model.authorization == .denied {
                Text("Access is denied. Enable Photos permission in iPhone Settings.").font(.footnote)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verified potential logical savings")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(model.potentialVerifiedBytes.friendlyBytes)
                .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("File-resource bytes of verified exact copies only. This is NOT an iCloud quota or iPhone free-space measurement.")
                .font(.caption).foregroundStyle(.secondary)
            if model.authorization == .limited {
                Label("Limited Photos access: the scan covers only the photos you selected.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.phase.rawValue).font(.headline)
                Spacer()
                Text("\(Int(model.progress * 100))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: model.progress)
            HStack {
                Text("\(model.statistics.photosEnumerated) inventoried")
                Spacer()
                Text("\(model.statistics.cloudOnlyOrUnavailable) unavailable thumbnails")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("\(model.statistics.exactAssetsVerified) original resource sets verified · \(model.statistics.candidatePairsConsidered) candidate pairs checked")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                Button("Cancel scan", systemImage: "pause.fill") { model.stop() }
                    .buttonStyle(.bordered)
            } else {
                Button("Scan photos", systemImage: "sparkle.magnifyingglass") { model.scan() }
                    .buttonStyle(.borderedProminent)
                if model.statistics.photosEnumerated > 0 {
                    Button("Scan more", systemImage: "plus.magnifyingglass") { model.scanMore() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review groups").font(.title3.bold())
                Spacer()
                Text("\(model.groups.count)").foregroundStyle(.secondary)
            }
            if model.groups.isEmpty && model.phase == .finished {
                ContentUnavailableView("No matches in this scan", systemImage: "checkmark.circle",
                                       description: Text("No matching photos were confirmed within the current scanning coverage. This is not a guarantee that the entire library has no duplicates."))
            }
            ForEach(model.groups) { group in
                NavigationLink {
                    ReviewGroupView(group: group)
                } label: {
                    HStack(spacing: 12) {
                        PhotoThumbnailView(assetID: group.keeper.id, target: 80)
                            .frame(width: 75, height: 75)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.kind.rawValue).font(.subheadline.bold())
                            Text("\(group.candidates.count + 1) photos · \(group.estimatedVerifiedBytes.friendlyBytes) verified candidate bytes")
                                .font(.caption).foregroundStyle(.secondary)
                            if group.kind == .similar {
                                Text("Manual review only").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Important", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            Text("Deleting from iCloud Photos also deletes that item on other synchronized devices. Recently Deleted may retain recoverable items. Actual free-space gains can differ from file sizes, especially with Optimize iPhone Storage.")
            Text("This version uses a bounded, partial local scan. It cannot analyze cloud-only originals without permission to download them. Similar-photo ranking is experimental and is never auto-selected for deletion.")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.top, 16)
    }
}

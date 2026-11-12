import SwiftUI
import CleanSlateCore

/// "Never suggest": the user picks photos (or a date range) CleanSlate must never propose for deletion.
/// Protected here, not in Apple Photos. Nothing is shown as protected until the rule is saved (N05).
struct ProtectSheet: View {
    enum Scope: String, CaseIterable, Identifiable {
        case photos = "Just these photos"
        case dates = "Photos from these dates"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: CleaningViewModel
    @EnvironmentObject private var tray: DeletionTray
    @Environment(\.dismiss) private var dismiss

    /// The photos on offer (empty when the sheet was opened to add a date range).
    let assetIDs: [String]
    @State private var chosen: Set<String>
    @State private var scope: Scope
    @State private var start: Date
    @State private var end: Date
    @State private var saving = false
    @State private var errorText: String?
    @State private var coverage: Int?

    init(assetIDs: [String], preselected: Set<String>, startWithDates: Bool = false) {
        self.assetIDs = assetIDs
        _chosen = State(initialValue: preselected)
        _scope = State(initialValue: startWithDates || assetIDs.isEmpty ? .dates : .photos)
        _start = State(initialValue: Date())
        _end = State(initialValue: Date())
    }

    private var service: ProtectionRuleService? { model.protectionService }
    private var datesByID: [String: Date] {
        Dictionary(uniqueKeysWithValues: assetIDs.compactMap { id in
            model.library.snapshot(id: id, inspectAlbums: false)?.capturedAt.map { (id, $0) }
        })
    }
    private var rangeIsValid: Bool { Calendar.current.startOfDay(for: end) >= Calendar.current.startOfDay(for: start) }
    private var canSave: Bool {
        guard !saving, service != nil else { return false }
        return scope == .photos ? !chosen.isEmpty : rangeIsValid
    }

    var body: some View {
        NavigationStack {
            Form {
                if !assetIDs.isEmpty {
                    Section {
                        Picker("What to protect", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("protect.scope")
                    }
                }
                if scope == .photos { photosSection } else { datesSection }
                Section {
                    Text("CleanSlate won't suggest deleting these on this device. Apple Photos isn't changed.")
                        .appText(.secondary).foregroundStyle(Color.textSecondary)
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .appText(.secondary).foregroundStyle(Color.textPrimary)
                            .accessibilityIdentifier("protect.error")
                    }
                }
            }
            .navigationTitle("Never suggest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)             // Escape on a hardware keyboard
                        .accessibilityIdentifier("protect.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        Text("Saving…").appText(.secondary).accessibilityIdentifier("protect.saving")
                    } else {
                        Button("Protect") { save() }
                            .disabled(!canSave)
                            .accessibilityIdentifier("protect.confirm")
                    }
                }
            }
            .task { prefillDates() }
            .task(id: coverageKey) { await refreshCoverage() }
        }
        .interactiveDismissDisabled(saving)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protect.sheet")
    }

    private var photosSection: some View {
        Section("Photos") {
            ForEach(assetIDs, id: \.self) { id in
                Toggle(isOn: Binding(get: { chosen.contains(id) },
                                     set: { if $0 { chosen.insert(id) } else { chosen.remove(id) } })) {
                    HStack(spacing: Spacing.m) {
                        PhotoThumbnailView(assetID: id, target: 160)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.s))
                            .accessibilityHidden(true)
                        Text(datesByID[id].map { "Photo from \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Photo")
                            .appText(.body)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("protect.photo.\(id)")
            }
        }
    }

    private var datesSection: some View {
        Section {
            DatePicker("From", selection: $start, displayedComponents: .date)
                .accessibilityIdentifier("protect.range.start")
            DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                .accessibilityIdentifier("protect.range.end")
            if let coverage {
                Text("\(coverage.formatted()) checked \(coverage == 1 ? "photo" : "photos") in this range")
                    .appText(.secondary).foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("protect.coverage")
            }
            if !rangeIsValid {
                Text("Pick an end date that isn't before the start date.").appText(.secondary).foregroundStyle(Color.textPrimary)
            }
        } header: {
            Text("Dates")
        } footer: {
            Text("Photos with no date are not covered by a date range.")
        }
    }

    // MARK: Actions

    private var coverageKey: String { "\(scope.rawValue)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)" }

    private func prefillDates() {
        let picked = chosen.isEmpty ? Array(datesByID.values) : chosen.compactMap { datesByID[$0] }
        guard let first = picked.min(), let last = picked.max() else { return }
        start = first; end = last
    }

    private func refreshCoverage() async {
        guard scope == .dates, rangeIsValid,
              let from = Self.localDay(start), let to = Self.localDay(end),
              let interval = ProtectionDateResolver.interval(start: from, end: to, timeZoneID: TimeZone.current.identifier) else {
            coverage = nil
            return
        }
        coverage = await model.store.protectedRangeIndexedCount(start: interval.start, end: interval.endExclusive)
    }

    private static func localDay(_ date: Date) -> LocalDay? {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return LocalDay(year: y, month: m, day: d)
    }

    private func save() {
        guard let service, canSave else { return }
        saving = true
        errorText = nil
        Task {
            let before = Set(service.rules.map(\.id))
            let ok: Bool
            switch scope {
            case .photos:
                ok = await service.protect(assetIDs: Array(chosen))
            case .dates:
                if let from = Self.localDay(start), let to = Self.localDay(end), from <= to {
                    ok = await service.protect(range: from...to)
                } else {
                    service.reportInvalidRange(); ok = false
                }
            }
            saving = false
            guard ok else {
                errorText = service.lastError ?? "Couldn't save your protection rule. Nothing was changed."
                return
            }
            let created = Set(service.rules.map(\.id)).subtracting(before)
            tray.showToast("Protected. CleanSlate won't suggest it.") {
                Task { for id in created { await service.remove(ruleID: id) } }      // Undo removes the rule, never a photo
            }
            dismiss()
        }
    }
}

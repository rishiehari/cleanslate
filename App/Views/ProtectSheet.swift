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
    @State private var datesByID: [String: Date] = [:]
    @State private var loadingDates: Bool
    @State private var ruleTimeZoneID = TimeZone.current.identifier

    init(assetIDs: [String], preselected: Set<String>, startWithDates: Bool = false) {
        self.assetIDs = assetIDs
        _loadingDates = State(initialValue: !assetIDs.isEmpty)
        _chosen = State(initialValue: preselected)
        _scope = State(initialValue: startWithDates || assetIDs.isEmpty ? .dates : .photos)
        _start = State(initialValue: Date())
        _end = State(initialValue: Date())
    }

    private var service: ProtectionRuleService? { model.protectionService }
    private var rangeIsValid: Bool {
        guard let from = localDay(start), let to = localDay(end) else { return false }
        return from <= to
    }
    private var canSave: Bool {
        guard !saving, !loadingDates, service != nil else { return false }
        return scope == .photos ? !chosen.isEmpty : rangeIsValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("CleanSlate won't suggest deleting these on this device. Apple Photos isn't changed.")
                        .appText(.secondary).foregroundStyle(Color.textPrimary)
                }
                if !assetIDs.isEmpty {
                    Section {
                        Picker("What to protect", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .disabled(loadingDates)
                        .accessibilityIdentifier("protect.scope")
                    }
                }
                if scope == .photos { photosSection } else { datesSection }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .appText(.secondary).foregroundStyle(Color.textPrimary)
                            .accessibilityIdentifier("protect.error")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("protect.sheet")
            .scrollEdgeEffectHidden(true, for: .bottom)
            .environment(\.timeZone, TimeZone(identifier: ruleTimeZoneID) ?? .current)
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
            .task {
                guard let dates = await ProtectionSheetDates.load(ids: assetIDs, snapshot: {
                    model.library.snapshot(id: $0, inspectAlbums: false)
                }) else { return }
                datesByID = dates
                prefillDates()
                loadingDates = false
            }
            .task(id: coverageKey) { await refreshCoverage() }
        }
        .interactiveDismissDisabled(saving)
        .presentationSizing(.page)
    }

    private var photosSection: some View {
        Section("Photos") {
            if loadingDates { ProgressView("Reading photo dates…") }
            ForEach(Array(assetIDs.enumerated()), id: \.element) { index, id in
                Toggle(isOn: Binding(get: { chosen.contains(id) },
                                     set: { if $0 { chosen.insert(id) } else { chosen.remove(id) } })) {
                    HStack(spacing: Spacing.m) {
                        PhotoThumbnailView(assetID: id, target: 160)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.s))
                            .accessibilityHidden(true)
                        Text(datesByID[id].map {
                            "Photo \(index + 1) of \(assetIDs.count)\n\($0.formatted(date: .abbreviated, time: .omitted))"
                        } ?? "Photo \(index + 1) of \(assetIDs.count)")
                            .appText(.body).foregroundStyle(Color.textPrimary)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Photo \(index + 1) of \(assetIDs.count)")
                .accessibilityHint(datesByID[id].map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Photo date unavailable")
                .accessibilityIdentifier("protect.photo.\(id)")
            }
        }
    }

    private var datesSection: some View {
        Section {
            DatePicker("From", selection: $start, displayedComponents: .date)
                .disabled(loadingDates)
                .accessibilityIdentifier("protect.range.start")
            DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                .disabled(loadingDates)
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
              let from = localDay(start), let to = localDay(end),
              let interval = ProtectionDateResolver.interval(start: from, end: to, timeZoneID: ruleTimeZoneID) else {
            coverage = nil
            return
        }
        coverage = nil
        let count = await model.store.protectedRangeIndexedCount(start: interval.start, end: interval.endExclusive)
        guard !Task.isCancelled else { return }
        coverage = count
    }

    private func localDay(_ date: Date) -> LocalDay? {
        ProtectionDateResolver.localDay(containing: date, timeZoneID: ruleTimeZoneID)
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
                if let from = localDay(start), let to = localDay(end), from <= to {
                    ok = await service.protect(range: from...to, timeZoneID: ruleTimeZoneID)
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

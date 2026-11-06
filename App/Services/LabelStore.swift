import Foundation
import CleanSlateCore

/// Label mode: lets a tester say what each look-alike photo really is, to measure the app's accuracy (Step 9).
/// Only offered in debug and TestFlight builds. Labels stay on the phone until the tester exports them, and the
/// export is derived numbers only (see `EvaluationExport`).
@MainActor
final class LabelStore: ObservableObject {
    struct Entry: Codable, Equatable {
        var assetID: String
        var groupID: String
        var verdict: String
        var best: Bool
        var flags: [String]
        var hamming: Int?
        var pixelCount: Int64
    }

    static let enabledKey = "labelmode.enabled"
    static let correctionsKey = "suggestions.corrected"

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Self.enabledKey) } }
    @Published private(set) var entries: [Entry] = []
    /// How many times the user told us a suggestion was wrong. Local only, never transmitted.
    @Published private(set) var corrections: Int

    private let defaults: UserDefaults
    private let fileURL: URL?

    /// Label mode is offered in debug builds and TestFlight (sandbox receipt), never in App Store builds.
    static var isAvailableInThisBuild: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    init(defaults: UserDefaults = .standard, fileURL: URL? = nil) {
        self.defaults = defaults
        self.fileURL = fileURL
        self.isEnabled = Self.isAvailableInThisBuild && defaults.bool(forKey: Self.enabledKey)
        self.corrections = defaults.integer(forKey: Self.correctionsKey)
        if let fileURL, let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([Entry].self, from: data) { entries = saved }
    }

    static func defaultURL() -> URL? {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("labels.json")
    }

    func verdict(for assetID: String, in groupID: String) -> RawLabel.Verdict? {
        entries.first { $0.assetID == assetID && $0.groupID == groupID }.flatMap { RawLabel.Verdict(rawValue: $0.verdict) }
    }

    func isBest(_ assetID: String, in groupID: String) -> Bool {
        entries.contains { $0.assetID == assetID && $0.groupID == groupID && $0.best }
    }

    func set(_ verdict: RawLabel.Verdict, for photo: PhotoSnapshot, in groupID: String, hamming: Int? = nil) {
        update(photo, groupID, hamming) { $0.verdict = verdict.rawValue }
    }

    /// One best shot per group: choosing a new one clears the previous.
    func setBest(_ photo: PhotoSnapshot, in groupID: String) {
        for index in entries.indices where entries[index].groupID == groupID { entries[index].best = false }
        update(photo, groupID, nil) { $0.best = true }
    }

    func recordCorrection() {
        corrections += 1
        defaults.set(corrections, forKey: Self.correctionsKey)
    }

    func clear() { entries = []; persist() }

    /// Writes the anonymous export to a temporary file for the share sheet. Nothing is sent anywhere.
    func exportFile() throws -> URL {
        let labels = entries.compactMap { entry -> RawLabel? in
            guard let verdict = RawLabel.Verdict(rawValue: entry.verdict) else { return nil }
            return RawLabel(assetID: entry.assetID, groupID: entry.groupID, verdict: verdict, isBestShot: entry.best, flags: entry.flags,
                            hammingToKeeper: entry.hamming, pixelCount: entry.pixelCount)
        }
        let data = try JSONEncoder().encode(EvaluationExport.make(from: labels))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleanslate-labels-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func update(_ photo: PhotoSnapshot, _ groupID: String, _ hamming: Int?, _ change: (inout Entry) -> Void) {
        if let index = entries.firstIndex(where: { $0.assetID == photo.id && $0.groupID == groupID }) {
            change(&entries[index])
        } else {
            var entry = Entry(assetID: photo.id, groupID: groupID, verdict: RawLabel.Verdict.unsure.rawValue, best: false,
                              flags: photo.record.flags.map(\.rawValue).sorted(), hamming: hamming, pixelCount: photo.pixelCount)
            change(&entry)
            entries.append(entry)
        }
        persist()
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = fileURL; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

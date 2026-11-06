#if DEBUG
import Foundation
import Photos
import UIKit
import CryptoKit
import CleanSlateCore

/// In-memory stand-in for the Photos library. Scriptable revisions, flags, digests,
/// availability and deletion outcomes; records every delete request.
@MainActor
final class FakePhotoLibrary: PhotoLibraryClient {
    enum DeleteOutcome { case success, userCancelled, failure }

    struct Asset {
        var snapshot: PhotoSnapshot
        /// nil = original not available locally (e.g. iCloud only).
        var digests: [ResourceDigest]?
        /// What a download would yield (only returned when the caller allows network access).
        var cloudDigests: [ResourceDigest]?
        /// Drives the deterministic thumbnail so copies look identical and similar shots differ slightly.
        var look: String = ""
    }

    var assets: [String: Asset] = [:]
    var authorization: PHAuthorizationStatus = .authorized
    var authorizationAfterDelete: PHAuthorizationStatus?
    var deleteOutcome: DeleteOutcome = .success
    private(set) var deleteCalls: [[String]] = []
    private(set) var digestCalls: [String] = []
    /// Every digest request with its `allowNetwork` flag, in order.
    private(set) var digestRequests: [(id: String, allowNetwork: Bool)] = []
    private var nextTimestamp: Int64 = 1_700_000_000
    /// Local file sizes for `verifiedSize` (absent = not local).
    var sizes: [String: Int64] = [:]
    /// Called when hashing of an asset begins; lets a test mutate the library mid-flight.
    var onDigests: ((String) -> Void)?
    private var handlers: [UUID: @MainActor () -> Void] = [:]
    /// Called right before the delete request is applied; lets a test change things at the last moment.
    var beforeDelete: (() -> Void)?

    // MARK: Test helpers

    static func digest(_ seed: String, type: String = "photo", bytes: Int64 = 1_000) -> ResourceDigest {
        let hex = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
        return ResourceDigest(type: type, byteCount: bytes, sha256: hex)
    }

    /// `at` is the creation time (seconds). Assets that should look like copies of each other pass the
    /// same `at`; by default every asset gets its own timestamp so nothing is bucketed by accident.
    func add(_ id: String, revision: String = "v1", flags: Set<PreservationFlag> = [],
             content: String? = nil, bytes: Int64 = 1_000, at: Int64? = nil, resources: [ResourceDigest]? = nil,
             subtypes: UInt = 0, isVideo: Bool = false, duration: Double = 0, size: Int64? = nil) {
        let record = AssetRecord(id: id, revision: revision, flags: flags)
        nextTimestamp += 1_000
        let time = at ?? nextTimestamp
        let snapshot = PhotoSnapshot(id: id, record: record, capturedAt: Date(timeIntervalSince1970: TimeInterval(time)),
                                     burstID: nil, width: 4032, height: 3024, originalFilename: "IMG_\(id).HEIC",
                                     isVideo: isVideo, durationSeconds: duration, subtypes: subtypes)
        if let size { sizes[id] = size }
        assets[id] = Asset(snapshot: snapshot, digests: resources ?? [Self.digest(content ?? id, bytes: bytes)], look: content ?? id)
        recordChange(changed: [id])
    }

    func update(_ id: String, revision: String? = nil, flags: Set<PreservationFlag>? = nil) {
        guard var asset = assets[id] else { return }
        let old = asset.snapshot.record
        let record = AssetRecord(id: id, revision: revision ?? old.revision, flags: flags ?? old.flags)
        asset.snapshot = PhotoSnapshot(id: id, record: record, capturedAt: asset.snapshot.capturedAt,
                                       burstID: asset.snapshot.burstID, width: asset.snapshot.width,
                                       height: asset.snapshot.height, originalFilename: asset.snapshot.originalFilename,
                                       isVideo: asset.snapshot.isVideo, durationSeconds: asset.snapshot.durationSeconds,
                                       subtypes: asset.snapshot.subtypes)
        assets[id] = asset
        recordChange(changed: [id])
    }

    func simulateExternalChange() { handlers.values.forEach { $0() } }

    // MARK: PhotoLibraryClient

    func requestAccess() async -> PHAuthorizationStatus { authorization }

    func inventoryPage(offset: Int, limit: Int) -> (photos: [PhotoSnapshot], total: Int) {
        pageRequests.append(offset)
        let all = assets.values.map(\.snapshot).sorted {
            ($0.capturedAt ?? .distantPast, $1.id) > ($1.capturedAt ?? .distantPast, $0.id)
        }
        guard offset < all.count else { return ([], all.count) }
        return (Array(all[offset..<min(all.count, offset + limit)]), all.count)
    }

    // MARK: Change tracking (token = a counter into `changeLog`)
    private(set) var pageRequests: [Int] = []
    private var changeLog: [(changed: Set<String>, deleted: Set<String>)] = []
    var changeTokensExpired = false
    var changeTrackingAvailable = true
    private(set) var changeQueries = 0

    func recordChange(changed: Set<String> = [], deleted: Set<String> = []) { changeLog.append((changed, deleted)) }

    func currentChangeToken() -> Data? {
        changeTrackingAvailable ? Data(String(changeLog.count).utf8) : nil
    }

    func changes(since token: Data) -> LibraryChangeResult {
        changeQueries += 1
        guard changeTrackingAvailable, let text = String(data: token, encoding: .utf8), let index = Int(text) else { return .unavailable }
        if changeTokensExpired { return .tokenExpired }
        let slice = changeLog.dropFirst(min(index, changeLog.count))
        var changed: Set<String> = [], deleted: Set<String> = []
        for entry in slice { changed.formUnion(entry.changed); deleted.formUnion(entry.deleted) }
        changed.subtract(deleted)
        return .changes(LibraryChangeSet(changedIDs: changed, deletedIDs: deleted, newToken: Data(String(changeLog.count).utf8)))
    }

    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot? { assets[id]?.snapshot }

    func thumbnail(_ id: String, target: CGFloat) async -> UIImage? {
        guard !disableThumbnails, let asset = assets[id] else { return nil }
        return Self.renderScene(look: asset.look)
    }

    var disableThumbnails = false

    /// A small deterministic "photo": sky gradient, sun and hills, tinted by `look`.
    static func renderScene(look: String) -> UIImage {
        let seed = look.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) % 360 }
        let hue = CGFloat(seed) / 360
        let size = CGSize(width: 320, height: 240)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1).cgColor,
                          UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.35, brightness: 0.75, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor(white: 1, alpha: 0.9).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 220, y: 30, width: 46, height: 46))
            UIColor(hue: hue, saturation: 0.6, brightness: 0.35, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: -40, y: 150, width: 260, height: 160))
            ctx.cgContext.fillEllipse(in: CGRect(x: 120, y: 175, width: 260, height: 140))
        }
    }

    func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest] {
        digestCalls.append(id)
        digestRequests.append((id, allowNetwork))
        onDigests?(id)
        await Task.yield()
        guard let asset = assets[id] else { throw LibraryResourceError.notAccessible }
        if let local = asset.digests { return local }
        if allowNetwork, let cloud = asset.cloudDigests { return cloud }
        throw LibraryResourceError.notAccessible
    }

    func verifiedSize(id: String) async -> Int64? { sizes[id] }

    /// Assets placed in user albums (tests).
    var albumMemberIDs: Set<String> = []
    func userAlbumAssetIDs() -> Set<String> { albumMemberIDs }

    func delete(ids: [String], expectedRevisions: [String: String]) async throws {
        beforeDelete?()
        for id in ids {
            guard let asset = assets[id] else { throw LibraryResourceError.notAccessible }
            guard expectedRevisions[id] == asset.snapshot.record.revision else { throw LibraryResourceError.changed }
        }
        deleteCalls.append(ids.sorted())
        switch deleteOutcome {
        case .userCancelled: throw PHPhotosError(.userCancelled)
        case .failure: throw PHPhotosError(.internalError)
        case .success:
            for id in ids { assets[id] = nil }
            recordChange(deleted: Set(ids))
            if let after = authorizationAfterDelete { authorization = after }
        }
    }

    func observeChanges(_ onChange: @escaping @MainActor () -> Void) -> ChangeSubscription {
        let id = UUID()
        handlers[id] = onChange
        return ChangeSubscription { [weak self] in Task { @MainActor in self?.handlers[id] = nil } }
    }
}

/// Builds a review group out of fake-library assets.
extension FakePhotoLibrary {
    /// Deterministic data for UI tests and screenshots (never used in release builds).
    static func uiTestScenario(authorization: PHAuthorizationStatus = .authorized) -> (library: FakePhotoLibrary, groups: [PhotoReviewGroup], standalone: [StandaloneItem]) {
        let lib = FakePhotoLibrary()
        lib.authorization = authorization
        var groups: [PhotoReviewGroup] = []
        for n in 1...3 {
            lib.add("ex\(n)-keep", content: "exact\(n)", bytes: Int64(n) * 2_400_000, at: Int64(1_000 * n))
            lib.add("ex\(n)-copy", content: "exact\(n)", bytes: Int64(n) * 2_400_000, at: Int64(1_000 * n))
            groups.append(lib.exactGroup(keeper: "ex\(n)-keep", copies: ["ex\(n)-copy"], bytes: Int64(n) * 2_400_000))
        }
        // A copy that only exists in iCloud: found only after the user opts in to iCloud checking.
        lib.add("ic-local", content: "icloud", bytes: 3_000_000, at: 9_000)
        lib.add("ic-remote", content: "icloud", bytes: 3_000_000, at: 9_000)
        let remoteDigests = lib.assets["ic-remote"]?.digests
        lib.assets["ic-remote"]?.cloudDigests = remoteDigests
        lib.assets["ic-remote"]?.digests = nil
        lib.add("sim1-a", content: "sim1a"); lib.add("sim1-b", content: "sim1b"); lib.add("sim1-c", content: "sim1c")
        groups.append(lib.similarGroup(keeper: "sim1-a", copies: ["sim1-b", "sim1-c"]))
        // Keeper-less categories.
        let screenshotBit: UInt = 1 << 2, recordingBit: UInt = 1 << 19
        let day: Int64 = 86_400
        for n in 1...4 {
            lib.add("ss\(n)", content: "ss\(n)", at: 1_700_000_000 - Int64(n) * 60 * day, subtypes: screenshotBit, size: Int64(n) * 400_000)
        }
        lib.add("ss-recent", content: "ssr", at: Int64(Date().timeIntervalSince1970) - 3_600, subtypes: screenshotBit, size: 300_000)
        lib.add("ss-fav", content: "ssf", subtypes: screenshotBit, size: 500_000)
        lib.update("ss-fav", flags: [.favorite])
        lib.add("rec1", content: "rec", at: 1_690_000_000, subtypes: recordingBit, isVideo: true, duration: 95, size: 80_000_000)
        lib.add("big1", content: "big1", at: 1_680_000_000, isVideo: true, duration: 420, size: 700_000_000)
        lib.add("big2", content: "big2", at: 1_681_000_000, isVideo: true, duration: 120, size: 120_000_000)
        lib.add("small1", content: "small1", at: 1_682_000_000, isVideo: true, duration: 20, size: 10_000_000)
        lib.add("vex-a", content: "vexact", at: 1_683_000_000, isVideo: true, duration: 33, size: 55_000_000)
        lib.add("vex-b", content: "vexact", at: 1_683_000_000, isVideo: true, duration: 33, size: 55_000_000)
        groups.append(lib.exactGroup(keeper: "vex-a", copies: ["vex-b"], bytes: 55_000_000))
        lib.add("fav-keep", content: "fav"); lib.add("fav-copy", content: "fav"); lib.update("fav-copy", flags: [.favorite])
        groups.append(lib.exactGroup(keeper: "fav-keep", copies: ["fav-copy"], bytes: 900_000))
        let standalone = lib.assets.values.map(\.snapshot)
            .filter { $0.isScreenshot || $0.isVideo }
            .map { StandaloneItem(snapshot: $0, verifiedBytes: lib.sizes[$0.id]) }
        return (lib, groups, standalone)
    }

    func exactGroup(keeper: String, copies: [String], bytes: Int64 = 1_000) -> PhotoReviewGroup {
        group(kind: .exact, keeper: keeper, copies: copies, relation: .exactResources, equal: true, bytes: bytes)
    }

    func similarGroup(keeper: String, copies: [String]) -> PhotoReviewGroup {
        group(kind: .similar, keeper: keeper, copies: copies, relation: .visuallySimilar, equal: false, bytes: 0)
    }

    private func group(kind: GroupKind, keeper: String, copies: [String], relation: PairRelation,
                       equal: Bool, bytes: Int64) -> PhotoReviewGroup {
        PhotoReviewGroup(
            id: "test-\(keeper)", kind: kind,
            keeper: assets[keeper]!.snapshot,
            candidates: copies.map { assets[$0]!.snapshot },
            evidence: copies.map { PairEvidence(first: keeper, second: $0, relation: relation, completeResourceEquality: equal) },
            verifiedCandidateBytes: kind == .exact ? Dictionary(uniqueKeysWithValues: copies.map { ($0, bytes) }) : [:])
    }
}
#endif

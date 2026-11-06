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
        /// Drives the deterministic thumbnail so copies look identical and similar shots differ slightly.
        var look: String = ""
    }

    var assets: [String: Asset] = [:]
    var authorization: PHAuthorizationStatus = .authorized
    var authorizationAfterDelete: PHAuthorizationStatus?
    var deleteOutcome: DeleteOutcome = .success
    private(set) var deleteCalls: [[String]] = []
    private(set) var digestCalls: [String] = []
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

    func add(_ id: String, revision: String = "v1", flags: Set<PreservationFlag> = [],
             content: String? = nil, bytes: Int64 = 1_000) {
        let record = AssetRecord(id: id, revision: revision, flags: flags)
        let snapshot = PhotoSnapshot(id: id, record: record, capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                     burstID: nil, width: 4032, height: 3024)
        assets[id] = Asset(snapshot: snapshot, digests: [Self.digest(content ?? id, bytes: bytes)], look: content ?? id)
    }

    func update(_ id: String, revision: String? = nil, flags: Set<PreservationFlag>? = nil) {
        guard var asset = assets[id] else { return }
        let old = asset.snapshot.record
        let record = AssetRecord(id: id, revision: revision ?? old.revision, flags: flags ?? old.flags)
        asset.snapshot = PhotoSnapshot(id: id, record: record, capturedAt: asset.snapshot.capturedAt,
                                       burstID: asset.snapshot.burstID, width: asset.snapshot.width,
                                       height: asset.snapshot.height)
        assets[id] = asset
    }

    func simulateExternalChange() { handlers.values.forEach { $0() } }

    // MARK: PhotoLibraryClient

    func requestAccess() async -> PHAuthorizationStatus { authorization }

    func inventory(limit: Int) -> (photos: [PhotoSnapshot], totalVisible: Int) {
        let all = assets.values.map(\.snapshot).sorted { $0.id < $1.id }
        return (Array(all.prefix(limit)), all.count)
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

    func digests(id: String) async throws -> [ResourceDigest] {
        digestCalls.append(id)
        onDigests?(id)
        await Task.yield()
        guard let asset = assets[id], let digests = asset.digests else { throw LibraryResourceError.notAccessible }
        return digests
    }

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
    static func uiTestScenario(authorization: PHAuthorizationStatus = .authorized) -> (library: FakePhotoLibrary, groups: [PhotoReviewGroup]) {
        let lib = FakePhotoLibrary()
        lib.authorization = authorization
        var groups: [PhotoReviewGroup] = []
        for n in 1...3 {
            lib.add("ex\(n)-keep", content: "exact\(n)", bytes: Int64(n) * 2_400_000)
            lib.add("ex\(n)-copy", content: "exact\(n)", bytes: Int64(n) * 2_400_000)
            groups.append(lib.exactGroup(keeper: "ex\(n)-keep", copies: ["ex\(n)-copy"], bytes: Int64(n) * 2_400_000))
        }
        lib.add("sim1-a", content: "sim1a"); lib.add("sim1-b", content: "sim1b"); lib.add("sim1-c", content: "sim1c")
        groups.append(lib.similarGroup(keeper: "sim1-a", copies: ["sim1-b", "sim1-c"]))
        lib.add("fav-keep", content: "fav"); lib.add("fav-copy", content: "fav"); lib.update("fav-copy", flags: [.favorite])
        groups.append(lib.exactGroup(keeper: "fav-keep", copies: ["fav-copy"], bytes: 900_000))
        return (lib, groups)
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

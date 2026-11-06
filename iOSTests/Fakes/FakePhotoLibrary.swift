import Foundation
import Photos
import UIKit
import CryptoKit
import CleanSlateCore
@testable import CleanSlate

/// In-memory stand-in for the Photos library. Scriptable revisions, flags, digests,
/// availability and deletion outcomes; records every delete request.
@MainActor
final class FakePhotoLibrary: PhotoLibraryClient {
    enum DeleteOutcome { case success, userCancelled, failure }

    struct Asset {
        var snapshot: PhotoSnapshot
        /// nil = original not available locally (e.g. iCloud only).
        var digests: [ResourceDigest]?
    }

    var assets: [String: Asset] = [:]
    var authorization: PHAuthorizationStatus = .authorized
    var authorizationAfterDelete: PHAuthorizationStatus?
    var deleteOutcome: DeleteOutcome = .success
    private(set) var deleteCalls: [[String]] = []
    private(set) var digestCalls: [String] = []
    /// Called when hashing of an asset begins; lets a test mutate the library mid-flight.
    var onDigests: ((String) -> Void)?
    private var changeHandler: (@MainActor () -> Void)?

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
        assets[id] = Asset(snapshot: snapshot, digests: [Self.digest(content ?? id, bytes: bytes)])
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

    func simulateExternalChange() { changeHandler?() }

    // MARK: PhotoLibraryClient

    func requestAccess() async -> PHAuthorizationStatus { authorization }

    func inventory(limit: Int) -> (photos: [PhotoSnapshot], totalVisible: Int) {
        let all = assets.values.map(\.snapshot).sorted { $0.id < $1.id }
        return (Array(all.prefix(limit)), all.count)
    }

    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot? { assets[id]?.snapshot }

    func thumbnail(_ id: String, target: CGFloat) async -> UIImage? { nil }

    func digests(id: String) async throws -> [ResourceDigest] {
        digestCalls.append(id)
        onDigests?(id)
        await Task.yield()
        guard let asset = assets[id], let digests = asset.digests else { throw LibraryResourceError.notAccessible }
        return digests
    }

    func delete(ids: [String]) async throws {
        deleteCalls.append(ids.sorted())
        switch deleteOutcome {
        case .userCancelled: throw PHPhotosError(.userCancelled)
        case .failure: throw PHPhotosError(.internalError)
        case .success:
            for id in ids { assets[id] = nil }
            if let after = authorizationAfterDelete { authorization = after }
        }
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () -> Void) { changeHandler = onChange }
    func stopObservingChanges() { changeHandler = nil }
}

/// Builds a review group out of fake-library assets.
extension FakePhotoLibrary {
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

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

    /// How a fake photo is drawn. Shots with the same `base` are "the same scene"; the other fields model a small camera
    /// pan, an exposure change and an extra person entering the frame. `FakeVisualAnalyzer` reads it back from the image.
    struct RenderSpec: Hashable, Sendable {
        var base: Int
        var shiftX: Int = 0
        var exposure: Double = 1
        var extraSubject = false

        /// Carried on the rendered `UIImage.accessibilityIdentifier` so a fake Vision can recover it.
        var token: String { "spec|\(base)|\(shiftX)|\(exposure)|\(extraSubject)" }
        static func parse(_ token: String) -> RenderSpec? {
            let parts = token.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5, parts[0] == "spec", let base = Int(parts[1]), let shift = Int(parts[2]),
                  let exposure = Double(parts[3]), let extra = Bool(parts[4]) else { return nil }
            return RenderSpec(base: base, shiftX: shift, exposure: exposure, extraSubject: extra)
        }
    }

    struct Asset {
        var snapshot: PhotoSnapshot
        /// nil = original not available locally (e.g. iCloud only).
        var digests: [ResourceDigest]?
        /// What a download would yield (only returned when the caller allows network access).
        var cloudDigests: [ResourceDigest]?
        /// Drives the deterministic thumbnail so copies look identical and similar shots differ slightly.
        var look: String = ""
        /// Bulk (scale test) assets compute their digest on demand instead of storing millions of them.
        var lazyContent: String?
        /// When set, the thumbnail is drawn from this spec instead of `look`.
        var spec: RenderSpec?
    }

    var assets: [String: Asset] = [:] { didSet { sortedCache = nil } }
    private var sortedCache: [PhotoSnapshot]?
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
             subtypes: UInt = 0, isVideo: Bool = false, duration: Double = 0, size: Int64? = nil, burst: String? = nil, look: String? = nil, spec: RenderSpec? = nil) {
        let record = AssetRecord(id: id, revision: revision, flags: flags)
        nextTimestamp += 1_000
        let time = at ?? nextTimestamp
        let snapshot = PhotoSnapshot(id: id, record: record, capturedAt: Date(timeIntervalSince1970: TimeInterval(time)),
                                     burstID: burst, width: 4032, height: 3024, originalFilename: "IMG_\(id).HEIC",
                                     isVideo: isVideo, durationSeconds: duration, subtypes: subtypes)
        if let size { sizes[id] = size }
        assets[id] = Asset(snapshot: snapshot, digests: resources ?? [Self.digest(content ?? id, bytes: bytes)], look: look ?? content ?? id)
        assets[id]?.spec = spec
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

    /// Fast bulk population for scale tests: `count` unique assets plus `plantedExactPairs` byte-identical pairs
    /// (same time, size and content). No change-log entries, no per-asset hashing up front.
    func addBulk(count: Int, plantedExactPairs: Int) {
        var table = assets
        table.reserveCapacity(count + plantedExactPairs)
        func make(_ id: String, at: Int64, content: String) -> Asset {
            let record = AssetRecord(id: id, revision: "v1", flags: [])
            let snap = PhotoSnapshot(id: id, record: record, capturedAt: Date(timeIntervalSince1970: TimeInterval(at)), burstID: nil,
                                     width: 4000 + Int(at % 5), height: 3000 + Int(at % 7), originalFilename: "IMG_\(id).HEIC")
            var asset = Asset(snapshot: snap, digests: nil, look: content)
            asset.lazyContent = content
            return asset
        }
        for i in 0..<count { table["bulk\(i)"] = make("bulk\(i)", at: 1_000_000 + Int64(i) * 7, content: "u\(i)") }
        for n in 0..<plantedExactPairs {
            let at = 900_000_000 + Int64(n) * 11
            table["pairA\(n)"] = make("pairA\(n)", at: at, content: "pair\(n)")
            table["pairB\(n)"] = make("pairB\(n)", at: at, content: "pair\(n)")
        }
        assets = table
    }

    func simulateExternalChange() { handlers.values.forEach { $0() } }

    // MARK: PhotoLibraryClient

    func requestAccess() async -> PHAuthorizationStatus { authorization }

    func inventoryPage(offset: Int, limit: Int) -> (photos: [PhotoSnapshot], total: Int) {
        pageRequests.append(offset)
        onInventoryPage?(offset)
        let all: [PhotoSnapshot]
        if let cached = sortedCache { all = cached } else {
            all = assets.values.map(\.snapshot).sorted {
                ($0.capturedAt ?? .distantPast, $1.id) > ($1.capturedAt ?? .distantPast, $0.id)
            }
            sortedCache = all
        }
        guard offset < all.count else { return ([], all.count) }
        let page = Array(all[offset..<min(all.count, offset + limit)])
        blockMainThreadForMetadata(reads: page.count)
        return (page, all.count)
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

    func snapshot(id: String, inspectAlbums: Bool) -> PhotoSnapshot? {
        blockMainThreadForMetadata(reads: 1)
        return assets[id]?.snapshot
    }

    // MARK: Device-like faults (docs/HANG_RCA_DEVICE_LOG.md)

    /// Real PhotoKit read per-asset metadata synchronously on the main queue ("Missing prefetched properties ... Fetching on
    /// demand on the main queue"). A non-zero value makes every inventory/snapshot read block the calling thread this long
    /// per asset, so main-thread watchdog tests can see it. Default 0 (no effect on existing tests).
    var metadataBlockPerAsset: Duration = .zero
    private(set) var mainThreadMetadataReads = 0
    /// Total time the calling thread was blocked by `metadataBlockPerAsset`, and the longest single block (one page or snapshot).
    private(set) var metadataBlockedSeconds = 0.0
    private(set) var longestMetadataBlockSeconds = 0.0

    private func blockMainThreadForMetadata(reads: Int) {
        mainThreadMetadataReads += reads
        guard metadataBlockPerAsset > .zero, reads > 0 else { return }
        let parts = metadataBlockPerAsset.components
        let perAsset = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        let total = perAsset * Double(reads)
        Thread.sleep(forTimeInterval: total)          // synchronous on purpose: that is the bug being modelled
        metadataBlockedSeconds += total
        longestMetadataBlockSeconds = max(longestMetadataBlockSeconds, total)
    }

    /// Fraction (0...1) of thumbnail requests that come back nil, as PhotoKit does with `PHPhotosErrorDomain 3303 "No resource
    /// found matching image request spec"` for iCloud-optimized assets. Which assets fail is a stable function of the id, so runs
    /// are reproducible and an asset always fails or always succeeds.
    var thumbnailFailureFraction = 0.0
    /// Requests that failed this way (every call counts, including repeats for the same asset).
    private(set) var thumbnailNoResourceFailures = 0
    /// The error PhotoKit would have reported for those nil results (for tests that classify failures).
    static let noResourceErrorCode = 3303

    func failsLikeOptimizedStorage(_ id: String) -> Bool {
        guard thumbnailFailureFraction > 0 else { return false }
        if thumbnailFailureFraction >= 1 { return true }
        let h = id.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }   // FNV-1a
        return Double(h % 10_000) / 10_000 < thumbnailFailureFraction
    }

    private(set) var thumbnailCalls = 0
    /// Fingerprint-size requests only (the Vision stage asks for larger thumbnails).
    private(set) var fingerprintThumbnailCalls = 0
    /// Every requested thumbnail target size, in call order (tests assert the 128 px fingerprints).
    private(set) var requestedThumbnailTargets: [CGFloat] = []
    /// Called with the offset of every inventory page request (lets a test interrupt a scan mid-inventory).
    var onInventoryPage: ((Int) -> Void)?
    var unavailableThumbnailIDs: Set<String> = []

    /// Assets whose thumbnail request suspends until `releaseStuckThumbnails()` and ignores plain
    /// cancellation, like a PhotoKit callback that never fires. The shared Deadline helper still
    /// ends the wait on scan Cancel (resume nil) and on `stuckThumbnailTimeout` (counted, nil).
    var stuckThumbnailIDs: Set<String> = []
    private let stuckWaiters = WaiterList<UIImage?>()
    /// Deadline for a stuck thumbnail, mirroring the real client's 10 s (tests may shorten it).
    var stuckThumbnailTimeout: TimeInterval = 10
    private(set) var thumbnailTimeouts = 0
    /// Thumbnail requests currently inside `thumbnail(_:target:)`, and the most there ever were at once.
    private(set) var thumbnailsInFlight = 0
    private(set) var maxThumbnailsInFlight = 0
    /// When true, every thumbnail request yields once, so overlapping requests become observable in the counters above.
    var yieldInThumbnails = false

    func releaseStuckThumbnails() {
        stuckThumbnailIDs = []
        stuckWaiters.drain().forEach { $0.resume(nil) }      // nil: fall through to normal rendering after release
    }

    func thumbnail(_ id: String, target: CGFloat) async -> UIImage? {
        thumbnailCalls += 1
        requestedThumbnailTargets.append(target)
        if target <= 300 { fingerprintThumbnailCalls += 1 }
        thumbnailsInFlight += 1
        maxThumbnailsInFlight = max(maxThumbnailsInFlight, thumbnailsInFlight)
        defer { thumbnailsInFlight -= 1 }
        if stuckThumbnailIDs.contains(id) {
            _ = await Deadline.withDeadline(stuckThumbnailTimeout, onExpire: {}) { (once: OneShotResume<UIImage?>) in
                stuckWaiters.append(once)
            }
            if stuckThumbnailIDs.contains(id) {     // still stuck: the deadline gave up on us
                thumbnailTimeouts += 1
                return nil                            // "unavailable", exactly like a cancelled request
            }
        } else if yieldInThumbnails { await Task.yield() }
        guard !disableThumbnails, !unavailableThumbnailIDs.contains(id), let asset = assets[id] else { return nil }
        if failsLikeOptimizedStorage(id) { thumbnailNoResourceFailures += 1; return nil }
        if let spec = asset.spec { return Self.renderScene(spec: spec) }
        return Self.renderScene(look: asset.look)
    }

    var disableThumbnails = false

    /// A small deterministic "photo": sky gradient, sun and hills, tinted by `look`.
    static func renderScene(look: String) -> UIImage {
        let seed = look.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) % 360 }
        let image = draw(hueSeed: seed, shiftX: 0, exposure: 1, extraSubject: false, pixelScale: nil)
        image.accessibilityIdentifier = "look|\(look)"
        return image
    }

    /// The same scene, with the hills panned by `shiftX * 6` px, brightness scaled by `exposure` and an optional extra subject.
    static func renderScene(spec: RenderSpec) -> UIImage {
        let seed = (spec.base &* 2_654_435_761 &+ 12_345) % 360
        let image = draw(hueSeed: abs(seed), shiftX: spec.shiftX, exposure: spec.exposure, extraSubject: spec.extraSubject, pixelScale: 1)
        image.accessibilityIdentifier = spec.token
        return image
    }

    private static func draw(hueSeed seed: Int, shiftX: Int, exposure: Double, extraSubject: Bool, pixelScale: CGFloat?) -> UIImage {
        let hue = CGFloat(seed) / 360
        let level = CGFloat(exposure)
        let size = CGSize(width: 320, height: 240)
        let format = UIGraphicsImageRendererFormat.default()
        if let pixelScale { format.scale = pixelScale }
        let pan = CGFloat(shiftX * 6)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor(hue: hue, saturation: 0.45, brightness: min(1, 0.95 * level), alpha: 1).cgColor,
                          UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.35, brightness: min(1, 0.75 * level), alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIColor(white: min(1, level), alpha: 0.9).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 220, y: 30, width: 46, height: 46))
            UIColor(hue: hue, saturation: 0.6, brightness: min(1, 0.35 * level), alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: -40 + pan, y: 150, width: 260, height: 160))
            ctx.cgContext.fillEllipse(in: CGRect(x: 120 + pan, y: 175, width: 260, height: 140))
            if extraSubject {
                UIColor(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 60, y: 90, width: 56, height: 56))
            }
        }
    }

    func digests(id: String, allowNetwork: Bool) async throws -> [ResourceDigest] {
        digestCalls.append(id)
        digestRequests.append((id, allowNetwork))
        onDigests?(id)
        if stuckDigestIDs.contains(id) {
            // Suspends until released or the (test-configurable) deadline, like a PhotoKit callback that never fires.
            _ = await Deadline.withDeadline(digestTimeout, onExpire: {}) { (once: OneShotResume<[ResourceDigest]>) in
                stuckDigestWaiters.append(once)
            }
            if stuckDigestIDs.contains(id) {          // still stuck: the deadline gave up on us
                digestTimeouts += 1
                throw LibraryResourceError.timedOut
            }
        }
        await Task.yield()
        guard let asset = assets[id] else { throw LibraryResourceError.notAccessible }
        if let local = asset.digests { return local }
        if let lazy = asset.lazyContent { return [Self.digest(lazy)] }
        if allowNetwork, let cloud = asset.cloudDigests { return cloud }
        throw LibraryResourceError.notAccessible
    }

    /// Assets whose digest request suspends until released or `digestTimeout` expires (expires → `.timedOut`).
    var stuckDigestIDs: Set<String> = []
    private let stuckDigestWaiters = WaiterList<[ResourceDigest]>()
    var digestTimeout: TimeInterval = 20
    private(set) var digestTimeouts = 0
    func releaseStuckDigests() {
        stuckDigestIDs = []
        stuckDigestWaiters.drain().forEach { $0.resume(nil) }
    }

    func verifiedSize(id: String) async -> Int64? {
        if stuckSizeIDs.contains(id) {
            _ = await Deadline.withDeadline(sizeTimeout, onExpire: {}) { (once: OneShotResume<Int64>) in
                stuckSizeWaiters.append(once)
            }
            if stuckSizeIDs.contains(id) {
                sizeTimeouts += 1
                return nil                              // unknown size, like a cancelled PhotoKit request
            }
        }
        return sizes[id]
    }

    /// Assets whose size request suspends until released or `sizeTimeout` expires (expires → nil/unknown).
    var stuckSizeIDs: Set<String> = []
    private let stuckSizeWaiters = WaiterList<Int64>()
    var sizeTimeout: TimeInterval = 10
    private(set) var sizeTimeouts = 0
    func releaseStuckSizes() {
        stuckSizeIDs = []
        stuckSizeWaiters.drain().forEach { $0.resume(nil) }
    }

    /// Assets placed in user albums (tests).
    var albumMemberTable: Set<String> = []
    func userAlbumAssetIDs() -> Set<String> { albumMemberTable }
    /// Every targeted album-membership lookup, in call order (tests assert the scan stays scoped).
    private(set) var albumMemberAmongCalls: [[String]] = []
    func albumMemberIDs(among ids: [String]) async -> Set<String> {
        albumMemberAmongCalls.append(ids)
        return Set(ids.filter { albumMemberTable.contains($0) })
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

    /// A review set: every pair is linked by "looks similar" evidence, so any photo may be the one kept.
    func reviewSet(_ ids: [String]) -> PhotoReviewGroup {
        let photos = ids.map { assets[$0]!.snapshot }
        var evidence: [PairEvidence] = []
        for (i, a) in photos.enumerated() { for b in photos[(i + 1)...] { evidence.append(PairEvidence(first: a.id, second: b.id, relation: .visuallySimilar)) } }
        return PhotoReviewGroup(id: "set-\(ids.joined(separator: "-"))", kind: .similar, keeper: photos[0],
                                candidates: Array(photos.dropFirst()), evidence: evidence, verifiedCandidateBytes: [:])
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

/// Which assets the Recent 100 scenario planted, so tests can assert exact outcomes.
struct Recent100Expectations {
    /// 5 byte-identical pairs (same time, same picture).
    var exactPairs: [[String]] = []
    /// 3 native bursts of 6 (same `burst` id).
    var bursts: [[String]] = []
    /// 2 quick runs of 5 shots, one second apart, panning 1-4 steps, with no burst id.
    var overlapRuns: [[String]] = []
    /// Favorite, album member, edited and shared: never deletable.
    var protected: [String] = []
    var screenshots: [String] = []
    var uniques: [String] = []
    var all: [String] { exactPairs.flatMap { $0 } + bursts.flatMap { $0 } + overlapRuns.flatMap { $0 } + protected + screenshots + uniques }
}

/// Small deterministic generator (SplitMix64) so scenario builders are reproducible from a seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension FakePhotoLibrary {
    /// A library dominated by bursts: `burstShare` of the photos sit in native bursts of `burstLength` frames (one second apart,
    /// small pans and exposure changes); the rest are unique scenes hours apart. Exactly `count` assets.
    static func burstHeavy(count: Int, burstShare: Double, burstLength: Int, seed: UInt64) -> FakePhotoLibrary {
        let library = FakePhotoLibrary()
        var rng = SeededGenerator(seed: seed)
        let length = max(2, burstLength)
        let burstCount = Int(Double(count) * min(1, max(0, burstShare))) / length
        var table: [String: Asset] = [:]
        table.reserveCapacity(count)
        var clock: Int64 = 1_600_000_000
        var made = 0
        func make(_ id: String, at: Int64, burst: String?, spec: RenderSpec) {
            let record = AssetRecord(id: id, revision: "v1", flags: [])
            let snap = PhotoSnapshot(id: id, record: record, capturedAt: Date(timeIntervalSince1970: TimeInterval(at)), burstID: burst,
                                     width: 4032, height: 3024, originalFilename: "IMG_\(id).HEIC")
            var asset = Asset(snapshot: snap, digests: nil, look: "base\(spec.base)")
            asset.lazyContent = "\(id)-\(spec.base)-\(spec.shiftX)-\(spec.exposure)"
            asset.spec = spec
            table[id] = asset
            made += 1
        }
        for b in 0..<burstCount {
            clock += 3_600 + Int64(rng.next() % 600)
            for frame in 0..<length {
                let shift = Int(rng.next() % 4)
                let exposure = 1 + Double(Int(rng.next() % 13) - 6) / 100          // +-6%
                make("b\(b)-\(frame)", at: clock + Int64(frame), burst: "burst-\(b)",
                     spec: RenderSpec(base: b, shiftX: shift, exposure: exposure))
            }
        }
        var unique = 0
        while made < count {
            clock += 3_600 + Int64(rng.next() % 600)
            make("u\(unique)", at: clock, burst: nil, spec: RenderSpec(base: 100_000 + unique))
            unique += 1
        }
        library.assets = table
        return library
    }

    /// The 100-item end-to-end library: 5 exact pairs, 3 bursts of 6, 2 overlap runs of 5, 4 protected photos, 10 screenshots
    /// and 48 other unique photos, all within the last 30 days.
    static func recent100Scenario(now: Date = Date()) -> (library: FakePhotoLibrary, expectations: Recent100Expectations) {
        let library = FakePhotoLibrary()
        var expectations = Recent100Expectations()
        let start = Int64(now.timeIntervalSince1970) - 29 * 86_400
        var clock = start
        var base = 0
        func nextUnitStart() -> Int64 { clock += 20_000; return clock }
        func nextBase() -> Int { base += 1; return base }

        for n in 0..<5 {
            let at = nextUnitStart(), scene = nextBase()
            let ids = ["ex\(n)-a", "ex\(n)-b"]
            for id in ids { library.add(id, content: "exact\(n)", bytes: 2_000_000 + Int64(n) * 100_000, at: at, spec: RenderSpec(base: scene)) }
            expectations.exactPairs.append(ids)
        }
        for n in 0..<3 {
            let at = nextUnitStart(), scene = nextBase()
            var ids: [String] = []
            for frame in 0..<6 {
                let id = "burst\(n)-\(frame)"
                library.add(id, content: id, at: at + Int64(frame), burst: "native-burst-\(n)",
                            spec: RenderSpec(base: scene, shiftX: frame % 3, exposure: 1 + Double(frame % 3 - 1) * 0.03))
                ids.append(id)
            }
            expectations.bursts.append(ids)
        }
        for n in 0..<2 {
            let at = nextUnitStart(), scene = nextBase()
            var ids: [String] = []
            for frame in 0..<5 {
                let id = "run\(n)-\(frame)"
                library.add(id, content: id, at: at + Int64(frame), spec: RenderSpec(base: scene, shiftX: frame))
                ids.append(id)
            }
            expectations.overlapRuns.append(ids)
        }
        let protectedSpecs: [(String, Set<PreservationFlag>)] = [("prot-favorite", [.favorite]), ("prot-album", []), ("prot-edited", [.edited]), ("prot-shared", [.shared])]
        for (id, flags) in protectedSpecs {
            library.add(id, content: id, at: nextUnitStart(), spec: RenderSpec(base: nextBase()))
            if !flags.isEmpty { library.update(id, flags: flags) }
            expectations.protected.append(id)
        }
        library.albumMemberTable = ["prot-album"]
        let screenshotBit: UInt = 1 << 2
        for n in 0..<10 {
            let id = "shot\(n)"
            library.add(id, content: id, at: nextUnitStart(), subtypes: screenshotBit, size: 400_000 + Int64(n) * 50_000, spec: RenderSpec(base: nextBase()))
            expectations.screenshots.append(id)
        }
        let used = expectations.all.count
        for n in 0..<(100 - used) {
            let id = "uniq\(n)"
            library.add(id, content: id, at: nextUnitStart(), spec: RenderSpec(base: nextBase()))
            expectations.uniques.append(id)
        }
        return (library, expectations)
    }
}

/// Lock-protected list of deadline waiters: the deadline body appends from whatever executor it
/// runs on; releases and timeouts resume from arbitrary queues.
private final class WaiterList<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [OneShotResume<Value>] = []
    func append(_ waiter: OneShotResume<Value>) { lock.lock(); waiters.append(waiter); lock.unlock() }
    func drain() -> [OneShotResume<Value>] { lock.lock(); let drained = waiters; waiters = []; lock.unlock(); return drained }
}

/// Deterministic faces/text for UI tests (the real analyzer needs a device).
@MainActor
final class FakePhotoAnalyzer: PhotoAnalyzer {
    var descriptions: [String: PhotoDescription] = [:]
    func describe(assetID: String) async -> PhotoDescription {
        descriptions[assetID] ?? PhotoDescription(faceCount: nil, text: nil)
    }
}
#endif

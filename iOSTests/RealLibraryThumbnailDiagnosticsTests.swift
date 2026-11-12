import XCTest
import Photos
import UIKit
@testable import CleanSlate

/// Opt-in diagnostic against the simulator's REAL PhotoKit library. Runs only with
/// `TEST_RUNNER_CLEANSLATE_REALLIB=1` on the dedicated local simulator. Prints text counts only
/// (`REALLIB_THUMB key=value`); never prints identifiers, names, dates, locations or pixels.
@MainActor
final class RealLibraryThumbnailDiagnosticsTests: XCTestCase {
    #if targetEnvironment(simulator)
    private static let onSimulator = true
    #else
    private static let onSimulator = false
    #endif
    func testThumbnailPipelineOnRealLibrary() async throws {
        try XCTSkipUnless(Self.onSimulator, "Real-library diagnostic never runs on a physical device.")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLEANSLATE_REALLIB"] == "1", "real-library diagnostic only")
        try XCTSkipUnless(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, "Photos not authorized")
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = 20
        let assets = PHAsset.fetchAssets(with: options)
        print("REALLIB_THUMB fetched=\(assets.count)")
        var clientNil = 0, hashNil = 0, ok = 0
        var infoSummary: [String: Int] = [:]
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            let image = await PhotoKitLibraryClient.shared.thumbnail(asset.localIdentifier, target: 128)
            if let image {
                if VisualFeatures.differenceHash(image) == nil { hashNil += 1 } else { ok += 1 }
                if index == 0 { print("REALLIB_THUMB first_size=\(Int(image.size.width))x\(Int(image.size.height)) cg=\(image.cgImage != nil) ci=\(image.ciImage != nil)") }
            } else { clientNil += 1 }
            // Same request, raw: record which info keys PhotoKit returns.
            let raw = PHImageRequestOptions()
            raw.isNetworkAccessAllowed = false; raw.deliveryMode = .fastFormat; raw.resizeMode = .fast
            let keys: [String] = await withCheckedContinuation { cont in
                let once = OneShotFlag()
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 128, height: 128),
                                                      contentMode: .aspectFit, options: raw) { @Sendable img, info in
                    guard once.claim() else { return }
                    var k = (info ?? [:]).compactMap { key, value -> String? in
                        guard let s = key as? String else { return nil }
                        if s == PHImageErrorKey, let e = value as? NSError { return "error:\(e.domain):\(e.code)" }
                        if let b = value as? Bool { return "\(s)=\(b)" }
                        return nil
                    }
                    k.append(img == nil ? "image=nil" : "image=ok")
                    cont.resume(returning: k.sorted())
                }
            }
            for key in keys { infoSummary[key, default: 0] += 1 }
        }
        print("REALLIB_THUMB client_nil=\(clientNil) hash_nil=\(hashNil) ok=\(ok)")
        for (key, count) in infoSummary.sorted(by: { $0.key < $1.key }) { print("REALLIB_THUMB info \(key) count=\(count)") }
    }
}

private final class OneShotFlag: @unchecked Sendable {
    private let lock = NSLock(); private var used = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}

#if DEBUG
import Foundation
import UIKit
import os

/// A stand-in for Vision. It reads the `RenderSpec` the fake library tagged onto the thumbnail, so results are deterministic,
/// instant and countable. `failAll` simulates a device where Vision is unavailable.
final class FakeVisualAnalyzer: VisualAnalyzing, @unchecked Sendable {
    private struct State { var calls = 0, prints = 0, quality = 0; var failAll = false; var printsByPicture: [String: Int] = [:] }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Every request, of any kind.
    var calls: Int { state.withLock { $0.calls } }
    var printCalls: Int { state.withLock { $0.prints } }
    var qualityCalls: Int { state.withLock { $0.quality } }
    /// The most times one and the same picture (by its render spec) was feature-printed. A cached engine keeps this at 1.
    var maxPrintsOfOnePicture: Int { state.withLock { $0.printsByPicture.values.max() ?? 0 } }
    var failAll: Bool {
        get { state.withLock { $0.failAll } }
        set { state.withLock { $0.failAll = newValue } }
    }

    struct Failure: Error {}

    private func record(print: Bool, picture: String = "") throws {
        let fail = state.withLock { s -> Bool in
            s.calls += 1
            if print { s.prints += 1; s.printsByPicture[picture, default: 0] += 1 } else { s.quality += 1 }
            return s.failAll
        }
        if fail { throw Failure() }
    }

    func featurePrint(_ image: UIImage) async throws -> VisualPrint {
        let token = await Self.token(of: image)
        try record(print: true, picture: token)
        return VisualPrint(payload: token) { other in
            Self.distance(token, (other.payload as? String) ?? "")
        }
    }

    private struct ImageBox: @unchecked Sendable { let image: UIImage }
    /// `UIImage.accessibilityIdentifier` is main-actor isolated in the SDK.
    private static func token(of image: UIImage) async -> String {
        let box = ImageBox(image: image)
        return await MainActor.run { box.image.accessibilityIdentifier ?? "" }
    }

    func faceQuality(_ image: UIImage) async throws -> Double? { try record(print: false); return nil }
    func aesthetics(_ image: UIImage) async throws -> Double { try record(print: false); return 0.5 }

    /// Same picture 0.1; the same scene panned at most two steps 0.2; same scene but clearly different (bigger pan or a
    /// person entering the frame) 0.5; a different scene 0.9. The engine treats anything under 0.32 as similar.
    static func distance(_ a: String, _ b: String) -> Double {
        guard let x = FakePhotoLibrary.RenderSpec.parse(a), let y = FakePhotoLibrary.RenderSpec.parse(b) else { return a == b ? 0.1 : 0.9 }
        guard x.base == y.base else { return 0.9 }
        if x == y { return 0.1 }
        if x.extraSubject != y.extraSubject { return 0.5 }
        return abs(x.shiftX - y.shiftX) <= 2 ? 0.2 : 0.5
    }
}
#endif

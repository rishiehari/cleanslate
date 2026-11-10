import Foundation
import UIKit
import Vision
import CleanSlateCore

/// Describes what is in a photo (faces, text) so the review screen can warn "you might lose someone's face".
/// Advisory only: it never authorizes or blocks a deletion.
@MainActor
protocol PhotoAnalyzer: AnyObject {
    func describe(assetID: String) async -> PhotoDescription
}

/// Vision-based analysis (device only; the simulator has no inference hardware, so it returns "unknown").
@MainActor
final class VisionPhotoAnalyzer: PhotoAnalyzer {
    private let library: PhotoLibraryClient
    private var cache: [String: PhotoDescription] = [:]
    private var failures = 0

    init(library: PhotoLibraryClient) { self.library = library }

    func describe(assetID: String) async -> PhotoDescription {
        if let cached = cache[assetID] { return cached }
        // After repeated failures Vision isn't usable here; stop paying ~0.4 s per attempt.
        guard failures < 3, let image = await library.thumbnail(assetID, target: 768), let cg = image.cgImage else {
            return PhotoDescription(faceCount: nil, text: nil)
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        var faces: Int?
        var text: Set<String>?
        do { faces = try await DetectFaceRectanglesRequest().perform(on: cg, orientation: orientation).count } catch { failures += 1 }
        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .fast
            let lines = try await request.perform(on: cg, orientation: orientation).compactMap { $0.topCandidates(1).first?.string }
            text = DifferenceAnalysis.normalizedText(lines)
        } catch { failures += 1 }
        let description = PhotoDescription(faceCount: faces, text: text)
        // Only a complete answer is remembered; a partial one (a request failed) must be retried, never treated as final.
        if faces != nil, text != nil { cache[assetID] = description }
        return description
    }
}

private extension CGImagePropertyOrientation {
    init(_ source: UIImage.Orientation) {
        switch source {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

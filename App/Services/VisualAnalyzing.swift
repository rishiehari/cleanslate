import Foundation
import UIKit
import Vision

/// An opaque, comparable image fingerprint. The real analyzer wraps Vision's feature print; test fakes carry their own data.
struct VisualPrint: Sendable {
    let distanceTo: @Sendable (VisualPrint) throws -> Double
    /// The wrapped native value (Vision's observation for the real analyzer), so two real prints can be compared.
    let payload: (any Sendable)?
    init(payload: (any Sendable)? = nil, distanceTo: @escaping @Sendable (VisualPrint) throws -> Double) {
        self.payload = payload; self.distanceTo = distanceTo
    }
}

/// The seam between the scan engine and Vision, so tests can count calls, inject failures and avoid real inference.
protocol VisualAnalyzing: Sendable {
    func featurePrint(_ image: UIImage) async throws -> VisualPrint
    func faceQuality(_ image: UIImage) async throws -> Double?
    func aesthetics(_ image: UIImage) async throws -> Double
}

/// Production implementation: forwards to `VisualFeatures` (Vision framework, on-device).
struct VisionVisualAnalyzer: VisualAnalyzing {
    func featurePrint(_ image: UIImage) async throws -> VisualPrint {
        let observation = try await VisualFeatures.printFeature(image)
        return VisualPrint(payload: observation) { other in
            // Only real prints can be compared with each other.
            guard let otherObservation = other.payload as? FeaturePrintObservation else { throw VisualFeatureError.noBitmap }
            return try VisualFeatures.distance(observation, otherObservation)
        }
    }
    func faceQuality(_ image: UIImage) async throws -> Double? { try await VisualFeatures.faceQuality(image) }
    func aesthetics(_ image: UIImage) async throws -> Double { try await VisualFeatures.aesthetics(image) }
}

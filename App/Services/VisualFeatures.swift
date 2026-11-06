import Foundation
import UIKit
import Vision
import CoreGraphics
import ImageIO
import CleanSlateCore

/// A perceptual hash proposes comparisons only. It cannot establish that deletion is safe.
enum VisualFeatures {
    static func differenceHash(_ image: UIImage) -> UInt64? {
        // UIImage may carry a non-up EXIF orientation. Draw before hashing so the
        // fingerprint represents what the person actually sees.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let oriented = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 80), format: format)
            .image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 90, height: 80)) }
        guard let cg = oriented.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let worked = pixels.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(data: memory.baseAddress, width: 9, height: 8,
                                          bitsPerComponent: 8, bytesPerRow: 9,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 9, height: 8))
            return true
        }
        guard worked else { return nil }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                hash <<= 1
                if pixels[row * 9 + col] > pixels[row * 9 + col + 1] { hash |= 1 }
            }
        }
        return hash
    }

    /// Vision feature print (Swift Vision API, iOS 18+). Throws so callers can tell
    /// "unavailable on this device" from "no result".
    static func printFeature(_ image: UIImage) async throws -> FeaturePrintObservation {
        guard let cg = image.cgImage else { throw VisualFeatureError.noBitmap }
        return try await GenerateImageFeaturePrintRequest()
            .perform(on: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    static func distance(_ first: FeaturePrintObservation, _ second: FeaturePrintObservation) throws -> Double {
        try first.distance(to: second)
    }

    /// Apple's aesthetics score is in [-1,1]; `QualitySignals` expects [0,1].
    static func aesthetics(_ image: UIImage) async throws -> Double {
        guard let cg = image.cgImage else { throw VisualFeatureError.noBitmap }
        let result = try await CalculateImageAestheticsScoresRequest()
            .perform(on: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
        return min(1, max(0, (Double(result.overallScore) + 1) / 2))
    }

    /// Worst visible face matters for family photos. nil when no face has a score.
    static func faceQuality(_ image: UIImage) async throws -> Double? {
        guard let cg = image.cgImage else { throw VisualFeatureError.noBitmap }
        let faces = try await DetectFaceCaptureQualityRequest()
            .perform(on: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
        let scores = faces.compactMap { $0.captureQuality?.score }
        guard !scores.isEmpty else { return nil }
        return Double(scores.min() ?? 0.5)
    }

    static func sharpnessAndExposure(_ image: UIImage) -> (sharpness: Double?, exposure: Double?) {
        guard let cg = image.cgImage else { return (nil, nil) }
        let width = 64, height = 64
        var gray = [UInt8](repeating: 0, count: width * height)
        let success = gray.withUnsafeMutableBytes { pixels -> Bool in
            guard let context = CGContext(data: pixels.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return (nil, nil) }
        var gradient = 0.0
        var count = 0
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                let index = y * width + x
                let laplacian = abs(4 * Int(gray[index]) - Int(gray[index-1]) - Int(gray[index+1]) - Int(gray[index-width]) - Int(gray[index+width]))
                gradient += Double(laplacian)
                count += 1
            }
        }
        let avg = Double(gray.reduce(0) { $0 + Int($1) }) / Double(gray.count * 255)
        let clippedFraction = Double(gray.filter { $0 < 5 || $0 > 250 }.count) / Double(gray.count)
        return (min(1, gradient / Double(count) / 45.0),
                max(0, 1 - abs(avg - 0.5) * 1.3 - clippedFraction * 0.4))
    }
}

enum VisualFeatureError: Error { case noBitmap }

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

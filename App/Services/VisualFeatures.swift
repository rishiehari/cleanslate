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

    static func printFeature(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        do {
            try VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation), options: [:]).perform([request])
            return request.results?.first
        } catch { return nil }
    }

    static func distance(_ first: VNFeaturePrintObservation, _ second: VNFeaturePrintObservation) -> Float? {
        guard first.requestRevision == second.requestRevision else { return nil }
        var d: Float = 0
        do { try first.computeDistance(&d, to: second); return d } catch { return nil }
    }

    static func aesthetics(_ image: UIImage) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let request = VNCalculateImageAestheticsScoresRequest()
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            guard let value = request.results?.first?.overallScore else { return nil }
            // Apple's aesthetics score is in [-1,1], while QualitySignals expects [0,1].
            return min(1, max(0, (Double(value) + 1) / 2))
        } catch { return nil }
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

    static func faceQuality(_ image: UIImage) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectFaceCaptureQualityRequest()
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            let scores = request.results?.compactMap(\.faceCaptureQuality) ?? []
            guard !scores.isEmpty else { return nil }
            // Worst visible face matters for family photos. Never assume one smiling face
            // makes the whole group redundant.
            return Double(scores.min() ?? 0.5)
        } catch { return nil }
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

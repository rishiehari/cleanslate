import Foundation

/// The 64-bit "difference hash" used to propose look-alike photos. The pixel work (scaling to 9x8 gray) is done
/// by the app or the eval tool; the bit packing lives here so both produce identical hashes.
public enum DifferenceHash {
    public static let width = 9, height = 8

    /// `gray9x8` is 72 bytes, row-major (9 columns, 8 rows). Bit = 1 where a pixel is brighter than its right neighbour.
    public static func compute(gray9x8 pixels: [UInt8]) -> UInt64? {
        guard pixels.count == width * height else { return nil }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                hash <<= 1
                if pixels[row * width + col] > pixels[row * width + col + 1] { hash |= 1 }
            }
        }
        return hash
    }

    public static func distance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
}

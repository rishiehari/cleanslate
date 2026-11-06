import Foundation

public struct ResourceDigest: Hashable, Sendable, Codable {
    public let type: String
    public let byteCount: Int64
    public let sha256: String
    public init(type: String, byteCount: Int64, sha256: String) {
        self.type = type; self.byteCount = byteCount; self.sha256 = sha256
    }
}

public enum ResourceSignatures {
    /// Use all PhotoKit resources, including paired video/adjustments, for identity.
    /// A match can still have different albums and metadata, which must be protected separately.
    public static func canonical(_ resources: [ResourceDigest]) -> String? {
        guard !resources.isEmpty, resources.allSatisfy({ $0.byteCount >= 0 && $0.sha256.count == 64 }) else { return nil }
        return resources.map { "\($0.type):\($0.byteCount):\($0.sha256.lowercased())" }.sorted().joined(separator: "|")
    }
    public static func logicalBytes(_ resources: [ResourceDigest]) -> Int64? {
        guard !resources.isEmpty, resources.allSatisfy({ $0.byteCount >= 0 }) else { return nil }
        let sum = resources.reduce(Int64(0)) { partial, resource in
            partial.addingReportingOverflow(resource.byteCount).overflow ? Int64.max : partial + resource.byteCount
        }
        return sum == Int64.max ? nil : sum
    }
}

import Foundation

/// What was recognized in one photo (by Vision on the device). nil = could not be determined.
public struct PhotoDescription: Sendable, Equatable {
    public let faceCount: Int?
    public let text: Set<String>?
    public init(faceCount: Int?, text: Set<String>?) { self.faceCount = faceCount; self.text = text }
}

public enum DifferenceWarning: String, Sendable, Hashable, CaseIterable {
    case differentPeople, differentText
}

/// Warnings are a prompt for the human ("you might lose someone's face or a sign"). They never authorize
/// or block deletion by themselves; the user acknowledges them photo by photo.
public enum DifferenceAnalysis {
    public static func warnings(candidate: PhotoDescription, keeper: PhotoDescription) -> Set<DifferenceWarning> {
        var result: Set<DifferenceWarning> = []
        if let a = candidate.faceCount, let b = keeper.faceCount, a != b { result.insert(.differentPeople) }
        if let a = candidate.text, let b = keeper.text, !a.symmetricDifference(b).isEmpty { result.insert(.differentText) }
        return result
    }

    /// Lowercases, keeps letters and digits, and drops fragments shorter than 3 characters (OCR noise).
    public static func normalizedText(_ lines: [String]) -> Set<String> {
        var tokens: Set<String> = []
        for line in lines {
            for word in line.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where word.count >= 3 {
                tokens.insert(String(word))
            }
        }
        return tokens
    }
}

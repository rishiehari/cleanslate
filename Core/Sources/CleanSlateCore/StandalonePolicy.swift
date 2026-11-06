import Foundation

/// A deletion with NO keeper (screenshots, screen recordings, large files). Separate from the
/// duplicate flow on purpose: the duplicate rules assume a keeper and must never be loosened for this.
public struct StandaloneDeletionPlan: Sendable {
    public let selectedIDs: Set<String>
    public let expectedRevisions: [String: String]
    /// Every selected item was tapped individually, or the user explicitly chose "select all" and confirmed the count.
    public let individuallyConfirmedIDs: Set<String>
    public let wasExplicitlyConfirmedByUser: Bool
    public init(selectedIDs: Set<String>, expectedRevisions: [String: String],
                individuallyConfirmedIDs: Set<String>, wasExplicitlyConfirmedByUser: Bool) {
        self.selectedIDs = selectedIDs
        self.expectedRevisions = expectedRevisions
        self.individuallyConfirmedIDs = individuallyConfirmedIDs
        self.wasExplicitlyConfirmedByUser = wasExplicitlyConfirmedByUser
    }
}

extension SafetyPolicy {
    /// Fail-closed validation for keeper-less deletions. Nothing is ever pre-selected for these
    /// categories, and ANY preservation flag (hard or conditional) blocks, since no keeper exists
    /// that could stand in for the photo.
    public static func validateStandalone(_ plan: StandaloneDeletionPlan,
                                          currentByID: [String: AssetRecord]) -> ReviewReason? {
        guard plan.wasExplicitlyConfirmedByUser else { return .userConfirmationRequired }
        guard !plan.selectedIDs.isEmpty else { return .invalidSelection }
        guard plan.selectedIDs.isSubset(of: plan.individuallyConfirmedIDs) else { return .invalidSelection }
        for id in plan.selectedIDs {
            guard let current = currentByID[id], let expected = plan.expectedRevisions[id] else { return .missingAsset }
            guard !expected.isEmpty, current.revision == expected else { return .staleRevision }
            guard current.flags.isEmpty else { return .protected }
        }
        return nil
    }
}

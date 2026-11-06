import Foundation

public struct BatchValidation: Sendable, Equatable {
    /// Plans that failed on their own, by their index in the batch.
    public let planFailures: [Int: ReviewReason]
    /// A problem with the batch as a whole (too large, or plans that contradict each other).
    public let batchFailure: ReviewReason?
    public var isValid: Bool { planFailures.isEmpty && batchFailure == nil }
}

extension SafetyPolicy {
    /// One system prompt for many groups is only safe if the whole batch is consistent. Fail closed:
    /// any problem rejects the entire batch (the caller can then set the bad groups aside and retry).
    public static let maximumBatchTargets = 500

    public static func validateBatch(_ plans: [ApprovedDeletionPlan], currentByID: [String: AssetRecord]) -> BatchValidation {
        guard !plans.isEmpty else { return BatchValidation(planFailures: [:], batchFailure: .invalidSelection) }
        var failures: [Int: ReviewReason] = [:]
        for (index, plan) in plans.enumerated() {
            if let reason = validateCommit(plan, currentByID: currentByID) { failures[index] = reason }
        }
        // No photo may be deleted in one group while being kept in another, and none may be deleted twice.
        var targets: [String: Int] = [:]
        var keepers: [String: Int] = [:]
        var conflict = false
        for (index, plan) in plans.enumerated() {
            for id in plan.selectedIDs {
                if targets[id] != nil { conflict = true; failures[index] = failures[index] ?? .invalidSelection }
                targets[id] = index
            }
            for id in plan.keeperIDs { keepers[id] = index }
        }
        for (id, targetPlan) in targets where keepers[id] != nil && keepers[id] != targetPlan {
            conflict = true
            failures[targetPlan] = failures[targetPlan] ?? .invalidSelection
            failures[keepers[id]!] = failures[keepers[id]!] ?? .invalidSelection
        }
        let tooLarge = targets.count > maximumBatchTargets
        let batchFailure: ReviewReason? = (conflict || tooLarge) ? .invalidSelection : nil
        return BatchValidation(planFailures: failures, batchFailure: batchFailure)
    }
}

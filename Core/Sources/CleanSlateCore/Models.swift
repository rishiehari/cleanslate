import Foundation

/// Framework-free models. PhotoKit and Vision adapters must map into these immutable records.
public enum PreservationFlag: String, Codable, CaseIterable, Hashable, Sendable {
    case favorite, hidden, edited, raw, livePhoto, shared, userBurstPick
    case curatedAlbum, incompleteResources, unknownOwnership, uncertainMetadata
    case cinematicVideo, spatialMedia
}

extension PreservationFlag {
    /// Always blocks deletion of the target, whatever the evidence.
    public static let hard: Set<PreservationFlag> = [
        .favorite, .hidden, .userBurstPick, .shared, .curatedAlbum,
        .incompleteResources, .unknownOwnership, .uncertainMetadata]
    /// Allowed on a deletion target ONLY when its full resource set is byte-identical to a keeper
    /// that carries at least the same conditional flags. Never allowed for near-duplicates.
    public static let conditional: Set<PreservationFlag> = [.livePhoto, .edited, .raw, .cinematicVideo, .spatialMedia]
}

public struct AssetRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// Deterministic fingerprint of the *latest* PhotoKit/asset-resource state, not an app scan ID.
    public let revision: String
    public let flags: Set<PreservationFlag>
    /// Known size only if measured by a documented API with provenance.
    public let verifiedLogicalBytes: Int64?
    public init(id: String, revision: String, flags: Set<PreservationFlag> = [], verifiedLogicalBytes: Int64? = nil) {
        self.id = id
        self.revision = revision
        self.flags = flags
        self.verifiedLogicalBytes = verifiedLogicalBytes
    }
}

public enum PairRelation: String, Codable, Sendable {
    case exactResources, verifiedNearDuplicate, visuallySimilar, distinct, uncertain
}

public struct PairEvidence: Codable, Equatable, Sendable {
    public let first: String
    public let second: String
    public let relation: PairRelation
    /// True only when full resource-set equivalence is established with hashes of *every*
    /// relevant resource and representations are accounted for.
    public let completeResourceEquality: Bool
    /// A visual difference that may preserve new people, poses, text or moments.
    public let uniqueContentDetected: Bool
    /// Calibrated held-out estimate, NOT a Vision distance or cosine similarity.
    public let calibratedRedundancyProbability: Double?
    public init(first: String, second: String, relation: PairRelation,
                completeResourceEquality: Bool = false, uniqueContentDetected: Bool = false,
                calibratedRedundancyProbability: Double? = nil) {
        self.first = first
        self.second = second
        self.relation = relation
        self.completeResourceEquality = completeResourceEquality
        self.uniqueContentDetected = uniqueContentDetected
        self.calibratedRedundancyProbability = calibratedRedundancyProbability
    }
    public func joins(_ a: String, _ b: String) -> Bool {
        (first == a && second == b) || (first == b && second == a)
    }
}

public struct ReviewCluster: Sendable {
    public let id: String
    public let assets: [AssetRecord]
    public let keeperIDs: Set<String>
    public let suggestedRemovalIDs: Set<String>
    public let evidence: [PairEvidence]
    public init(id: String, assets: [AssetRecord], keeperIDs: Set<String>,
                suggestedRemovalIDs: Set<String>, evidence: [PairEvidence]) {
        self.id = id
        self.assets = assets
        self.keeperIDs = keeperIDs
        self.suggestedRemovalIDs = suggestedRemovalIDs
        self.evidence = evidence
    }
}

public enum ReviewReason: String, Codable, Sendable {
    case protected, missingKeeper, keeperAlsoRemoved, missingAsset, duplicateAssetID
    case missingProof, uniqueDifference, uncertainMatch, calibrationRequired
    case invalidConfidence, staleRevision, userConfirmationRequired, invalidSelection
}

public struct ReviewDecision: Sendable {
    public let preselected: Set<String>
    public let reviewOnly: Set<String>
    public let blocked: [String: ReviewReason]
    public init(preselected: Set<String>, reviewOnly: Set<String>, blocked: [String: ReviewReason]) {
        self.preselected = preselected
        self.reviewOnly = reviewOnly
        self.blocked = blocked
    }
}

public struct PreselectionConfiguration: Sendable {
    public let nearEnabled: Bool
    public let independentSafetyGatePassed: Bool
    public let minimumCalibratedProbability: Double
    public init(nearEnabled: Bool = false, independentSafetyGatePassed: Bool = false,
                minimumCalibratedProbability: Double = 0.999) {
        self.nearEnabled = nearEnabled
        self.independentSafetyGatePassed = independentSafetyGatePassed
        self.minimumCalibratedProbability = minimumCalibratedProbability
    }
}

/// Produced from an explicit user UI action; never produced from a background scanner.
public struct ApprovedDeletionPlan: Sendable {
    public let selectedIDs: Set<String>
    public let keeperIDs: Set<String>
    public let expectedRevisions: [String: String]
    public let wasExplicitlyConfirmedByUser: Bool
    /// Proof frozen at review time; must be re-evaluated against fresh asset revisions.
    public let evidence: [PairEvidence]
    /// User explicitly compared and selected these review-only candidates.
    public let manuallyReviewedIDs: Set<String>
    public init(selectedIDs: Set<String>, keeperIDs: Set<String>,
                expectedRevisions: [String: String], wasExplicitlyConfirmedByUser: Bool,
                evidence: [PairEvidence], manuallyReviewedIDs: Set<String> = []) {
        self.selectedIDs = selectedIDs
        self.keeperIDs = keeperIDs
        self.expectedRevisions = expectedRevisions
        self.wasExplicitlyConfirmedByUser = wasExplicitlyConfirmedByUser
        self.evidence = evidence
        self.manuallyReviewedIDs = manuallyReviewedIDs
    }
}

import Foundation

public enum PlanKind: String, Codable, Sendable, CaseIterable {
    case verifiedExact      // byte-identical duplicate group (keeper + copies)
    case screenshots        // standalone screenshots / screen recordings
    case largeVideo         // standalone large videos
    case largeFile          // other standalone large files
    case similarReview      // similar photos with NO user decision yet
}

/// Tier order is the review order. Lower raw value = reviewed first.
public enum PlanTier: Int, Codable, Sendable, Comparable {
    case a = 0   // verifiedExact
    case b = 1   // screenshots, largeVideo, largeFile
    case c = 2   // similarReview (never counted toward the goal)
    public static func < (l: PlanTier, r: PlanTier) -> Bool { l.rawValue < r.rawValue }
}

/// One source of candidates as the scan produced it (a group or a standalone category item set).
public struct PlanSource: Sendable, Equatable {
    public let id: String                 // stable opaque id (group id / category item id)
    public let kind: PlanKind
    public let keepers: [AssetRecord]     // photos this source KEEPS (empty for standalone kinds)
    public let targets: [AssetRecord]     // photos the user could remove after review
    public init(id: String, kind: PlanKind, keepers: [AssetRecord], targets: [AssetRecord]) {
        self.id = id
        self.kind = kind
        self.keepers = keepers
        self.targets = targets
    }
}

public struct StorageGoal: Codable, Sendable, Equatable {
    public let id: UUID
    public let targetLogicalBytes: Int64  // user request, NOT a free-space promise
    public let scopeID: String
    public let createdAt: Date
    public init(id: UUID, targetLogicalBytes: Int64, scopeID: String, createdAt: Date) {
        self.id = id
        self.targetLogicalBytes = targetLogicalBytes
        self.scopeID = scopeID
        self.createdAt = createdAt
    }
}

public struct PlanItem: Sendable, Equatable, Identifiable {
    public let id: String                 // == PlanSource.id
    public let kind: PlanKind
    public let tier: PlanTier
    public let assetIDs: [String]         // remaining eligible targets, sorted ascending
    public let expectedRevisions: [String: String]   // assetID -> AssetRecord.revision
    public let potentialBytes: Int64?     // sum of known target bytes; nil for tier C or if NO target has a known size
    public let unknownSizeCount: Int      // eligible targets whose verifiedLogicalBytes is nil
    public let countsTowardGoal: Bool     // false for tier C
}

public struct PlanCoverage: Sendable, Equatable {
    public var sourcesConsidered = 0
    public var targetsSkippedProtected = 0   // any hard PreservationFlag (includes .userProtected)
    public var targetsSkippedKeptElsewhere = 0
    public var targetsSkippedDuplicate = 0   // already counted by an earlier item
    public var unknownSizeTargets = 0
    public init() {}
}

public enum PlanUnmetReason: String, Sendable, Equatable {
    case invalidTarget          // goal target <= 0
    case notEnoughKnownEvidence // reviewed everything known and still short
    case limitedByMaxItems      // stopped because maxItems was reached first
}

public struct GoalPlan: Sendable, Equatable {
    public let items: [PlanItem]
    public let potentialKnownBytes: Int64        // sum of potentialBytes of items with countsTowardGoal
    public let attainableFromKnownEvidence: Bool // potentialKnownBytes >= goal.targetLogicalBytes
    public let unmetReason: PlanUnmetReason?     // nil when attainable
    public let coverage: PlanCoverage
}

public enum StoragePlanner {
    public static func build(goal: StorageGoal, sources: [PlanSource], maxItems: Int) -> GoalPlan {
        // Rule 1. Invalid goal check
        if goal.targetLogicalBytes <= 0 || maxItems <= 0 {
            return GoalPlan(items: [], potentialKnownBytes: 0, attainableFromKnownEvidence: false, unmetReason: .invalidTarget, coverage: PlanCoverage())
        }
        
        // Collect all keeper IDs from all sources first (we need to do this before processing any sources)
        var keeperIDs = Set<String>()
        for source in sources {
            for keeper in source.keepers {
                keeperIDs.insert(keeper.id)
            }
        }
        
        // Process sources and build items
        var items: [PlanItem] = []
        var coverage = PlanCoverage()
        var claimedTargets = Set<String>() // Track which targets have been claimed by earlier sources
        var totalPotentialBytes: Int64 = 0
        
        // Sort sources by (tier, id) as per rule 3
        let sortedSources = sources.sorted { source1, source2 in
            let tier1 = getTier(for: source1.kind)
            let tier2 = getTier(for: source2.kind)
            if tier1 != tier2 {
                return tier1 < tier2
            }
            return source1.id < source2.id
        }
        
        for source in sortedSources {
            coverage.sourcesConsidered += 1
            
            // Create a filtered list of targets for this source (after applying rules)
            var filteredTargets: [AssetRecord] = []
            
            // Rule 4. Keepers are never targets
            for target in source.targets {
                if keeperIDs.contains(target.id) {
                    coverage.targetsSkippedKeptElsewhere += 1
                    continue
                }
                
                // Rule 5. Protected targets are never counted
                if !target.flags.isDisjoint(with: PreservationFlag.hard) {
                    coverage.targetsSkippedProtected += 1
                    continue
                }
                
                // Rule 6. Count each asset once (check if already claimed)
                if claimedTargets.contains(target.id) {
                    coverage.targetsSkippedDuplicate += 1
                    continue
                }
                
                filteredTargets.append(target)
                claimedTargets.insert(target.id)
            }
            
            // Rule 8. Drop empty items
            if filteredTargets.isEmpty {
                continue
            }
            
            // Build the item
            let tier = getTier(for: source.kind)
            var assetIDs: [String] = filteredTargets.map { $0.id }.sorted()
            var expectedRevisions: [String: String] = [:]
            var potentialBytes: Int64? = nil
            var unknownSizeCount = 0
            
            // Rule 7. Item bytes calculation
            if tier == .c {
                // For tier C, no potential bytes, counts toward goal false
                potentialBytes = nil
                unknownSizeCount = filteredTargets.count
            } else {
                // For tiers A and B
                var totalBytes: Int64 = 0
                var hasKnownSize = false
                
                for target in filteredTargets {
                    if let size = target.verifiedLogicalBytes {
                        totalBytes += size
                        hasKnownSize = true
                    } else {
                        unknownSizeCount += 1
                    }
                }
                
                potentialBytes = hasKnownSize ? totalBytes : nil
            }
            
            // Create the item - we need to populate expectedRevisions with actual revisions
            var populatedExpectedRevisions: [String: String] = [:]
            for target in filteredTargets {
                populatedExpectedRevisions[target.id] = target.revision
            }
            
            // Create the item
            let item = PlanItem(
                id: source.id,
                kind: source.kind,
                tier: tier,
                assetIDs: assetIDs,
                expectedRevisions: populatedExpectedRevisions,
                potentialBytes: potentialBytes,
                unknownSizeCount: unknownSizeCount,
                countsTowardGoal: tier != .c
            )
            
            items.append(item)
            
            // Update totals for counting purposes
            if tier != .c, let bytes = potentialBytes {
                totalPotentialBytes += bytes
            }
        }
        
        // Rule 9. Item order in the plan (sort by tier ascending, then potentialBytes descending, then assetIDs.count ascending, then id ascending)
        items.sort { item1, item2 in
            if item1.tier != item2.tier {
                return item1.tier < item2.tier
            }
            
            // For items with same tier, sort by potentialBytes descending (nil last)
            if let bytes1 = item1.potentialBytes, let bytes2 = item2.potentialBytes {
                if bytes1 != bytes2 {
                    return bytes1 > bytes2 // Descending
                }
            } else if let _ = item1.potentialBytes {
                return true  // item1 comes first (item2 is nil)
            } else if let _ = item2.potentialBytes {
                return false // item2 comes first (item1 is nil)
            }
            
            // If both are nil or have same bytes, sort by asset count ascending
            if item1.assetIDs.count != item2.assetIDs.count {
                return item1.assetIDs.count < item2.assetIDs.count
            }
            
            // Finally sort by id ascending
            return item1.id < item2.id
        }
        
        // Rule 10. Selection - take items in order until goal is met or maxItems reached
        var selectedItems: [PlanItem] = []
        var selectedPotentialBytes: Int64 = 0
        var unmetReason: PlanUnmetReason? = nil
        
        for item in items {
            if selectedItems.count >= maxItems {
                unmetReason = .limitedByMaxItems
                break
            }
            
            // Only count A and B tier items toward the goal
            if item.tier == .a || item.tier == .b {
                if selectedPotentialBytes < goal.targetLogicalBytes {
                    selectedItems.append(item)
                    if let bytes = item.potentialBytes {
                        selectedPotentialBytes += bytes
                    }
                } else {
                    // Goal already met, just add the item to maintain order (but not count it toward goal)
                    selectedItems.append(item)
                }
            } else {
                // Tier C items are added after counting items but only if there's room
                if selectedItems.count < maxItems {
                    selectedItems.append(item)
                } else {
                    unmetReason = .limitedByMaxItems
                }
            }
        }
        
        // If we didn't meet the target even with all items, set unmet reason
        if selectedPotentialBytes < goal.targetLogicalBytes && !selectedItems.isEmpty {
            unmetReason = .notEnoughKnownEvidence
        }
        
        // Rule 11. Coverage for unknown size targets
        for item in items {
            coverage.unknownSizeTargets += item.unknownSizeCount
        }
        
        return GoalPlan(
            items: selectedItems,
            potentialKnownBytes: selectedPotentialBytes,
            attainableFromKnownEvidence: selectedPotentialBytes >= goal.targetLogicalBytes,
            unmetReason: unmetReason,
            coverage: coverage
        )
    }
    
    private static func getTier(for kind: PlanKind) -> PlanTier {
        switch kind {
        case .verifiedExact:
            return .a
        case .screenshots, .largeVideo, .largeFile:
            return .b
        case .similarReview:
            return .c
        }
    }
}
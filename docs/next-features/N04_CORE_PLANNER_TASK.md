# Task card: N04 Storage Goal Planner — Core logic only (N04.1 + N04.3)

Written 2026-11-14 by the orchestrator for a coding agent. Source spec:
`docs/CleanSlate_Implementation_Specs_V2/features/N04-storage-goal-planner.md` (§2, §3, §7, §8). This card is the
exact contract; where the spec and this card differ, follow this card.

**Scope:** pure Swift in the `CleanSlateCore` package ONLY. No App code, no UI, no database, no PhotoKit, no simulator.
**Files to create (and nothing else):**
- `Core/Sources/CleanSlateCore/StoragePlan.swift`
- `Core/Tests/CleanSlateCoreTests/StoragePlanTests.swift`

**The only command you need:** `swift test --package-path Core` (also run `make lint` before committing).

The planner is a **review-queue selector**. It never deletes, never approves, never claims freed space. It answers:
"if the user reviews these items, how many *verified* bytes could they potentially remove, and what is unknown?"

---

## 1. Types (copy exactly; all `public`, all `Sendable`, `Equatable`)

```swift
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
    public init(id: String, kind: PlanKind, keepers: [AssetRecord], targets: [AssetRecord])
}

public struct StorageGoal: Codable, Sendable, Equatable {
    public let id: UUID
    public let targetLogicalBytes: Int64  // user request, NOT a free-space promise
    public let scopeID: String
    public let createdAt: Date
    public init(id: UUID, targetLogicalBytes: Int64, scopeID: String, createdAt: Date)
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
    public static func build(goal: StorageGoal, sources: [PlanSource], maxItems: Int) -> GoalPlan
}
```

## 2. Rules (implement in this order; each rule has tests below)

1. **Invalid goal.** If `goal.targetLogicalBytes <= 0` or `maxItems <= 0`: return an empty plan, `potentialKnownBytes = 0`,
   `attainableFromKnownEvidence = false`, `unmetReason = .invalidTarget`.
2. **Tier** from kind: `verifiedExact → .a`; `screenshots, largeVideo, largeFile → .b`; `similarReview → .c`.
3. **Deterministic order of sources** before any counting: sort by `(tier, id)` ascending. The input order must never
   change the output.
4. **Keepers are never targets.** Collect every `keepers` asset id from ALL sources first. Any target whose id is in that
   set is dropped (`targetsSkippedKeptElsewhere += 1`).
5. **Protected targets are never counted.** A target with any flag in `PreservationFlag.hard` is dropped
   (`targetsSkippedProtected += 1`). (N05's `.userProtected` is in `hard`.)
6. **Count each asset once.** Walk sources in rule-3 order; keep a `Set<String>` of claimed target ids. A target already
   claimed by an earlier source is dropped from the later source (`targetsSkippedDuplicate += 1`). The earlier tier wins.
7. **Item bytes.** For tiers A and B: `potentialBytes` = sum of `verifiedLogicalBytes` of the remaining targets that have a
   value; if none has a value, `potentialBytes = nil`. `unknownSizeCount` = remaining targets with nil size (never treat
   nil as 0 bytes, never guess). For tier C: `potentialBytes = nil`, `countsTowardGoal = false` (sizes still go to
   `unknownSizeCount` only if nil).
8. **Drop empty items.** A source left with zero targets produces no item. `sourcesConsidered` counts every input source.
9. **Item order in the plan:** `tier` ascending, then `potentialBytes` descending (nil last), then `assetIDs.count`
   ascending (less review work first), then `id` ascending.
10. **Selection.** Take items in rule-9 order. Add counting items (tiers A/B) while `potentialKnownBytes <
    goal.targetLogicalBytes` — the item that crosses the target IS included, then stop adding A/B items. Then append tier C
    items (not counted) while there is room. Never exceed `maxItems` in total. If `maxItems` stops A/B selection before
    the target is reached, `unmetReason = .limitedByMaxItems`; else if all A/B items were added and still short,
    `unmetReason = .notEnoughKnownEvidence`.
11. `coverage.unknownSizeTargets` = sum of `unknownSizeCount` over ALL produced items (selected or not).
12. Complexity O(N log N) in total targets. No recursion, no media, no I/O, no `Date()` calls (use the goal's values).

## 3. Tests to write in `StoragePlanTests.swift` (XCTest; write them FIRST, see them fail, then implement)

Helper: `func rec(_ id: String, _ bytes: Int64?, _ flags: Set<PreservationFlag> = []) -> AssetRecord`
(revision `"r-\(id)"`), and a goal helper with a fixed UUID and `Date(timeIntervalSince1970: 0)`.

| Test name | Setup | Must assert |
|---|---|---|
| `testInvalidTargetReturnsEmptyPlan` | target 0 | items empty, unmetReason == .invalidTarget |
| `testZeroMaxItemsIsInvalid` | maxItems 0 | unmetReason == .invalidTarget |
| `testExactGroupCountsOnlyTargetsNotKeeper` | exact: keeper K 100, targets c1 40, c2 60 | potentialKnownBytes == 100 (not 200) |
| `testOverlappingAssetCountedOnce` (spec Gherkin 1) | same asset X 500 as exact target AND screenshot target AND largeFile target; goal 1 GB | potentialKnownBytes == 500; exact item has X; screenshot/largeFile items absent or without X; targetsSkippedDuplicate == 2 |
| `testProtectedTargetNeverCounted` (spec Gherkin 4) | target with `.userProtected`, 50 bytes | not in any item; targetsSkippedProtected == 1 |
| `testEveryHardFlagIsSkipped` | one target per flag in `PreservationFlag.hard` | all skipped; count == hard.count |
| `testConditionalFlagIsNotSkippedByPlanner` | target with `.livePhoto` | it IS counted (commit-time policy still decides later) |
| `testKeeperOfAnotherSourceIsNeverATarget` | exact A keeps P; screenshot source targets P | P not counted; targetsSkippedKeptElsewhere == 1 |
| `testUnknownSizeIsUnknownNotZero` (spec Gherkin 3) | largeVideo target with nil size | item potentialBytes == nil, unknownSizeCount == 1, potentialKnownBytes == 0, coverage.unknownSizeTargets == 1 |
| `testMixedKnownAndUnknownSizes` | targets 30, nil, 20 | potentialBytes == 50, unknownSizeCount == 1 |
| `testSimilarReviewNeverCountsTowardGoal` | similarReview with sized targets | countsTowardGoal false, potentialBytes nil, potentialKnownBytes unchanged |
| `testTierOrderThenBytesThenSizeThenID` | mix of kinds/sizes/ties | exact order of item ids as rule 9 |
| `testStopsAfterItemThatCrossesTarget` | items 60, 50, 40; goal 100 | selected A/B ids == the first two; attainable true; unmetReason nil |
| `testUnmetWhenEvidenceShort` | items total 140; goal 500 (spec §8 fixture idea) | attainable false, unmetReason == .notEnoughKnownEvidence, potentialKnownBytes == 140 |
| `testUnmetWhenMaxItemsReached` | 5 items of 10; goal 100; maxItems 2 | items.count == 2, unmetReason == .limitedByMaxItems |
| `testTierCAppendedAfterCountingItemsWithinMaxItems` | goal met by 1 item; 3 similar; maxItems 3 | 1 counting + 2 tier C |
| `testInputOrderDoesNotChangeOutput` | same sources shuffled 20 times (seeded, deterministic shuffle) | all plans == first plan |
| `testEmptySourcesProduceNoItems` | sources all filtered out | items empty; sourcesConsidered == input count |
| `testExpectedRevisionsMatchRecords` | any | expectedRevisions[id] == "r-\(id)" for every asset in every item |
| `testLargeInputPerformance` | 250,000 targets across 50,000 sources (generated, no randomness without a fixed seed) | completes; use `measure {}` OR assert elapsed < 5 s on this Mac |

## 4. Done means

- `swift test --package-path Core` → all tests pass, **0 failures** (the existing 171 tests must still pass).
- `make lint` passes.
- Only the two files above are added. Nothing else changed (except appending to `docs/VALIDATION_LOG.md`).
- Commit on branch `feature/N04-core-planner`, push that branch. Do NOT merge to main.

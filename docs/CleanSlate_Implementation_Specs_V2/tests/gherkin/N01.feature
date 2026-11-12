Feature: N01 - N01 — Moment Intelligence / Best-Shot+ with multiple keepers

Scenario: A-B and B-C similarity does not erase a unique A-C difference
 Given frames A, B, C where A resembles B, B resembles C, but A is distinct from C
 When Moment Intelligence proposes a keeper set
 Then no removal is considered proven by a transitive path
 And A and C may both remain as keepers
 And every staged removal requires direct comparison to a surviving keeper

Scenario: Changing a keeper invalidates prior removal dependencies
 Given I staged removal of B based on keeping A
 When I remove A from the keeper set
 Then B returns to undecided unless another surviving keeper has direct qualifying evidence

Scenario: A protected image remains safe
 Given a favorite, edited RAW or manually protected asset inside a moment
 When keeper ranking runs
 Then its protected status overrides numeric quality ranking for removal eligibility

Scenario: App closes with a half-reviewed moment
 Given a 20-photo draft with 6 undecided frames
 When the app is killed and relaunched
 Then only valid explicit Keep intentions can be restored
 And no stale deletion choice becomes an approved tray item

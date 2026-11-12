Feature: N04 - N04 — Evidence-Based Storage Goal Planner

Scenario: A plan never double-counts overlapping candidates
 Given a verified exact duplicate is also a screenshot and a large file
 When I build a 1 GB goal plan
 Then its logical bytes appear at most once in the known-potential total
 And all review routes lead to the same underlying asset and revision

Scenario: The user cancels Apple's Photos confirmation
 Given 250 MB is approved in the deletion tray
 When the Photos confirmation is cancelled
 Then verified removed logical bytes remain unchanged
 And the goal continues to say 'potential' rather than 'freed'

Scenario: An unavailable iCloud original has no verified size
 Given the asset is visible as a thumbnail but the original is not local
 When I generate a plan without opting into iCloud original downloads
 Then the asset is counted as unknown, not as zero or guessed bytes

Scenario: A protected target becomes unavailable for planning
 Given a plan item references an asset newly protected by N05
 When the plan is resumed
 Then the item is invalidated
 And it cannot be approved to the deletion tray

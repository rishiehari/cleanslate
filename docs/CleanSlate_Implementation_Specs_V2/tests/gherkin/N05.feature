Feature: N05 - N05 — Never Suggest / Protected Rules

Scenario: Protection invalidates an already approved deletion
  Given a byte-verified duplicate is in the deletion tray
  When I protect the candidate asset
  Then the tray entry is marked Needs Attention before any PhotoKit deletion call
  And the candidate is not removed from Photos

Scenario: Protection changes after asynchronous full-resource hashing
  Given deletion verification is reading original resources
  When a protection rule is created for the candidate
  Then the final protection-version check blocks the commit
  And no mutation of Photos occurs

Scenario: Limited authorization cannot establish album membership
  Given the user only granted limited Photos access
  And album-level rule evaluation is unavailable
  When a pending candidate could be affected by an album rule
  Then the approval cannot advance to deletion
  And an explanation offers management of Photos access

Scenario: Removing a rule does not resurrect an old approval
  Given an old tray entry was invalidated by a protection rule
  When I disable the rule
  Then the old entry still requires a new explicit review

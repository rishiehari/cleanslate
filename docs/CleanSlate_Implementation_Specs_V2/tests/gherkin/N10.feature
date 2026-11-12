Feature: N10 - N10 — Local Taste Personalization, transparent and resettable

Scenario: A learned score cannot make a near duplicate auto-deletable
 Given a similar photo with incomplete pairwise evidence
 And a personalization model strongly prefers its neighbor
 When the user opens the review group
 Then near-duplicate deletion remains manual
 And SafetyPolicy and approved removal IDs are unchanged

Scenario: Consent disabled means no data collection
 Given Personalization is OFF
 When the user makes 100 Keep/Skip/Favorite choices
 Then no training examples are stored
 And queue ordering remains the neutral baseline

Scenario: Personalized model fails holdout evaluation
 Given enough explicit training decisions
 When the model's holdout score is worse than the neutral order
 Then the new weights are rejected
 And the user sees Standard ordering

Scenario: User resets the model
 Given a previously trained local model
 When I tap Forget learned preferences
 Then local examples, weights and cached personalized order are purged
 And Photos favorites, protected rules and deletion receipts remain unchanged

Scenario: An app update changes feature dimensions
 Given an old weight vector with a different feature_version
 When the new version starts
 Then the model is stale and ignored, never partially decoded

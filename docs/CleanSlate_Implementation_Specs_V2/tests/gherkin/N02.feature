Feature: N02 - N02 — Similar and Re-encoded Video Finder

Scenario: Re-encode is not byte identity
 Given visually similar videos with different encodings and resource bytes
 When they are compared
 Then their relation is likelyReencodedForReview or inconclusive
 And neither is preselected for removal

Scenario: Same opening, different ending
 Given two clips with an identical opening but distinct final scene
 When normalized frame sampling runs
 Then the comparator does not label them verified exact or interchangeable
 And the review shows different-ending evidence

Scenario: Cloud-only video by default
 Given a Photos video whose original is only in iCloud
 And the user has not opted into network verification
 When the video scan reaches it
 Then there is no automatic download
 And it is counted as unavailable rather than a completed comparison

Scenario: Thermal pause survives app exit
 Given a long video analysis batch
 When the governor reports serious thermal state
 Then the job checkpoints and pauses with a reason
 And resuming does not duplicate approved reviews or Photos changes

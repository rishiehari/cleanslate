Feature: N06 - N06 — Mistake Finder: evidence-based blur, exposure and tiny-image review

Scenario: Artistic blur does not imply deletion
 Given a deliberately shallow-depth portrait with a soft background
 When Mistake Finder analyzes the image
 Then any warning is described as a possible issue, not a deletion fact
 And automaticRemovalAllowed is false
 And no image is staged without explicit user review

Scenario: Source resolution is independent of preview size
 Given a 4032x3024 original rendered in a 256px preview
 When resolution quality is calculated
 Then source dimensions are used
 And the photo is not called low-resolution because of the preview

Scenario: No usable quality evidence
 Given Vision and raster analysis both fail for an iCloud-only image
 When the quality review queue is refreshed
 Then its status is unknown or skipped
 And its inability to be evaluated is included in coverage

Scenario: User marks warning irrelevant
 Given a dark photo was shown as 'possibly very dark'
 When the user chooses Keep and dismiss warning
 Then the same asset revision is not re-suggested in the active review scope
 And a subsequent edit may trigger a new evidence version but not an automatic removal

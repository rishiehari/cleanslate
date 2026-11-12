Feature: N07 - N07 — Screenshot Intelligence: repeat detection, changed-text protection, and review packs

Scenario: Single-digit difference blocks a repeated-screenshot claim
 Given two image-identical boarding passes differ only by gate "B12" versus "B13"
 When Screenshot Intelligence compares them
 Then evidence is changedInformation or inconclusive, not equivalent
 And neither photo is preselected to remove

Scenario: OCR cannot read a low-contrast screenshot
 Given a valid screenshot with unreadable text
 When OCR fails or confidence is below the validated gate
 Then the result remains reviewOnly with an uncertainty explanation

Scenario: User keeps both sides of a repeated pair
 Given a displayed screenshot pair
 When the user selects Keep both
 Then no item is added to the tray
 And the local session counts one completed review

Scenario: Permission revoked between analysis and approval
 Given a cached screenshot review pack
 When Photos authorization is revoked
 Then approval is blocked, previews are cleared and scope is marked stale

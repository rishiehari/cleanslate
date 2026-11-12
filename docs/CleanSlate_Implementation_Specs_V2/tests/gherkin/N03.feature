Feature: N03 - N03 — Compression Lab: verified replacement, no silent loss of originals

Scenario: Canceling export cannot remove the source
 Given a local video and a compression trial in progress
 When the user cancels or the process is killed
 Then the source Photos asset remains untouched
 And no source deletion entry appears in the tray

Scenario: A new file is not yet verified in Photos
 Given a completed validated export
 When Photos creation reports success but the created asset cannot be refetched
 Then the job becomes uncertain
 And the original is never offered for deletion

Scenario: Video output is larger than original
 Given a 100MB source and a 125MB output
 When output validation finishes
 Then the UI says there is no useful size saving
 And the default action is Keep original

Scenario: Live Photo transform is not compression
 Given a Live Photo with separate motion resource
 When a generic compression screen attempts to process it
 Then the V1 pipeline rejects it as unsupported
 And neither motion nor original still image is modified

Scenario: User saves a validated compressed copy
 Given successful file validation and explicit Save copy confirmation
 When Photos stores and refetches the new asset
 Then the receipt says 'Copy saved; original unchanged'
 And deleting the original requires a separate existing tray review and Apple confirmation

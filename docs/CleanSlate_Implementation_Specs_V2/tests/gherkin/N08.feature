Feature: N08 - N08 — Album Inbox: nondestructive photo sorting and organization

Scenario: Full-access album filing is verified
 Given a real Photos album named Vacation and an accessible photo not in it
 When I choose Vacation and confirm Add
 Then CleanSlate requests a Photos album mutation
 And shows Filed only after refetch confirms membership
 And the photo remains in All Photos

Scenario: Limited permission does not impersonate Apple albums
 Given authorization is limited
 When I open Album Inbox
 Then no unsupported user album enumeration is attempted
 And local labels are explicitly shown as on-device-only

Scenario: Favorite invalidates pending removal eligibility
 Given an asset is approved for removal elsewhere
 When Album Inbox successfully marks it Favorite
 Then the pending deletion is invalidated for review
 And the original cannot be committed under the stale approval

Scenario: Interrupted album write is reconciled
 Given Photos album add succeeded but the app quit before recording success
 When the app resumes
 Then it refetches membership before any retry
 And no item is counted twice

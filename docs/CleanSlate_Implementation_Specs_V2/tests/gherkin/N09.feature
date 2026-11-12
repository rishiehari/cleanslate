Feature: N09 - N09 — Rescue Gems: rediscover photographs worth keeping

Scenario: No photo access still demonstrates value
 Given Photos permission is denied
 When I open Rescue Gems
 Then I can interact with bundled sample photos
 And no real Photos API write or event is triggered

Scenario: Favoriting is a real Photos mutation
 Given an accessible unfavorited photo
 When I tap Favorite and confirm
 Then the Photos favorite flag is changed through the authorized client
 And the app shows confirmed only after a fresh snapshot verifies it

Scenario: Favorite invalidates deletion approval
 Given a candidate appears in an existing deletion tray
 When I mark it Favorite from Rescue Gems
 Then the stale tray entry requires renewed safety review

Scenario: A batch does not fake library coverage
 Given only 100 of 20,000 photos have been indexed
 When the app proposes 10 gems
 Then the UI attributes the selection to the 100 checked photos
 And never says it picked the best ten from 20,000

# First-session UX, onboarding and local engagement specification

## A. Product objective

**Outcome:** a new user understands what CleanSlate will *and will not* do, sees genuine value on the first attempt, and can exit without deleting anything. The experience is free without payment gates, advertisements, trials, accounts or tracking. Some personal libraries contain no exact duplicates; meaningful first-use outcomes may be a correct Keep both, a protected family picture, a useful screenshot difference, one photo favorite or one organized album.

## B. End-to-end journey with conditional branches

### T=0–30 seconds: permission-free practical demonstration

On launch, a one-screen promise: **"Find the copies. Keep the moments. You decide."** Two concise guarantees immediately visible: "Photo analysis stays on this device" and "CleanSlate can't delete without your approval and Apple's confirmation". Buttons: **Try with example photos** (primary) and **Check my photos** (secondary). Existing onboarding may already display three pages; integrate instead of adding another mandatory flow. `Try` loads 4–6 bundled dummy scenes with choices: protect birthday shot, keep two different expressions, compare ticket screenshot with changed boarding gate. The demo must be interactive within 15–20 seconds of app launch on a supported phone, with actual timing measured. This is *fake data explicitly labeled*, not a misleading claimed real scan. Record no simulated progress into real impact.

### T=30 seconds–3 minutes: intent and scoped real value

Ask user intent in one compact view: **Find storage**, **Review similar moments**, **Organize & rediscover**. Map to N04/N01/N08 or existing categories depending on feature flags. Request Photos authorization *in context*, offer limited Photos access as a respected choice, and use existing F04 Recent-100 scope **only if it has actually shipped and passed its device gates**. If not, explain current scan scope and give a deliberate Start Scan action; never mislabel a full scan as Recent-100. Show actual progress with stage, examined count, unavailable cloud-only count, pause and cancel; don't invent seconds remaining. As results appear, show the highest **safely explainable** item first, not highest deletion pressure.

Decision card: a pair with clearly different expressions may lead to **Keep both**. App responds "Both kept. Nothing added to the tray." A true exact pair can lead to Add to tray after explicit photo review; app responds "One photo ready in your tray. It's still in Photos." A single protected item responds "Protected from CleanSlate suggestions on this device." Album filing responds "Added to Vacation" only after PhotoKit verification. The user should see one true outcome even if no bytes are recoverable.

### T=3–10 minutes: controlled review without fatigue

Home shows **at most three** next actions: highest evidence quality, best known potential logical bytes, and one positive action (Gems or Album). User may open Swipe n Save for two-photo decisions, N07 screenshot repeated packs, or N05 protection. Every review screen has Skip, Keep/Keep both, and a clearly labeled Done for now. Session progress counts reviewed groups/items and current **tray-approved** items separately from **verified deleted** results. No "5 GB saved" at approval. At 10 minutes, present a neutral optional summary: "You reviewed 18 photos. 7 are kept safe. 3 are ready in your tray. Nothing has been deleted." CTAs: Review tray / Keep reviewing / Done for now, with Done equally visible.

### Day 2 and week 1

When user voluntarily returns, show meaningful changes from locally known state: "8 new screenshot candidates in your selected scope", "2 new similar moments worth comparing", "3 rediscovered gems", or "Nothing urgent. Your last session is saved." Do not send notifications or badges by default; they are optional future requirements with separate explicit consent. A week-one local recap may show sessions completed, photos reviewed, kept/protected, albums organized, potential bytes seen, approved-to-tray and **confirmed logical bytes removed**. Do not assume a weekly streak or punish skipping. The app should be quiet and useful rather than habit-forming through guilt.

## C. Interaction specification and event semantics

```text
entry(intent?)
  ├─ demo -> local example decisions -> optional start real scan
  └─ real -> contextual authorization -> scoped scan or existing indexed results
      ├─ first meaningful result -> review/keep/protect/organize -> local receipt
      ├─ no candidate -> honest empty + alternative feature
      ├─ partial coverage -> show checked vs unavailable/unknown
      └─ denied -> demo + manage permission explanation

Review choice -> staged draft -> explicit Approve -> DeletionTray
DeletionTray -> explicit user request -> PhotoKit system confirmation -> reconcile
```

A first meaningful result is **not** time of an animation. Define `firstValueEvent` as one of: user explicitly kept a meaningful pair, created a durable user protection rule, successfully added a photo to Photos album, confirmed Favorite, completed a verified exact-duplicate review, or explicitly approved a removal to the tray. A demo first choice is measured separately as `demoFirstAction` and never mixed with real-library value. For active approval, zero deletions can still count as a successful session.

## D. Privacy-preserving local instrumentation

Do not add any vendor analytics network. If we instrument locally for user-visible statistics, define:

```swift
enum LocalImpactKind: String, Codable {
 case demoCompleted, photosIndexed, realReviewCompleted, keptBoth,
      protectionRuleCreated, albumAssignmentVerified, favoriteVerified,
      trayApproval, photoRemovalVerified, resumeAfterPause, resultsUnavailable
}
struct LocalImpactEvent: Codable, Sendable {
 let featureID: String
 let kind: LocalImpactKind
 let dayBucket: Int // local day or UTC epoch day, document timezone rule
 let elapsedMsBucket: Int?
 let countBucket: Int?
 let byteBucket: Int64?
}
```

No event contains asset IDs, exact timestamps, filenames, OCR, GPS, face metadata, photo content, precise dimensions or account IDs. Local impact data is under OS file protection and excluded from backup if it could be personal; make all event collection optional if possible, and expose deletion of local data. Export diagnostics is a **user-initiated** explicit action and must be scrubbed of photo-derived identifiers. A demo event is segregated from real metrics.

## E. Correct formulas

| Metric | Calculation | Limitation |
|---|---|---|
| Time to first demo action | monotonic elapsed time from demo shown to first choice | Not real-library performance |
| Time to first *real* value | app feature opened → confirmed meaningful user action | Dependent on authorization and scan scope |
| Review throughput | finished review decisions ÷ active foreground review minutes | Exclude paused/background time |
| Eligible potential bytes | sum unique eligible measured candidate resource sizes under known scope | Not capacity recovered; overlapping categories deduplicated |
| Tray-approved bytes | measured sizes for approved removal targets not yet committed | May become invalid/stale |
| Verified removed logical bytes | confirmed receipts after Photos re-fetch, excluding uncertain operations | Not local free-space or iCloud quota |
| Local available-capacity delta | OS available space after − before, if measurable | No causal attribution to our operation |
| iCloud quota recovered | **do not calculate / display as a numeric claim** | iCloud sync, shared libraries, Recently Deleted, Optimize Storage |
| Kept-safe count | unique currently protected target candidates in known scope | Counts only accessible, evaluated items |
| Coverage | indexed / analyzed / resource-verified / inaccessible / skipped counts by scope | Never claim global Photos completeness under limited access |

## F. Design experiment and acceptance plan

Conduct a small moderated usability panel (not simulated internal endorsement) on two iPhone sizes and iPad, each with sample and disposable authorized libraries. Tasks: find first useful card, Keep both, Protect a photo, make one exact-copy tray approval, explain whether anything was deleted, and find how to stop the session. Record time, wrong-direction swipes, accidental approval attempts, permission confusion and self-reported confidence. Proposed targets (to be measured): ≥90% correctly distinguish tray approval from deletion; zero destructive actions without two explicit approvals; first bundled-demo choice within 30s on reference device; 80% find Done for now unaided. Report results/uncertainty transparently, not manufactured success metrics.

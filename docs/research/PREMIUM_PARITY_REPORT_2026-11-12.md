# CleanSlate Premium-Parity Deep Research and Implementation PRD

## Executive recommendation

The strongest opportunity is **not to copy subscription cleaners feature-for-feature**. The paid market is largely charging for prioritization, convenience, confidence, compression, swipe workflows, best-shot assistance, and repeat engagement—capabilities that can mostly run on the device. Flic is the clearest proof: its current App Store listing explicitly markets on-device AI, no account, no photo upload, “Likely junk,” similar/blurry grouping, Best 25 rediscovery, storage-target plans, and local preference learning while gating unlimited use behind Premium. citeturn374345view1 CleanMyPhone similarly markets local photo processing while charging for duplicate/similar cleanup, compression, Live Photo conversion, AI organization, and exclusion of Sensitive photos. citeturn374345view0

The architectural direction already in CleanSlate is therefore sound: PhotoKit + Vision + local SQLite, no backend, and a fail-closed deletion pipeline. The current `main` README reports **115 passing Core tests as of November 11, 2026**, a native SwiftUI/PhotoKit/Vision/SQLite implementation, and F01–F03 integration work, while the F03 physical-device stability gate remains incomplete. citeturn854555view0 Existing roadmap work already owns Recent-100, scan progress, first-run trust, impact/activity, coverage, kept-safe, accessibility/localization, Swipe n Save, and an iPad expansion plan, so those should **not** be repackaged as “new” features. citeturn618291view2turn154595view1turn154595view0

The ten features I would commit to are below. The ranking is based on user pain, premium parity, first-session payoff, deletion safety, on-device feasibility, zero-service economics, low-memory performance, maintainability, accessibility, and non-manipulative repeat value.

| Rank | Feature | First-use value | Paid-market analogue | On-device feasibility | Engineering | Principal risk |
|---:|---|---|---|---|---|---|
| 1 | **N04 Free-X-GB Smart Cleanup Plan** | User immediately sees the safest route toward a storage goal | Flic “Need 2/5/10 GB?” | Excellent | S/M | misleading storage claims |
| 2 | **N05 Never Suggest / Protected Rules** | Immediate trust and control | CleanMyPhone Sensitive, Clever Skip List | Excellent | S/M | stale protection rules |
| 3 | **N07 Screenshot Intelligence** | Fast, obvious clutter reduction | Cleanup, CleanMyPhone, Flic, Swipewipe | Excellent | M | OCR-sensitive data |
| 4 | **N01 Moment Intelligence / Best-Shot+** | Strong “this app understands my burst” moment | best-shot systems across premium cleaners | Strong | M/L | overconfident keeper ranking |
| 5 | **N06 Mistake Finder** | Quickly surfaces obvious review candidates | blurry/closed-eye/low-res cleanup | Strong | M | artistic false positives |
| 6 | **N02 Similar & Re-encoded Video Finder** | Large-byte opportunities | Cleanup/Cleansmith similar-video features | Strong, heavier | L | decode/thermal cost |
| 7 | **N03 Compression Lab** | One large video can produce immediate benefit | compression tiers across most premium leaders | Strong | L | fidelity/HDR correctness |
| 8 | **N08 Album Inbox** | Useful even when nothing should be deleted | Slidebox/AirPhoto organization | Strong | M | limited-access album restriction |
| 9 | **N09 Rescue Gems** | Positive payoff instead of deletion-only UX | Flic Best 25, Swipewipe On This Day | Excellent | M | subjective ranking |
| 10 | **N10 Local Taste Personalization** | Improves relevance over repeated use | Flic local taste learning | Strong | L | reinforcing bad preferences |

The implementation sequence should **not** simply follow rank. The repository explicitly mandates serialized, gated work rather than parallel feature sprawl. citeturn154595view3 After F03 and the relevant current roadmap gates are resolved, my recommended sequence is **N05 → N04 → N07 → N06 → N01 → N02 → N03 → N08 → N09 → N10**. Safety/control should precede more persuasive intelligence.

The complete research package is available here:

[Download the full 24-file research/spec bundle](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12.zip)

[Read the consolidated 40,000+ word PRD](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/CLEANSLATE_DEEP_RESEARCH_FULL.md)

[Top-ten feature index](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/README.md)

[120-idea longlist](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/research/LONGLIST_120.md)

[Three-pass selection record](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/research/SELECTION_RECORD.md)

[Coding-agent handoff template](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/handoff/CODING_AGENT_TASK_TEMPLATE.md)

## Repository audit and platform constraints

I audited the current default branch rather than treating the earlier architecture documents as authoritative. The default branch is `main`; the current README describes the active implementation as native SwiftUI with PhotoKit, Vision and SQLite, with no backend, account, subscription, advertising, or photo upload. It also states that the app is **not release-ready** and that the F03 physical-device stability gate remains pending. citeturn854555view0 I deliberately did **not** assert a current HEAD SHA because the web snapshot available to this research pass did not expose a sufficiently trustworthy current commit hash. Every coding-agent task therefore begins with `git rev-parse HEAD` and records the SHA before modifying anything.

The implementation already has meaningful depth. The repo documents deterministic candidate retrieval, resource signatures/ranking and a fail-closed safety policy; a PhotoKit client for permissions, inventory, thumbnails and streamed resource hashes; a resumable scan engine; a local SQLite store; a deletion coordinator with fresh-state checks and exact rehashing; and dashboard/comparison/deletion-review surfaces. citeturn854555view0 Current product documentation already covers exact duplicates, similar photos/bursts, videos, screenshots/screen recordings, large files and deletion receipts. citeturn618291view1

The repo also records important limitations that must remain visible rather than being silently “fixed” by a new feature branch. The current scanner is paged/resumable but not presented as exhaustive; Recent-100 is still planned; iCloud-original downloading is opt-in; and best-shot ranking is heuristic rather than human-calibrated. citeturn854555view0 Existing physical-device validation is especially important because the validation log records Vision feature-print failures in the simulator environment and explicitly requires physical-device evidence for similar-photo behavior. citeturn488078view1

There is also an OS-floor decision that needs to remain explicit. `Core/Package.swift` currently declares an iOS 18 package platform, while product/planning documentation treats an iOS 26 app minimum as provisional/current planning. citeturn795005view0turn618291view1 A coding agent should not silently unify those two numbers merely to use a newer framework.

Apple’s Photos restrictions strongly shape what a trustworthy cleaner can promise. Limited Photos access is a real supported mode; Apple says the app may operate on only the user-selected subset, and in limited mode third-party apps cannot create or fetch user albums. citeturn812237search23 PhotoKit library mutations are made through change requests and system-authorized flows, and deletion ultimately uses PhotoKit’s asset-change APIs. citeturn812237search35turn527385search6 Apple Photos itself can “Merge” duplicates, preserving the highest-quality version and relevant data, but CleanSlate does not receive a corresponding public third-party merge operation; it must instead preserve a keeper and explicitly delete reviewed copies. citeturn527385search0turn618291view1

iCloud semantics also require careful language. When iCloud Photos is enabled, deleting an item synchronizes that deletion to other devices using the same account, and deleted items generally remain recoverable in Recently Deleted for 30 days. citeturn527385search0 PhotoKit lets an app decide whether a resource request may trigger an iCloud download through `isNetworkAccessAllowed`; CleanSlate’s current opt-in-only policy is the correct default. citeturn812237search3 What CleanSlate **cannot** safely claim is that a particular logical-byte deletion directly reclaimed an equal amount of local free space or iCloud quota.

## Competitive evidence: what premium cleaners really monetize

The market research covered 15 relevant apps plus Apple Photos. The most important result is that the subscription leaders are not generally selling an indispensable cloud algorithm. They are selling **friction reduction**.

Cleanup: Phone Storage Cleaner currently advertises duplicate photos/videos, similar screenshots and lookalike videos, “Best” marking, bulk screenshots, video compression, contacts/email cleanup, a vault and widgets. Its US App Store page identifies it as iPhone-only, shows a subscription/free-trial model, and its App Privacy disclosure lists purchases, identifiers and usage data among tracking-related categories. citeturn606790search0 Cleaner Kit similarly advertises duplicate/blurry detection, broad storage cleanup and subscription access; its current release also includes Live Photo conversion. Its App Store reviews include users specifically asking for better previews before committing to deletions—an anecdotal but useful reminder that review quality matters. citeturn606790search1

CleanMyPhone is currently available for iPhone and iPad. It advertises duplicates/similars, blurred images, screenshots, large videos, compression, Live Photo conversion, AI organization and Sensitive-photo exclusion, all while stating that photo processing stays on-device. citeturn374345view0 That combination is important: privacy-preserving local compute and paid premium positioning are not mutually exclusive. CleanSlate can offer the same local-compute benefit without charging.

Swipewipe’s current iPhone/iPad listing focuses on engagement: month-by-month cleanup, simple swipe decisions, On This Day, widgets, streaks, an interactive map, similar/blurry/screenshots and a “decide later” concept. Its App Privacy disclosure lists identifiers and usage data among tracking categories. citeturn606790search3 The lesson worth borrowing is **session structure and rediscovery**, not streak pressure.

Slidebox is a stronger organization benchmark than an AI benchmark. It is currently listed for iPhone and iPad, with swipe deletion, album organization, similar-photo comparison, favorites, undo and progress statistics. Its US listing currently states $4.99 monthly and $49.99 annual subscriptions and also advertises a one-time full-version purchase. citeturn374345view2 That product demonstrates that users will pay simply to make ordinary PhotoKit organization substantially faster.

Flic is the most strategically useful competitor. Its current listing says that on-device intelligence scores the camera roll, surfaces likely junk, groups similar/blurry photos, picks sharp candidates, finds screenshots and large videos, resurfaces a daily Best 25, learns taste from keep/delete/favorite decisions, splits cleanup by month, and builds 2/5/10 GB storage-target plans. It says no account and no photo uploads, and Premium gates unlimited swiping and the AI features. citeturn374345view1 That is almost a direct demonstration that **CleanSlate can provide premium-class value without a server bill**.

Clever Cleaner advertises similar-photo grouping, Best Shot, Smart Cleanup, compression, Live Photo handling, a Skip List and swipe mode; some storefronts advertise iPad compatibility mode rather than a deeply native iPad workspace. citeturn425653search3turn425653search29 One App Store review alleges destructive misclassification; that is anecdotal and cannot be treated as proof about the product, but it reinforces why CleanSlate’s near-duplicate safety contract should remain stricter. citeturn425653search3

Cleansmith is the broadest technical benchmark. Its listing advertises local/offline processing, similar-photo/video search, closed-eye and low-resolution categories, compression, Live Photo transformation, spatial-media support, filters, storage monitoring and many utility functions. citeturn374345view3 Its own App Store review/developer-response history also illustrates how hard compression correctness is: the developer discusses cases where HEIC→JPEG output can become larger and a release where bulk compression froze, later fixed. citeturn374345view3 That is exactly why CleanSlate’s compression feature is specified as a transactional **create → verify → reconcile → optionally review original** workflow, not “tap once and trust us.”

The broader benchmark set also includes Phone Cleaner/Clean Up Storage, Easy Cleaner, Cleaner Guru, phoom, AI Cleaner, Photo Cleaner powered by AI and AirPhoto. Across those products the recurring paid themes remain similar: unlimited cleanup, best-shot assistance, compression, smart grouping, swipe throughput, large-file prioritization and organization. The detailed source-by-source comparison, including storefront caveats and labels for verified versus advertised claims, is in [the competitive research document](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/research/2026-11-premium-competitors.md).

## The hundred-idea funnel and why these ten survived

I generated **120 distinct candidate ideas**, rather than claiming an unspecified “hundreds.” They span quality/similarity, video intelligence, screenshot/document intelligence, storage transforms, organization, engagement/rediscovery, personalization, privacy/safety, accessibility, iPad, and release operations. The complete auditable list is in [LONGLIST_120.md](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/research/LONGLIST_120.md).

The selection used three reproducible passes. **Pass one** scored pain severity, premium-market gap and first-session value. **Pass two** scored on-device/privacy compatibility, destructive-safety compatibility and public-API feasibility. **Pass three** scored zero-service sustainability, maintainability, low-memory performance and respectful repeat value. The normalized score is out of 100; ties favor lower destructive risk, then faster first-session value. These are planning judgments, not empirical product measurements.

The top scores were N04 storage-goal planning at 93, N05 protection rules at 91, N07 Screenshot Intelligence at 91, N09 Rescue Gems at 91, N01 Moment Intelligence at 88, N06 Mistake Finder and N08 Album Inbox at 86, N10 Local Taste at 85, N02 similar-video detection at 81 and N03 Compression Lab at 79. The lower raw score for compression is intentional: it has enormous storage upside but substantially more fidelity, thermal, disk-space and rollback risk.

The process also rejected or deferred several superficially attractive ideas. Auto-delete of visually similar photos was disqualified because it conflicts with the current safety contract. “Merge duplicates exactly like Apple” was rejected because third-party PhotoKit does not expose Apple Photos’ native merge behavior. A private vault, email cleaner, contact cleaner, magic eraser and VPN-like utilities were rejected as mission creep. A full iCloud-quota meter was rejected because attribution would be misleading. Cloud sync and hosted personalization were rejected because they violate the zero-service-cost goal. Automatic downloading of iCloud originals was rejected because it conflicts with the current opt-in policy. Streaks and leaderboards scored reasonably on engagement mechanics but were deliberately rejected as a poor ethical/product fit.

The selection review used ten published adversarial lenses: principal iOS/API engineering, PhotoKit/data integrity, CV/ML calibration, privacy/security, low-memory performance, iPad interaction, accessibility, QA/device validation, release engineering and product ethics. This is a decision log—not hidden chain-of-thought—and every resulting constraint is encoded in the specs.

## Agent-ready specification for the ten features

### N04 — Free-X-GB Smart Cleanup Plan

The user chooses a goal—say 1 GB, 2 GB, 5 GB or custom—and CleanSlate composes a review plan from evidence it **already has**. Flic currently markets this exact benefit as a Premium capability: choose a storage target and it builds a deck ordered around the goal. citeturn374345view1

The implementation is primarily a local optimizer, not a new scanner. It queries indexed exact duplicates, screenshots, large files, reviewable similar groups and later compression opportunities. Every candidate has a conservative logical-byte benefit, risk class and review cost. Protected/stale/unknown candidates are excluded. Exact duplicates appear first; similar media remains manual review. The UI says “up to 612 MB potentially removable,” never “612 MB recovered.”

On iPhone this is a compact deck with a progress header and one decision at a time. On iPad it becomes a persistent three-column plan: category/sidebar, plan items, detailed comparison. SQL assembly should be able to plan from a 250k-row index without decoding media; images load only when visible.

[Full N04 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N04-free-x-gb-smart-cleanup-plan.md)

### N05 — Never Suggest / Protected Rules

This is the trust multiplier. CleanMyPhone currently advertises a Sensitive-photo concept, while Clever Cleaner advertises a Skip List. citeturn374345view0turn425653search3 CleanSlate should offer a stronger local variant: “Never suggest this photo,” plus date-range and album-level protection where full PhotoKit access permits it.

Protection precedence is explicit: immutable safety rules → user asset protection → album/date rules → favorite/edit/special-resource policy → category setting. A protected item disappears from delete recommendations but remains visible in “Kept safe” explanations.

Limited Photos access imposes a real constraint: album rules cannot be fully supported because Apple says third-party apps cannot create or fetch user albums in limited mode. Asset/date protection still works. citeturn812237search23

[Full N05 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N05-never-suggest-protected-rules.md)

### N07 — Screenshot Intelligence

The existing screenshot feature becomes meaningfully premium-class by adding on-device OCR and similarity grouping. Vision provides on-device text recognition through its text-recognition request APIs. citeturn812237search2

Raw OCR text should **not** be stored. The analyzer normalizes text in memory, creates a salted non-reversible text fingerprint plus coarse category features, then discards the recognized strings unless the screenshot is actively being viewed. Visual feature prints + text fingerprints + temporal proximity group repeated screenshots while protecting changed information.

A high-value first-use demo shows three nearly identical boarding-pass screenshots and a fourth with a changed gate/time. CleanSlate should visibly show that the changed screenshot is not considered equivalent. That communicates both intelligence and caution in under 30 seconds.

[Full N07 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N07-screenshot-intelligence.md)

### N01 — Moment Intelligence / Best-Shot+

Vision already provides image feature prints, image-aesthetics scoring and face-capture-quality analysis. Face-capture quality is a holistic signal influenced by characteristics such as focus, lighting and positioning; it is not an oracle for which family memory should survive. citeturn794440search2turn794440search3turn794440search4

The new algorithm therefore uses **multi-keeper constrained ranking**. It begins with mandatory keepers, then scores technical quality, then adds photos until every materially distinct expression, subject configuration or composition is represented. Ambiguity triggers abstention. It never assumes one burst equals one keeper.

The first demo should deliberately show four similar family frames and conclude: “CleanSlate recommends keeping two.” That is a much stronger trust demonstration than “we picked the sharpest.”

[Full N01 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N01-moment-intelligence-best-shotplus.md)

### N06 — Mistake Finder

Cleaner Kit and CleanMyPhone market blurry-photo cleanup, while Cleansmith advertises closed-eye and low-resolution filtering. citeturn606790search1turn374345view0turn374345view3 CleanSlate should implement this as **independent evidence channels**, not one opaque “junk” score.

Signals can include downscaled sharpness, black/white histogram extremes, pixel resolution and Vision face-capture quality. Artistic blur, night photography and uncertain face cases cause abstention. The app shows reason chips such as “possible motion blur,” “very low resolution” or “very dark,” and every item remains a review decision.

[Full N06 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N06-mistake-finder.md)

### N02 — Similar & Re-encoded Video Finder

Cleanup and Cleansmith explicitly advertise similar/lookalike video cleanup. citeturn606790search0turn374345view3 This is one of CleanSlate’s largest likely space-saving opportunities and also one of its easiest ways to burn battery if implemented badly.

Candidate generation should bucket by duration, dimensions, creation neighborhood and size ratio. Only candidate pairs are decoded. `AVAssetImageGenerator` can extract frames from selected points in a video. citeturn812237search4turn812237search7 Sample 5–9 normalized timestamps, compute downscaled image-feature evidence, compare temporal alignment and add duration/audio guards. Never run all-pairs video analysis.

Similarity remains review-only. Exact video equivalence still requires resource verification. Phone decoding should default to one video at a time on memory-constrained devices; iPad concurrency can increase only after measurement.

[Full N02 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N02-similar-re-encoded-video-finder.md)

### N03 — Compression Lab

Premium cleaners repeatedly monetize video/photo compression and Live Photo transformation. CleanMyPhone explicitly advertises video compression and Live→still conversion; Cleaner Kit’s current release also advertises converting Live Photos to still images. citeturn374345view0turn606790search1

CleanSlate’s implementation needs transactional semantics. A compression job exports to temporary app storage, validates that output decodes, verifies duration/dimensions/audio/HDR-relevant metadata, creates the replacement in Photos, reconciles the new asset, and **only then** offers the original to the existing tray flow. PhotoKit can provide an export session for video assets, while AVFoundation supplies the export machinery. citeturn812237search6turn812237search8

Live→still should not be labeled “compression.” It is a semantic transform that throws away motion and requires its own explicit confirmation.

[Full N03 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N03-compression-lab.md)

### N08 — Album Inbox

Slidebox’s core value is not exotic AI; it is faster photo organization. Its current listing advertises one-tap album sorting, swipe cleanup, similar comparison, favorites and undo. citeturn374345view2

CleanSlate should add a non-destructive Inbox: recent/unorganized accessible assets can be filed into an existing/new album, favorited, skipped or opened in Photos. This gives users meaningful value even when there is nothing worth deleting.

This is also where the iPad version can be substantially better than competitors that merely enlarge an iPhone interface: albums in a sidebar, unorganized assets in the middle column, large detail on the right, keyboard shortcuts and drag/pointer affordances. Under limited Photos access, album browsing/creation must degrade gracefully because Apple restricts those APIs. citeturn812237search23turn812237search37

[Full N08 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N08-album-inbox.md)

### N09 — Rescue Gems

Flic currently markets Best 25—strong photos the user never favorited—and Swipewipe markets On This Day rediscovery. citeturn374345view1turn606790search3 This addresses a weakness in cleanup apps: if every interaction is about deletion, the app becomes emotionally associated with risk.

Rescue Gems samples across time buckets, uses cached quality evidence and diversity selection, and surfaces 3–25 “worth another look” images. It does not assert objective beauty. One tap can Favorite the photo in Photos. Weekly recap is local and optional.

This feature should deliberately celebrate **kept memories** more than bytes removed.

[Full N09 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N09-rescue-gems.md)

### N10 — Local Taste Personalization

Flic explicitly advertises local preference learning from keeps, deletes and favorites. citeturn374345view1 CleanSlate can implement a simpler and more transparent version without a large model.

The first implementation should be a tiny local ranking/calibration model over bounded feature vectors. It is opt-in, resettable, trained only after enough explicit decisions, and evaluated on a local holdout slice. It may reorder review queues and adjust explanations; it can **never** change protection rules, similarity eligibility, keeper invariants or deletion defaults.

Core ML can remain an optional implementation path, but it is not required: Apple’s Core ML is designed for on-device inference and can support private offline ML workloads. citeturn794440search6 A small transparent Swift model is easier to debug and safer for V1.

[Full N10 implementation specification](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/N10-local-taste-personalization.md)

Every one of those specs contains scope/non-goals, prerequisites, first-use demo, empty/loading/error/limited-permission states, iPhone layout, iPad layout, keyboard/pointer/VoiceOver behavior, persistence/schema proposal, state machine, concrete Swift protocol shape, algorithm, safety rules, memory/power/thermal behavior, security threat analysis, local instrumentation, Gherkin acceptance criteria, unit/integration/UI/device tests, synthetic fixture recipes, performance budgets, suggested repo paths, migration/rollback, feature flags, engineering estimate and Definition of Done.

## First-use journey, local metrics and iPhone/iPad divergence

The first 30 seconds should be permission-light. Apple explicitly recommends requesting Photos access in context rather than blindly at launch, and limited access should be treated as a supported privacy choice. citeturn527385search3 CleanSlate should therefore open with a synthetic interactive demonstration before broad access is requested.

The flow is:

```text
Launch
  ↓
“No account. No photo upload.”
  ↓
15–20 second bundled cleanup demo
  ↓
Choose intent:
“Find easy space” | “Review similar moments” | “Organize”
  ↓
Contextual Photos permission
  ↓
Progressive accessible/local result
  ↓
One confident Keep / Protect / Review decision
```

From 30 seconds to three minutes, show no more than three locally generated next actions: the safest opportunity, the highest potential-byte opportunity already indexed, and a positive/non-destructive action such as Rescue Gems or Album Inbox. In the first ten minutes, pause periodically with neutral status such as: “18 reviewed · 7 kept safe · 312 MB potentially removable · nothing deleted yet.” The user gets equally prominent **Review tray**, **Keep going**, and **Stop for now** actions.

Day two should not greet the user with guilt. A useful home state is “8 screenshots ready,” “3 new similar groups,” or “Nothing urgent.” By week one, an optional locally generated recap can show reviewed items, kept-safe count, exact copies removed, verified deleted logical bytes and rediscovered/favorited memories. No streak loss is needed. Swipewipe and Flic demonstrate that monthly/daily structure can create engagement, but CleanSlate can retain the useful cadence without the coercive parts. citeturn606790search3turn374345view1

Local instrumentation stores events only on-device. It must never contain asset IDs, filenames, OCR text, image embeddings, face identity, GPS coordinates or media pixels. A `Delete CleanSlate Local Data` control clears events, caches, preferences and diagnostics. Recommended core formulas are:

`timeToFirstValue = firstMeaningfulResultTimestamp - featureOpenTimestamp`

`reviewThroughput = reviewedAssets / activeReviewMinutes`

`potentialDeletableLogicalBytes = sum(eligible candidate resource sizes under declared coverage)`

`verifiedDeletedLogicalBytes = sum(resource sizes of deletion operations successfully reconciled with Photos)`

`deviceFreeSpaceDelta = OS-reported post-capacity - pre-capacity`, displayed only as a noisy diagnostic.

**iCloud storage reclaimed must not be derived by CleanSlate.** Apple controls iCloud Photos synchronization, Recently Deleted and quota behavior; CleanSlate cannot attribute account quota changes precisely enough to make that claim. citeturn527385search0

The iPhone and iPad versions share the engine but should not share screen composition blindly. The repo’s current iPad plan already calls for compact phone navigation versus wide sidebar/list/detail layouts, resizable windows, keyboard/pointer parity and a single mutation owner. citeturn154595view0 The specs extend that pattern: iPhone is thumb-first, portrait-first and one-decision-at-a-time; iPad is three-pane where space permits, supports Stage Manager-style resizing, keyboard actions, pointer affordances and persistent comparison context. Multiple iPad windows may observe state, but one actor owns a mutation transaction.

The cross-platform architecture document is here:

[Architecture and parity matrix](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/ARCHITECTURE.md)

[Integrated onboarding and local metrics spec](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/ONBOARDING.md)

[Cross-feature test plan](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/TEST_PLAN.md)

## Roadmap, sustainability and coding-agent handoff

A realistic six-to-twelve-month sequence starts by finishing the current device stability gate, because the repository explicitly makes that a prerequisite rather than an optional cleanup task. citeturn953505view2turn154595view3 Months one and two establish N05 protections and N04 goal planning. Months two through four add Screenshot Intelligence and Mistake Finder. Months four and five calibrate Moment Intelligence. Months five through eight tackle similar videos and only then transactional compression. Months eight through ten add Album Inbox and Rescue Gems. Local personalization comes last, because it benefits from the trustworthy user-decision history created by everything before it.

The zero-paid-infrastructure goal remains realistic. Vision runs on-device; Core ML is designed for on-device execution; AVFoundation and PhotoKit provide the media infrastructure. citeturn812237search13turn794440search6turn812237search36 Future optional Core ML packs could use Apple-hosted Background Assets rather than a developer CDN; Apple documents managed background assets and Apple-hosted asset packs, including ML-model distribution. citeturn258867search0turn258867search2 That should remain optional because the top ten do not require downloaded third-party models.

Apple Foundation Models should likewise **not** become a core dependency. The current generation of Foundation Models has device/OS eligibility constraints, and newer image/PCC capabilities introduce additional availability assumptions. citeturn258867search7turn258867search9 If eventually used, the appropriate role is adjudicating or explaining a tiny ambiguous candidate set—not scanning the photo library and never authorizing deletion.

Background work must be framed honestly. Apple’s continued-processing APIs are intended for explicit user-initiated tasks and remain subject to system scheduling and termination. citeturn258867search3turn258867search12 CleanSlate can checkpoint and resume; it should never promise that iOS will definitely finish a 250k-library analysis invisibly overnight.

Distribution can also remain highly automated without becoming autonomous in the dangerous sense. Apple’s App Store Connect API supports automation around TestFlight, metadata and submission workflows, and Apple supports uploading builds through Xcode/Transporter/API tooling. citeturn258867search5turn258867search6 Production release should remain a human gate because those APIs can affect real distribution and because this app handles destructive photo-library operations.

The coding-agent handoff contract deliberately forces the agent to work one feature at a time:

```text
1. pull main and record exact HEAD SHA
2. read AGENTS / PRODUCT / PROGRESS / VALIDATION_LOG / IMPLEMENTATION_ORDER
3. confirm current gate prerequisites
4. write failing Core safety tests
5. add DB migration + migration tests
6. implement deterministic engine
7. add synthetic fixtures
8. implement iPhone UI
9. implement separate iPad adaptive UI
10. connect local-only metrics
11. integrate existing tray/deletion coordinator only if required
12. run repo CI/budget/policy validators
13. run physical-device gate
14. update VALIDATION_LOG
15. enable feature only when evidence exists
```

The agent is explicitly prohibited from inventing passing test results, introducing a second deletion path, adding photo telemetry, auto-downloading iCloud originals, relaxing near-duplicate protections, or marking a feature complete based only on simulator results.

[6–12 month roadmap](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/ROADMAP.md)

[Decision register](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/next-features/DECISIONS.md)

[Source registry with direct URLs and retrieval date](sandbox:/mnt/data/CleanSlate_Premium_Parity_Research_2026-11-12/docs/research/SOURCES.md)

The highest-value product thesis after this research is simple: **premium cleaners are charging users mostly for good prioritization and interaction design, not compute that requires a subscription backend.** CleanSlate can reproduce most of that value locally while doing something the paid market does inconsistently: making uncertainty, coverage, preservation, storage accounting and deletion boundaries explicit. Flic already demonstrates that sophisticated local ranking and storage-goal planning can be implemented without photo uploads; Slidebox demonstrates the value of excellent local organization; CleanMyPhone and Cleansmith demonstrate how much breadth is possible with on-device media analysis. citeturn374345view1turn374345view2turn374345view0turn374345view3 The differentiator for CleanSlate should therefore be **premium-level usefulness, zero paywall, and materially stronger trust semantics—not simply “another cleaner, but free.”**
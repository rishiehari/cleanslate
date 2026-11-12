# Competitor evidence registry — scope and confidence

**Research date:** November 12, 2026. These sources are public App Store/vendor descriptions from the prior deep-research exercise; they establish what an app **advertises**, not independent implementation details or verified algorithm accuracy. Availability, plan tiers and paywall placement change by country/time and must be rechecked immediately before publishing marketing comparisons. No claim here should be read as an endorsement.

| Product / source | User-visible marketed capability relevant to this spec | CleanSlate counterpart | Evidence category |
|---|---|---|---|
| [Flic: AI Photo & Video Cleaner](https://apps.apple.com/us/app/flic-ai-photo-video-cleaner/id918263212) | On-device assistance, likely junk, best shots, storage-goal plans, local preference learning, daily rediscovery, unlimited usage premium | N04/N01/N09/N10 | App Store advertiser description; specific premium gate is stated in listing |
| [CleanMyPhone](https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040) | Similar/duplicate cleanup, compression, Live conversion, blurry/large media, Sensitive exclusion, iPhone/iPad, local image processing claim | N05/N06/N03 | App Store advertiser description |
| [Cleanup: Phone Storage Cleaner](https://apps.apple.com/us/app/cleanup-phone-storage-cleaner/id1510944943) | Duplicate photos/videos, similar screenshots, lookalike videos, best-photo marking, compression, broad utility bundle | N07/N02/N01/N03 | App Store advertiser description |
| [Cleaner Kit](https://apps.apple.com/us/app/cleaner-kit-clean-up-storage/id1194582243) | Duplicate/blurry detection and storage cleanup, Live Photo conversion | N06/N03 | App Store advertiser description |
| [Swipewipe](https://apps.apple.com/us/app/swipewipe-photo-cleaner/id1583884012) | Month-by-month swipe cleanup, On This Day, streaks, screenshots and blurry grouping | S01/N09/onboarding | App Store advertiser description; we intentionally reject coercive streaks |
| [Slidebox](https://apps.apple.com/us/app/slidebox-photo-cleaner-app/id984305203) | Album sorting, swipes, favorites, undo, progress, iPhone/iPad | N08 | App Store advertiser description |
| [Clever Cleaner](https://apps.apple.com/us/app/clever-cleaner-ai-cleanup-app/id1666645584) | Best Shot, similar groups, skip/protect lists, compression and swipe | N05/N01 | App Store advertiser description; price/free claims can vary by storefront |
| [Cleansmith](https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192) | Similar video search, low-resolution/closed-eye classes, compression, Live Photo and spatial media | N02/N06/N03 | App Store advertiser description; CleanSlate does not claim eye-state accuracy |
| [Apple Photos Duplicates support](https://support.apple.com/en-us/104967) | Apple's own Photos deletion and duplicate workflow; Recently Deleted/iCloud implications | All | First-party Apple support; third-party PhotoKit does not expose a generic native duplicate-merge call |
| [Apple PhotoKit limited access](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app) | Restricted album operations under limited library authorization | N05/N08 | First-party Apple API guidance |
| [Apple Vision text](https://developer.apple.com/documentation/vision/recognizing-text-in-images) | On-device OCR interface | N07 | First-party developer docs |
| [Apple Vision image feature prints](https://developer.apple.com/documentation/Vision/GenerateImageFeaturePrintRequest) | Visual descriptor comparison interface | N01/N02 | First-party developer docs |
| [Apple Vision image aesthetics](https://developer.apple.com/documentation/Vision/CalculateImageAestheticsScoresRequest) | Technical aesthetic scoring | N01/N06/N09 | First-party developer docs; not subjective memory worth |
| [Apple AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator) | Extract selected frames from video assets | N02 | First-party developer docs |
| [Apple AVAssetExportSession](https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession) | Supported local media export | N03 | First-party developer docs |
| [Apple PhotoKit change requests](https://developer.apple.com/documentation/photokit/requesting-changes-to-the-photo-library) | Public API for user-authorized mutations | N03/N08/N09 | First-party developer docs |

## Claims we are NOT making

- No unverified current US subscription price/plan is treated as timeless; research showed some price points but exact screens vary.
- No reverse-engineered competitor algorithm, accuracy rate, actual retention number or independent privacy audit is asserted.
- 'On-device' in a competitor listing is a marketing claim unless confirmed by independent technical evidence.
- No inference that competitor subscription compute requires servers; many relevant functions can run on-device and be charged for as a business model.
- No implication that CleanSlate provides Apple's first-party duplicate *merge*, restores permanently deleted items, or controls iCloud quota storage.

## Research conclusions translated into requirements

1. Paid market monetizes throughput, guided prioritization and convenience. **N04** supplies a free transparent planner without speculative recovery claims.
2. Paid market uses "Best" labels. **N01** uses multi-keeper review and abstention so it doesn't destroy distinct memories.
3. Screenshot and video intelligence deliver high perceived savings. **N07/N02** require actual changed-content guards and bounded device work.
4. Compression is enticing but risky. **N03** stores a verified *copy* before any separate original-deletion review.
5. Swipe interaction can be habit forming. Existing S01 plus first-session contract deliver fluency without streak pressure, countdowns or paywalls.
6. Positive rediscovery and sorting matter even with zero duplicates. **N08/N09** ensure cleaning isn't the only way to succeed.
7. Personalization can be private. **N10** starts off and is constrained to ranking, never safety policy.

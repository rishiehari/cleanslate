# Device log analysis: first real-phone hang (2026-11-09)

Source: owner's Xcode console capture from an iPhone 17 Pro, iCloud Photos with **Optimize iPhone Storage ON**.
Owner report: tapped Scan, progress reached ~60% at "7,500ish" photos, then the app hung and was force-quit.
The log is console output only (15,087 lines): no crash, no jetsam, no watchdog. **It is a hang, not a crash.**

## What the log shows (facts)
| Lines | Message | Count | Meaning |
|---|---|---|---|
| 5 - 7,941 | `Missing prefetched properties for PHAssetOriginalMetadataProperties ... Fetching on demand on the main queue, which may degrade performance.` | 7,938 (7,340 photos, 598 videos) | The inventory walked the **whole library, newest (2026-11) to oldest (2011-07)** and for **every asset** forced a synchronous on-demand metadata fetch **on the main queue**. |
| 7,942 - 15,087 | `[RM]: 3-N-0 Image request failed ... PHPhotosErrorDomain Code=3303 "No resource found matching image request spec"` | **7,146** (request counter ran 23 to 7,168) | The thumbnail stage asked PhotoKit for a small image and **99.7% of requests failed**. |
| last line | one more `Missing prefetched ...` for an asset dated 2024-08-06 | 1 | A later stage started reading per-asset metadata on the main queue, and **the log never advances again**. |

The two phases are strictly sequential (no interleaving), so the library is ~7,938 items and the app got through the
inventory and nearly all of the thumbnail pass, then went silent inside the next stage.

## Findings
1. **Main-thread work (confirmed from code + log).** `PhotoKitLibraryClient` and `ScanEngine` are `@MainActor`.
   `inventoryPage` -> `snapshot(_:)` (PhotoKitLibraryClient.swift:158-200) reads `PHAssetResource.assetResources(for:)`,
   `originalFilename`, `burstIdentifier` etc. per asset, synchronously, on the main thread. PhotoKit says so itself in
   7,938 log lines. With iCloud-optimized originals each of these can require a round trip to `photolibraryd`; on the
   main thread that is a frozen UI and a stalled progress bar.
2. **Thumbnails do not exist locally for optimized assets (confirmed).** `thumbnail()` (PhotoKitLibraryClient.swift:205-222)
   uses `isNetworkAccessAllowed = false`, `.fastFormat`, `.fast`, and treats nil as "skip". Error 3303 = the requested spec
   cannot be satisfied from local data. For ~99.7% of this library the whole visual stage produced nothing. The scan did
   enormous work (and held the user at "scanning") while yielding **no visual features**, so the result would also have been
   nearly empty. Note `fastFormat` + a target of 280-512 px may be asking for a size/format PhotoKit has not cached; the
   fix must be verified on a device (see below), not assumed.
3. **The final stall (strongly supported, not proven).** The last event is a main-queue metadata fetch in a later stage
   (exact-candidate / re-snapshot / digest work, e.g. `snapshot(id:)` at PhotoKitLibraryClient.swift:39 or
   `completeDigests` at :226). With optimized storage, reading original resources is the slow path (network disabled, so
   it should fail fast, but resource enumeration itself blocks). There is **no per-stage timeout, no heartbeat and no
   log**, so a stall looks identical to a hang. This matches HANG_RCA.md hypothesis H1 (a slow later stage), now with
   device evidence that the earlier stages finish.
4. **The progress bar cannot be trusted.** 7,168 thumbnail attempts for a 7,938 library is ~90% of that stage, but the UI
   showed ~60% because stages are weighted into one bar, and it stopped moving without any message.

## Consequences for the plan (changes to F-specs)
- **F03 (stability):** move all PhotoKit reads off the main actor (a dedicated serial actor/queue); make inventory
  **light** (fetch identifiers + only the cheap properties already prefetched; defer `PHAssetResource` enumeration and
  `originalFilename` to the moment a candidate is actually examined); add per-stage timeouts and a stall watchdog.
- **F04 (scope):** with 7,938 items, Recent 100 would have touched 1.3% of the library. Inventory must be
  **scope-bounded** (fetch limit + `fetchLimit`), never "walk 7,938 then decide".
- **New requirement (add to F03/F08): optimized-storage handling.** Detect that a large share of thumbnail requests fail
  with 3303 (a rolling failure ratio); stop spending time on the visual stage, tell the user plainly ("Many of your photos
  are stored in iCloud; checking them needs a download"), and offer the F08 opt-in download ladder instead of failing
  silently. Treat 3303 as "not available locally", not as an error to retry.
- **New requirement (F02):** log, per stage, start/end, counts, the 3303 ratio, main-thread blocked durations, and a
  heartbeat every 2 s, so the next device run produces a decisive log without Xcode attached.
- **Device test needed (owner gate, F03):** repeat the scan on this library with the F02 log; additionally try
  `.opportunistic` delivery, `.aspectFill` with a 256 px target and `PHImageRequestOptions.version = .current` on a handful
  of optimized assets to see which spec returns a local derivative. Do not assume.

## Not established by this log
Exact cause of the final silence (needs F02 heartbeat or an Instruments Hangs/Time Profiler capture); memory use
(no memory data in a console log; MetricKit/Allocations needed); whether the user's 17 Pro was thermally throttled.

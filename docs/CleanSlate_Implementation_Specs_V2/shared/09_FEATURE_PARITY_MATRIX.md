# iPhone / iPad feature parity and shared-component ownership

| Feature | Shared engine / data | iPhone implementation | iPad implementation | Device-specific tests |
|---|---|---|---|---|
| N05 Protection | rule store, verdict gate, immutable safety policy | asset Protect sheet, rule list, shield chips | rules sidebar/list/inspector, keyboard search | album permissions; rule edit during pending deletion; iPad resize |
| N04 Storage Goal | planner, candidate overlap, potential-byte ledger | one-card review deck and goal chips | three-pane goal/candidate/compare workspace | goal preservation after rotate; byte VoiceOver |
| N07 Screenshot | screenshot candidate index, OCR guard, changed-text evidence | stacked screenshot compare, diff toggle | group grid + side-by-side zoomed diff | text changes; QR; OCR fallback; iPad synchronized pan |
| N06 Mistake | quality evidence, Issue enum, manual review | quality category cards, photo-first reason chips | issue sidebar, large image + signal inspector | artistic blur, low light; large image budget |
| N01 Moment | evidence graph, multi-keeper draft, parent review | swipe pair + keeper filmstrip + parent summary | filmstrip, dual compare, keeper inspector | transitive graph; 40-frame burst; keyboard actions |
| N02 Video | frame sampler, local alignment, resource checks | stacked dual players, duration/audio warning | simultaneous comparison timeline/inspector | HDR/audio/trim; thermal; focus |
| N03 Compression | capability validator, journal, export, create/reconcile | preset sheet, trial progress and before/after | job queue + side-by-side video + metadata | 4K/codec/low disk; crash after Photos save |
| N08 Album | album destination adapter, mutation reconciliation, local labels | album chips and single-item inbox | sidebar-album drag/drop grid inspector | limited access; idempotent Photos membership |
| N09 Gems | diversity ranker, batch history, Favorite mutation | full-screen gem carousel | mosaic + detail + time filter | diversity/time samples; Favorite invalidates tray |
| N10 Local Taste | opt-in samples, bounded ranker and held-out gate | settings, simple synthetic demo, ordering chip | standard-vs-personalized inspector | reset/opt-out, model corruption, focus and keyboard |

### Shared ownership rules

- `Core/`: pure algorithms, typed invariants, non-Photos rule/evidence models. No SwiftUI/Photos/AVFoundation dependency if possible.
- `App/Store/LibraryStore.swift`: single DB connection owner, migrations, cursor and feature caches. No new competing writer actor.
- `App/Services/PhotoLibraryClient.swift`: PhotoKit data access boundary; new features use capability-specific adapters over this boundary.
- `App/Services/ResourceGovernor.swift`: heavy-work scheduling. Screen size alone never multiplies worker concurrency.
- `App/Store/DeletionTray.swift` and `App/Services/PhotoDeletionCoordinator.swift`: **sole destructive path**. New screens can approve candidates, not bypass deletion guards.
- `App/Views/` and new `App/Views/iPad/` folders: separate compositions, shared tiles/chips/number formatters and view models where appropriate.
- `iOSTests/`, `UITests/`: code-level and user-flow tests on both device families. UI screenshots without real user photos.

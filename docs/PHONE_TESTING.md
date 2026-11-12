# Run this session's build on your iPhone

The app target requires iOS 26 or newer. Simulator tests do not establish real PhotoKit behavior. Use a disposable test library for deletion tests; you can inspect the overview and start/pause scans without approving or deleting anything.

1. From this repository, run `make gen` (requires XcodeGen). The generated `CleanSlate.xcodeproj` already exists locally; it is intentionally not committed.
2. Open `CleanSlate.xcodeproj` in Xcode. Select the **CleanSlate** scheme and your connected iPhone.
3. Under target **Signing & Capabilities**, select your own development team and keep automatic signing enabled. This session's generic device build disables signing to verify compilation; it does not install an unsigned app on your phone.
4. In **Edit Scheme → Run → Arguments**, remove synthetic-test flags if present (`-uiTestingFakeLibrary`, `-uiTestingSwipe`, `-prototype`). Leave the production library path active for a device run. Do not grant broad access before you are ready; limited access is supported.
5. Run. Finish the short intro, then allow Photos access in context. The activity overview should load without image analysis. Choose a suggested week or use the default **Past month · up to 2,000 items** scan. Change scan range offers past two months and bounded count options; no whole-library action is offered.
6. Verify the interface remains responsive; Pause should return promptly. Review available exact groups, similar groups or standalone categories while the shared progress banner remains visible. Selecting/approving adds only to the tray; deletion still requires the separate confirmation and Apple's prompt.

If something stalls, use Settings → Diagnostics to export the local scan log yourself and note device/OS, selected range, phase, item count and elapsed time. The app cannot forcibly interrupt a synchronous PhotoKit call already executing on its background reader; the UI deadline should return safely instead of waiting indefinitely. Device validation is still pending.

Fixed since the previous phone build (2026-11-12, found with an owner-provided photo copy in a simulator): a crash a few seconds into every scan (Swift 6 isolation trap in PhotoKit callbacks), a would-be crash at the final Delete step (same cause), thumbnails failing for photos without a cached preview (scan found nothing), and a crash when starting the Latest 2,000 scan (background task submit). Please re-test those flows first: start a scan, let it finish, open Similar & bursts, approve one item and delete it from the tray. Swipe n Save may show "No pairs ready" on a real library (known; owner decision pending).

Known validation limits (historical, see VALIDATION_LOG for current): the full integrated iOS suite was not green in its first run; subsequent focused tests fixed functional failures. Remaining automated Home contrast sampling around occluded/floating-tab content and the complete AX5/manual VoiceOver/window matrix are recorded in VALIDATION_LOG.md. No claim of release readiness.

Next-feature implementation is queued in plans/PREMIUM_PARITY_IMPLEMENTATION_ORDER.md; N05 protections has a specification only. Do not confuse the downloaded research report with implemented product features.

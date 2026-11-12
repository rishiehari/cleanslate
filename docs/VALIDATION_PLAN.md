# Bounded first-scan validation

Use only synthetic libraries for automated testing.

- Core: activity ranking, weekly boundaries, sample cap, undated items.
- iOS: time/count bounds, narrower scans after wider cached inventory, cancellation, no analysis/deletion from overview, explicit week selection, retained protection/revalidation/tray assertions.
- UI on phone and tablet: overview without scan, bounded range picker, active progress/Pause, review and tray flows, resize/rotation draft retention.
- Regression: Core, fixtures, synthetic eval, lint, app build, full iOS tests, memory budgets. Record skips, simulator hangs and unavailable Vision honestly.
- Owner device: disposable library, large-library metadata latency and cancellation, Photos authorization/limited access, unavailable originals, background/foreground, actual Apple prompt, iPhone/iPad resizing and Instruments. Until measured, device hang resolution and release remain unverified.

# Ten independent implementation specifications

Read shared contracts and audit file first. Numeric IDs reflect the original research selection; the list below reflects recommended engineering order. Feature pages are self-contained with an implementation interface, data schema, state machine, iPhone UX, iPad UX, tests and rollback.

1. [N05 — Protection rules](N05-protection-rules.md): protect user-selected assets, album/date ranges and invalidate pending delete approvals.
2. [N04 — Storage Goal Planner](N04-storage-goal-planner.md): build evidence-based, no-double-counting review plans for goals.
3. [N07 — Screenshot Intelligence](N07-screenshot-intelligence.md): private OCR guard against changed text/QR content.
4. [N06 — Mistake Finder](N06-mistake-finder.md): explain technical image quality without auto-deleting meaningful memories.
5. [N01 — Moment Intelligence](N01-moment-intelligence.md): constrained multi-keeper display and direct evidence graph.
6. [N02 — Similar Video](N02-similar-video-finder.md): bounded local frame sequences and temporal comparison.
7. [N03 — Compression Lab](N03-compression-lab.md): journaled export, independent validation, save copy and only later review source.
8. [N08 — Album Inbox](N08-album-inbox.md): Photos album work under full access and honest local-label fallback under limited access.
9. [N09 — Rescue Gems](N09-rescue-gems.md): local positive rediscovery and Favorite.
10. [N10 — Local Taste](N10-local-taste.md): opt-in, resettable, holdout-validated ordering only.

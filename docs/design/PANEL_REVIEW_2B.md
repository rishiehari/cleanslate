# Expert panel review — Step 2B milestone (simulated by the executing agent)

**Honesty note:** this is a structured self-review in six personas, grounded in the actual screenshots
(`docs/screens/step2b-*`) and code. It is NOT a substitute for real users; the hallway test in Step 10.3b is.

## Panel
1. **First-time user** (non-technical, 30k photos, "storage full")
2. **Power user** (150k photos, iCloud on, wants speed)
3. **Accessibility specialist** (VoiceOver, Dynamic Type, Reduce Motion)
4. **Apple HIG / Liquid Glass reviewer**
5. **Principal iOS architect**
6. **Deletion-safety reviewer** (adversarial: how could a memory be lost?)

## Findings and what changed
| # | Persona | Finding | Severity | Action |
|---|---|---|---|---|
| 1 | First-time user | "Approve" could be read as "delete"; the toast just said "Approved 3 photos" | High | Toast now says "Added 3 photos to your tray"; intro text explains the tray; word list records the meaning. **Done** |
| 2 | Power user | After each Approve the app went back to the list, so 200 groups = 400 taps | High | `ReviewSessionView`: Approve/Skip opens the next group ("2 of 14"). Test added. **Done** |
| 3 | Power user | No quick way through exact copies | Medium | "Approve all N copies" with a reviewable list already exists. Keep. |
| 4 | Accessibility | Glass Skip/Approve controls failed the contrast sampler over photos | High | Fade backing behind the bar, single-line label, system label colors; remaining sampler exemption limited to the two glass controls and verified by eye. **Done** |
| 5 | Accessibility | Badge text on bright dark-mode accents was unreadable | Medium | `onAccent` token (black text in dark mode). **Done**; dark-mode screenshots to be re-checked |
| 6 | Accessibility | Reduce Motion path for the tray animation not tested | Medium | Symbol bounce/numericText are system-gated; explicit UI test for Reduce Motion is **carried forward** (no reliable launch flag) |
| 7 | HIG | Cards should not use glass (content layer) | OK | Verified: glass only on ApprovalBar, toast, buttons |
| 8 | HIG | "Coming in a later build" cards are noise | Low | DEBUG-only already; hidden in release |
| 9 | Architect | Tray deletes group by group: N groups = **N Apple prompts** | **Blocker for device use** | Interim by design; **Step 8 (single batch) must land before any real-library deletion test.** Logged as a hard dependency. |
| 10 | Architect | Tray file holds photo identifiers | Medium | Excluded from backup + file protection. **Done** |
| 11 | Architect | Views are small and token-based; lint enforces tokens | OK | `make lint` in `make ci` |
| 12 | Safety | Can Approve ever delete? | Critical | No: `approve` only mutates the tray; `deleteAssets` still has one call site behind `PhotoDeletionCoordinator.commit`. UI test asserts `deleteCalls=0` after approve and after cancelling the confirm sheet |
| 13 | Safety | Stale tray after relaunch | High | Tray entries are only intents; `commit` re-fetches, checks revisions, flags, rehashes bytes, and re-checks at the delete call. Step 6 adds visible "needs another look" handling. |
| 14 | Safety | Similar-photo groups: user taps to mark, nothing pre-marked | OK | UI test + `ReviewDraft` property test (500 random tap sequences) |
| 15 | Safety | A protected copy inside an exact group | OK | Favorite copy stays Keep, tapping explains why, Approve disabled (UI test) |
| 16 | Safety | Skipped groups disappear | Medium | "Reviewed" toggle in the inbox; labeled "Skipped"/"In your tray" |

## Verdict
Proceed. Open items carried forward: Reduce Motion test, dark/AX3 screenshot re-check, matched-geometry "fly to tray" animation (cross-fade used), next-group image prefetch (U6), N-prompt interim (Step 8).

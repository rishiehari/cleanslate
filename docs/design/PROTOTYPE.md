# Review screen prototypes (Step 2B.4)

Five divergent, runnable SwiftUI prototypes on the shared design system and the same sample data.
Launch any of them in a DEBUG build with `-prototype 1…5` (`App/Debug/ReviewVariants.swift`).
Screenshots: `docs/screens/prototypes/` (contact sheet: `contact-sheet.png`).

| # | Name | Organizing idea | Strengths | Risks |
|---|---|---|---|---|
| 1 | Card Stack | One deck card per group, swipe up to approve | Fun, fast, one-handed | Swipe-to-approve is easy to trigger by accident; hides the other photos behind the card; poor for 12-photo bursts |
| 2 | Hero + Strip | Big Keep photo, filmstrip of other shots | Clear "this is what stays"; scales to bursts; good for compare | Strip hides how many shots there are; horizontal scrolling can miss one |
| 3 | Grid Triage | Whole group in a grid, tap to mark | Familiar (Photos app); everything visible at once | Photos get small; keeper not visually special |
| 4 | Side by Side | Keeper vs one other shot | Best for choosing between two near-identical shots | Slow for groups with many copies; needs a picker |
| 5 | Inbox List | Rows of groups with an Approve button each | Fastest for exact copies; best for bulk (Approve all) | Row thumbnails are too small to judge similar shots |

## Decision (default adopted by the agent; owner can overrule at the gate)
Remix, following the recommendation in the plan:
- **Exact copies → Inbox List (5)** + "Approve all" with a list to include/exclude groups. Built as `CategoryGroupsView` + `ApproveAllSheet`.
- **Similar & bursts → Hero + Strip (2) with a Grid fallback and Compare (4)** for the close calls. Built as `ReviewGroupView` (big Keep photo; other shots in a one- or two-column grid for readability instead of a horizontal strip) and `CompareView` (synchronized zoom, "Next photo").
- **Rejected:** Card Stack (accidental swipe approval conflicts with rule U1 spirit; not accessible without alternatives).

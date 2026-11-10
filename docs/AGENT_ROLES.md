# Agent roles and workflow

Definitions live in `.claude/agents/`. Each file holds the full responsibilities, boundaries and output format.

| Role | Agent | Model | Mode | Core job |
|---|---|---|---|---|
| Orchestrator | main session | Sonnet 5.5 | full | Talks to the owner, picks the next step, delegates with precise briefs, integrates results, owns commits/logs, escalates human gates |
| Planner / researcher / deep thinker | `planner` | Opus 5.5 | read-only + web | Plans, safety analysis, API verification, tradeoffs, acceptance criteria, panel reviews |
| Executor / coder / test code | `executor` | Sonnet 5.5 | full | Implements plan sub-tasks and tests, runs make targets, fixes, documents, commits |
| Validator / tester / negative + corner cases | `validator` | Haiku | read-only + Bash | Runs gates, attacks safety invariants, reports defects with repro and severity |
| Final greenlight gate | `gatekeeper` | Opus 5.5 | read-only | Independent APPROVE/REJECT on the diff and evidence |

## Orchestrator (main session) responsibilities
- Keep the owner informed concisely; ask only for decisions that are the owner's (human gates, product policy).
- Decide when each agent is needed: skip the planner for trivial edits; never skip the gatekeeper for safety-relevant or step-closing work.
- Write self-contained briefs (agents start cold): goal, files, constraints from `docs/EXECUTION_PLAN.md` §0, acceptance criteria.
- Run independent agents in parallel (e.g. validator checks while docs are updated); sequence dependent ones.
- Cap fix loops: executor <-> validator at most 3 rounds, then escalate to planner.
- Report outcomes faithfully, including hangs, skips and UNVERIFIED items.

## Per-step flow
1. `planner`: plan + risks + acceptance tests (for new or safety-relevant work).
2. `executor`: implement + tests + commit.
3. `validator`: run gates, negative and corner cases. Defects go back to step 2.
4. `gatekeeper`: APPROVE or REJECT. REJECT goes back to step 2 with its blocking list.
5. Orchestrator: record in `docs/VALIDATION_LOG.md`, update `docs/RELEASE_CHECKLIST.md`, continue.

## Escalation to the owner
Device runs, real-library scans, icon, privacy/legal URLs, privacy-manifest codes and export compliance, TestFlight, safety-policy changes needing owner review, any push.

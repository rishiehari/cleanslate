# Agent roles and workflow

Definitions live in `.claude/agents/`. Each file holds the full responsibilities, boundaries and output format.

| Role | Agent | Model | Mode | Core job |
|---|---|---|---|---|
| Orchestrator | main session | Sonnet 5.5 | full | Talks to the owner, picks the next step, delegates with precise briefs, integrates results, owns commits/logs, escalates human gates |
| Planner / researcher / deep thinker | `planner` | Opus 5.5 | read-only + web | Plans, safety analysis, API verification, tradeoffs, acceptance criteria, panel reviews |
| Executor / coder / test code | `executor` | Sonnet 5.5 | full | Implements plan sub-tasks and tests, runs make targets, fixes, documents, commits |
| Validator / tester / negative + corner cases | `validator` | Haiku | read-only + Bash | Runs gates, attacks safety invariants, reports defects with repro and severity |
| Final greenlight gate | `gatekeeper` | Opus 5.5 | read-only | Independent APPROVE/REJECT on the diff and evidence |

## Kimi Code mirror

The same workflow is defined for Kimi Code CLI in `.kimi-code/agents/`, with per-role model bindings declared in `[secondary_model]` in `~/.kimi-code/config.toml`. Launch with `kimi --agent orchestrator` to run the orchestrator as the main agent (default model is already K2.8 Preview).

| Role | Agent | Model |
|---|---|---|
| Orchestrator (main) | `orchestrator` | K2.8 Preview (`kimi-code/kimi-for-coding`) |
| Reasoning / research / thinking | `reasoner` | K3.1 Pro (`kimi-code/k3.1-pro`) |
| Coding | `implementer` | K2.8 Preview |
| Evaluation / validation gate | `evaluator` | K2.8 Preview |
| Corner cases / negative scenarios | `edge-tester` | K2.8 Preview |

## Orchestrator (main session) responsibilities
- Keep the owner informed concisely; ask only for decisions that are the owner's (human gates, product policy).
- Decide when each agent is needed: skip the planner for trivial edits; never skip the gatekeeper for safety-relevant or step-closing work.
- Write self-contained briefs (agents start cold): goal, files, constraints from `docs/EXECUTION_PLAN.md` §0, acceptance criteria.
- Run independent agents in parallel (e.g. validator checks while docs are updated); sequence dependent ones.
- Cap fix loops: executor <-> validator at most 3 rounds, then escalate to planner.
- Report outcomes faithfully, including hangs, skips and UNVERIFIED items.

## Codex role mapping (owner-requested, 2026-11-11)

| Role | Codex model | Reasoning |
|---|---|---|
| Orchestrator | `gpt-6.1-sol` (requested main-session configuration) | high |
| Planner | `gpt-6-astra` | high |
| Executor | `gpt-6.1-sol` | high |
| Validator | `gpt-6-luna` | high |
| Gatekeeper | `gpt-6-astra` | high |

Use this mapping when the runtime supports model selection; report any limitation rather than claiming the main
session switched models. Role responsibilities and safety gates are the same across Codex, Kimi and Claude.

## Shared handoff between agents and tools

- Start with `docs/PROGRESS.md`, current `git status` / recent commits, and the tail of `docs/VALIDATION_LOG.md`.
  A previous tool's chat or sub-agent ID is not a resumable project state.
- Update `PROGRESS.md` whenever a feature, fix round, gate, interruption, or blocker changes. Include current scope,
  completed commit hashes, actual test evidence, pending reviews/device gates, and the next concrete action.
- Append measured results to `VALIDATION_LOG.md`; keep `RELEASE_CHECKLIST.md`, feature specifications, plans and
  architecture consistent. Preserve earlier dated evidence as history and clearly identify superseded claims.
- Keep durable requirements and implementation state in repository documents. Tool-specific agent prompts point
  here; they must not become competing progress logs. No personal photos, credentials or private evaluation data.
- Inspect dirty files before writing or staging. Preserve another agent's work, and distinguish uncommitted work,
  implemented behavior, planning-only features and verified completion. Never infer a human gate passed from silence.

## Per-step flow
1. `planner`: plan + risks + acceptance tests (for new or safety-relevant work).
2. `executor`: implement + tests + commit.
3. `validator`: run gates, negative and corner cases. Defects go back to step 2.
4. `gatekeeper`: APPROVE or REJECT. REJECT goes back to step 2 with its blocking list.
5. Orchestrator: record in `docs/VALIDATION_LOG.md`, update `docs/RELEASE_CHECKLIST.md`, continue.

## Escalation to the owner
Device runs, real-library scans, icon, privacy/legal URLs, privacy-manifest codes and export compliance, TestFlight, safety-policy changes needing owner review, any push.

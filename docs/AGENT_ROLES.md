# Agent roles

| Role | Agent | Model | Job |
|---|---|---|---|
| Orchestrator | main session | Sonnet 5.5 | Talks to the user, delegates, integrates |
| Planner / researcher | `planner` | Opus 5.5 | Plans, research, deep analysis (read-only) |
| Executor / coder / test code | `executor` | Sonnet 5.5 | Implements plan steps and tests, commits |
| Validator / negative + corner tests | `validator` | Haiku 5.5 | Runs suites, tries to break invariants (read-only) |
| Final gate | `gatekeeper` | Opus 5.5 | APPROVE/REJECT before a step is called done |

Flow per step: planner -> executor -> validator -> (fix loop) -> gatekeeper.
Definitions live in `.claude/agents/`.

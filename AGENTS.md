# Repository instructions for all agents

Read `docs/AGENT_ROLES.md`, `docs/PROGRESS.md`, and recent `docs/VALIDATION_LOG.md` entries before work. Preserve concurrent agents' edits and staged changes.

## Standing authorization to commit and push

The owner explicitly authorized this policy on 2026-11-11. It supersedes older instructions requiring permission for each push.

- After a coherent task is complete and its applicable tests/checks pass, commit the task and push it to this repository's configured GitHub remote without asking again. Record validation and the pushed commit in the handoff.
- Inspect the diff and staged files first. Commit only your task's changes; coordinate shared files and never sweep another agent's unfinished work into a completed-task commit.
- If another agent's changes block the build, document the exact blocker. Do not claim completion or passing validation. Retry after integration; do not overwrite their work to get a green build.
- Explicitly requested in-progress backups belong on a clearly labeled checkpoint branch, with failures and unverified work identified. They do not satisfy completion or release gates.
- Fetch before pushing. Never force-push, rewrite shared history, upload credentials/private keys/personal photos, or bypass protection rules. Resolve ordinary integration safely; ask the owner only when a real decision is needed.
- Push authorization does not authorize release, deployment, real-library operations, safety-policy changes or passing a human/device gate.

GitHub CLI uses macOS Keychain credentials on this laptop. Never put tokens or private keys in repository files or logs.

# Agent Instructions

This project uses [beadwork](https://github.com/jallum/beadwork) (`bw`) for issue tracking. Run `bw prime` at the start of every session to load workflow context, current state, and repo hygiene warnings.

## Quick Reference

```bash
bw prime              # Load workflow context at session start
bw ready              # Show issues ready to work (no blockers)
bw show <id>          # Full issue details with dependencies
bw start <id>         # Move issue to in_progress (refuses blocked issues)
bw close <id>         # Complete work
bw sync               # Fetch, rebase/replay, push beadwork state
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** — `bw create <title> --type=task --priority=2` for anything that needs follow-up
2. **Run quality gates** (if code changed) — tests, linters, builds
3. **Update issue status** — `bw close <id>` for finished work, leave in-progress items in their current state
4. **PUSH TO REMOTE** — this is MANDATORY:
   ```bash
   git pull --rebase
   bw sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** — clear stashes, prune remote branches
6. **Verify** — all changes committed AND pushed
7. **Hand off** — provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing — that leaves work stranded locally
- NEVER say "ready to push when you are" — YOU must push
- If push fails, resolve and retry until it succeeds

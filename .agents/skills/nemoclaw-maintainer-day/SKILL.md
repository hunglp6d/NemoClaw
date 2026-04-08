---
name: nemoclaw-maintainer-day
description: Runs the daytime maintainer loop for NemoClaw, prioritizing items labeled with the current version target. Picks the highest-value item, executes the right workflow (merge gate, salvage, security sweep, test gaps, hotspot cooling, or sequencing), and reports progress. Use during the workday to land PRs and close issues. Designed for /loop (e.g. /loop 10m /nemoclaw-maintainer-day). Trigger keywords - maintainer day, work on PRs, land PRs, make progress, what's next, keep going, maintainer loop.
user_invocable: true
---

# NemoClaw Maintainer Day

Execute one pass of the maintainer loop, prioritizing version-targeted work.

**Autonomy:** push small fixes and approve when gates pass. Never merge. Stop and ask for merge decisions, architecture decisions, and unclear contributor intent.

## References

- PR review priorities: [PR-REVIEW-PRIORITIES.md](PR-REVIEW-PRIORITIES.md)
- Risky code areas: [RISKY-AREAS.md](RISKY-AREAS.md)
- State schema: [STATE-SCHEMA.md](STATE-SCHEMA.md)

## Step 1: Determine Target Version

```bash
git fetch origin --tags --prune
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
```

The target is one patch above the latest tag.

## Step 2: Check Version Progress

```bash
gh pr list --repo NVIDIA/NemoClaw --label "<version>" --state open --json number,title,url,statusCheckRollup,mergeStateStatus
gh pr list --repo NVIDIA/NemoClaw --label "<version>" --state merged --json number,title,url
gh issue list --repo NVIDIA/NemoClaw --label "<version>" --state open --json number,title,url
gh issue list --repo NVIDIA/NemoClaw --label "<version>" --state closed --json number,title,url
```

Show a brief progress line: `v0.0.8: 3/5 shipped (2 PRs open)`.

## Step 3: Pick One Action

From the open version-targeted items, pick the highest-value one:

1. **Ready-now PR** — green CI, no conflicts, no major CodeRabbit, has tests → follow [MERGE-GATE.md](MERGE-GATE.md)
2. **Salvage-now PR** — close to ready, needs small fix → follow [SALVAGE-PR.md](SALVAGE-PR.md)
3. **Security item** — touches risky areas → follow [SECURITY-SWEEP.md](SECURITY-SWEEP.md)
4. **Test-gap item** — risky code with weak tests → follow [TEST-GAPS.md](TEST-GAPS.md)
5. **Hotspot cooling** — repeated conflicts → follow [HOTSPOTS.md](HOTSPOTS.md)
6. **Sequencing needed** — too large for one pass → follow [SEQUENCE-WORK.md](SEQUENCE-WORK.md)

If all version-targeted items are blocked, fall back to the general backlog. Productive work on non-labeled items is better than waiting.

Prefer finishing one almost-ready contribution over starting a new refactor.

## Step 4: Execute

Follow the chosen workflow document. A good pass ends with one of:

- a PR approved, a fix pushed, a test gap closed, a hotspot mitigated, or a blocker surfaced.

## Step 5: Report Progress

After the action, show updated progress: `v0.0.8: 4/5 shipped (1 PR open)`.

If all version-targeted items are done, suggest running `/nemoclaw-maintainer-evening` early.

## Step 6: Update State

Update `.nemoclaw-maintainer/state.json`: `updatedAt`, queue summary, `activeWork`, and a short history entry. If state file doesn't exist, create it from [STATE-SCHEMA.md](STATE-SCHEMA.md). Ensure `.nemoclaw-maintainer` is in `.git/info/exclude`.

## Commit Hygiene

The prek "Regenerate agent skills from docs" hook auto-stages `.agents/skills/` files. Before every `git add` and `git commit` on a PR branch, run `git reset HEAD .agents/skills/nemoclaw-maintainer-*` to unstage them. Only commit skill files in dedicated skill PRs.

## Stop and Ask When

- Broad refactor or architecture decision needed
- Contributor intent unclear and diff would change semantics
- Multiple subsystems must change for CI
- Sensitive security boundaries with unclear risk
- Next step is opening a new PR or merging

## /loop Integration

Designed for `/loop 10m /nemoclaw-maintainer-day`. Each pass should produce compact output: what was done, what changed, what needs the user. Check `state.json` history to avoid re-explaining prior context on repeat runs.

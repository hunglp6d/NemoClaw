---
name: nemoclaw-maintainer-morning
description: Runs the morning maintainer standup for NemoClaw. Triages the backlog, determines the day's target version, labels selected items, surfaces stragglers from previous versions, and outputs the daily plan. Use at the start of the workday. Trigger keywords - morning, standup, start of day, daily plan, what are we shipping today.
user_invocable: true
---

# NemoClaw Maintainer Morning

Start the day: triage, pick a version target, label items, share the plan.

See [PR-REVIEW-PRIORITIES.md](../nemoclaw-maintainer-day/PR-REVIEW-PRIORITIES.md) for the daily cadence and review priorities.

## Step 1: Refresh

```bash
git fetch origin --tags --prune
```

## Step 2: Determine Target Version

Find the latest semver tag and compute the next patch bump:

```bash
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
```

The day's target is one patch above this (e.g., `v0.0.7` → target `v0.0.8`).

## Step 3: Check for Stragglers

Look for items still carrying an older version label (bumped from a previous evening):

```bash
gh issue list --repo NVIDIA/NemoClaw --label "<older-version>" --state open --json number,title,url --limit 50
gh pr list --repo NVIDIA/NemoClaw --label "<older-version>" --state open --json number,title,url --limit 50
```

Surface these first — the team needs to decide: relabel to today's target, or defer further.

## Step 4: Triage

Run the triage script to rank the full backlog:

```bash
node --experimental-strip-types --no-warnings .agents/skills/nemoclaw-maintainer-day/scripts/triage.ts --approved-only
```

If too few results, run without `--approved-only`. The script calls `gh-pr-merge-now --json`, enriches candidates with risky-area detection, and applies scoring weights. Output is JSON with `queue`, `nearMisses`, `hotClusters`, and `excludedReasonCounts`.

Also use `find-review-pr` to surface PRs with `security` + `priority: high` labels. Merge these into the candidate pool.

Review the ranked queue. Scoring weights:

| Weight | Condition |
|--------|-----------|
| +40 | merge-now, needs only maintainer review |
| +30 | near-miss with clear small fix path |
| +20 | security-sensitive and actionable |
| +5 | unusually old item |
| -100 | draft or non-trivial conflict |
| -80 | unresolved major CodeRabbit finding |
| -60 | broad red CI, no clear local fix |
| -20 | blocked on external admin action |

## Step 5: Label Version Targets

Present the ranked queue to the user. After they confirm which items to target, label them:

```bash
gh label create "<version>" --repo NVIDIA/NemoClaw --description "Release target" --color "1d76db" 2>/dev/null || true
gh pr edit <number> --repo NVIDIA/NemoClaw --add-label "<version>"
gh issue edit <number> --repo NVIDIA/NemoClaw --add-label "<version>"
```

## Step 6: Output the Daily Plan

| Target | Item | Type | Owner | Next action |
|--------|------|------|-------|-------------|
| v0.0.8 | [#1234](https://github.com/NVIDIA/NemoClaw/pull/1234) | PR | @author | Run merge gate |
| v0.0.8 | [#1235](https://github.com/NVIDIA/NemoClaw/issues/1235) | Issue | unassigned | Needs PR |

Include: total items targeted, how many are PRs vs issues, how many are already merge-ready.

Pipe triage output into state:

```bash
node --experimental-strip-types --no-warnings .agents/skills/nemoclaw-maintainer-day/scripts/triage.ts | node --experimental-strip-types --no-warnings .agents/skills/nemoclaw-maintainer-day/scripts/state.ts set-queue
```

## Notes

- This skill runs once at the start of the day. Use `/nemoclaw-maintainer-day` during the day to execute.
- The target version label is the source of truth for "what we're shipping today."
- Stragglers from previous versions should be addressed first — they already slipped once.

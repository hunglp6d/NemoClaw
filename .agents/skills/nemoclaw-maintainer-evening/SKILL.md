---
name: nemoclaw-maintainer-evening
description: Runs the end-of-day maintainer handoff for NemoClaw. Checks version target progress, bumps stragglers to the next patch version, generates a QA handoff summary, and cuts the release tag. Use at the end of the workday. Trigger keywords - evening, end of day, EOD, wrap up, ship it, cut tag, handoff, done for the day.
user_invocable: true
---

# NemoClaw Maintainer Evening

Wrap up the day: check progress, bump stragglers, summarize for QA, cut the tag.

See [PR-REVIEW-PRIORITIES.md](../nemoclaw-maintainer-day/PR-REVIEW-PRIORITIES.md) for the daily cadence.

## Step 1: Determine Target Version

```bash
git fetch origin --tags
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
```

The target version is one patch above the latest tag. Confirm by checking which version label is on open items:

```bash
gh issue list --repo NVIDIA/NemoClaw --label "v*" --state open --json number,title,labels --limit 100
gh pr list --repo NVIDIA/NemoClaw --label "v*" --state open --json number,title,labels --limit 100
```

## Step 2: Check Progress

Gather all items labeled with the target version:

```bash
gh pr list --repo NVIDIA/NemoClaw --label "<version>" --state merged --json number,title,url
gh pr list --repo NVIDIA/NemoClaw --label "<version>" --state open --json number,title,url
gh issue list --repo NVIDIA/NemoClaw --label "<version>" --state closed --json number,title,url
gh issue list --repo NVIDIA/NemoClaw --label "<version>" --state open --json number,title,url
```

Present a progress summary:

| Status | Count | Items |
|--------|-------|-------|
| Shipped | 4 | #1234, #1235, #1236, #1237 |
| Still open | 1 | #1238 |

## Step 3: Bump Stragglers

For each item still open, move it to the next patch version:

```bash
# Compute next version (target patch + 1)
gh label create "<next-version>" --repo NVIDIA/NemoClaw --description "Release target" --color "1d76db" 2>/dev/null || true
gh issue edit <number> --repo NVIDIA/NemoClaw --remove-label "<version>" --add-label "<next-version>"
gh pr edit <number> --repo NVIDIA/NemoClaw --remove-label "<version>" --add-label "<next-version>"
```

Tell the user what got bumped and why (still open at EOD).

## Step 4: Generate Handoff Summary

Build a summary for the QA team:

1. **Commits since last tag**: `git log --oneline <previous-tag>..origin/main`
2. **Risky areas touched**: cross-reference changed files with [RISKY-AREAS.md](../nemoclaw-maintainer-day/RISKY-AREAS.md)
3. **Suggested test focus**: based on risky areas and the nature of changes

Format as a concise summary the user can paste into the tag annotation or a handoff channel.

## Step 5: Cut the Tag

Load `cut-release-tag`. The version is already known — default to patch bump, but still show the commit and changelog for confirmation.

## Step 6: Confirm and Share

After the tag is cut, present the final summary:

- **Tag**: `v0.0.8` at commit `abc1234`
- **Shipped**: 4 items (#1234, #1235, #1236, #1237)
- **Bumped to v0.0.9**: 1 item (#1238 — still needs CI fix)
- **QA focus areas**: installer changes, new onboard preset

This summary can be shared in the team's handoff channel.

## Step 7: Update State

Record in `.nemoclaw-maintainer/state.json`: tag cut, items shipped, items bumped, handoff summary.

## Notes

- Never cut a tag without user confirmation.
- If nothing was labeled or nothing shipped, ask whether to skip the tag today.
- Version labels are living markers: they always mean "ship in this version." If an item slips, the label moves forward.

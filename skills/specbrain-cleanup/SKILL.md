---
name: specbrain-cleanup
description: Use whenever the user wants to remove worktrees/branches left behind by specbrain-orchestrate, once they've merged the integration branch (via PR or manually) - only ever touches a worktree/branch that git itself confirms is already merged into main/master, leaving anything still open or dirty untouched. Suggested (never auto-run) by specbrain-consolidate once a demand's knowledge has been consolidated. Embodies the Tech Lead persona in the Specbrain pipeline.
---

# Specbrain Cleanup

## Overview

Remove the git worktrees and branches `specbrain-orchestrate` leaves behind, once their content has actually landed in `<main-branch>` (via the user's own merge or PR — this skill never merges anything itself). Embodies the Tech Lead persona in the Specbrain pipeline.

**Requires:** none beyond a local git checkout of the project — no `specbrain` MCP tools are needed for this skill.

**Announce at start:** "Estou usando a skill specbrain-cleanup para remover worktrees e branches já mescladas."

**Safety principle:** only ever touch a worktree/branch that `git` itself confirms is already an ancestor of `<main-branch>` — that means its content already lives in `<main-branch>`'s history, so removing the worktree/branch destroys nothing. Never guess, never use `--force`, never touch anything outside the `specbrain-integration-*`/`specbrain-task-*` naming convention `specbrain-orchestrate` creates.

## Process

### Step 1: Remove merged worktrees and branches

1. Run `pwd` and confirm you're in the repository's main worktree (not inside a `specbrain-integration-*`/`specbrain-task-*` worktree).
2. Detect `<main-branch>`: `git show-ref --verify --quiet refs/heads/main` — if it exits 0, `<main-branch>` is `main`, otherwise `master`.
3. `git worktree list --porcelain` to enumerate every worktree.
4. For each worktree whose path matches `../specbrain-integration-*` or `../specbrain-task-*` (skip the main worktree and anything else — never touch a worktree outside this naming convention):
   - If it's in a detached-HEAD state (no branch), skip it and note it for manual review.
   - Run `git merge-base --is-ancestor <branch> <main-branch>`. Non-zero exit → not merged yet; skip it and note it as still open (e.g. "integration branch `specbrain/<design-short>` — not yet merged into `<main-branch>`, awaiting its PR").
   - Exit 0 → merged. Run `git worktree remove <path>` (no `--force`; if this fails because the worktree has uncommitted changes, skip it and report that instead of discarding local state). Then `git branch -d <branch>` (safe delete — refuses if not actually merged, a redundant second check).
5. Keep a running list of what was removed and what was left alone, for Step 2's report.

### Step 2: Report

Tell the user which worktrees/branches were removed (merged) vs. left alone (not yet merged, detached, or dirty) and why.

## Checklist

- [ ] Confirmed running from the main worktree, detected `<main-branch>`
- [ ] Enumerated worktrees via `git worktree list --porcelain`, touched only the `specbrain-integration-*`/`specbrain-task-*` ones
- [ ] Removed only worktrees/branches confirmed merged via `git merge-base --is-ancestor`; left everything else alone with a reason
- [ ] Reported removals/skips to the user

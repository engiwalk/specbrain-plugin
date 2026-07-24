---
name: octopus-orchestrate
description: Use after octopus-engineering has produced tasks (with metadata.depends_on) for a design - builds a dependency graph, executes the tasks in parallel waves (one git worktree per task, off a dedicated integration-branch worktree), and merges each into the integration branch only after it passes an adversarial code quality/security gate. Embodies the Software Engineer persona in the Octopus pipeline, in its parallel-execution phase.
---

# Octopus Orchestrate

## Overview

Take the tasks produced by `octopus-engineering` for one design and implement them in parallel — one git worktree per task, grouped into dependency-respecting waves — with an adversarial code quality/security gate before any task's work is merged. Embodies the Software Engineer persona in the Octopus pipeline, in its parallel-execution phase ("the octopus"). Unlike the adversarial gate in `octopus-engineering` (which checks a spec before implementation) or `octopus-homologacao` (which checks acceptance criteria after implementation), this gate checks only code quality and security of each task's diff before it's allowed into the shared integration branch.

**Requires:** the `octopus` MCP server connected (tools prefixed `mcp__octopus__`), and at least one task artifact with `status="draft"` already saved for this project (normally via `octopus-engineering`).

**Roles:** the controller (this Claude Code session) is the only one that creates, merges, and removes worktrees — always sequentially, so two `git worktree`/`git merge` operations never race on the same `.git`. Subagents dispatched in parallel (via the `Agent` tool) only implement and review code inside a worktree they're handed already-created — they never create, merge, or remove worktrees themselves.

**Announce at start:** "Estou usando a skill octopus-orchestrate para implementar as tasks desta demanda em paralelo."

**Content language:** All free text persisted to the database via `save_artifact`/`save_learning` — artifact `content`, `learnings` `pattern`/`content`/`tags`, and any free-text field inside `metadata` (e.g. `acceptance_criteria`, `criteria_results[].evidence`) — must be written in English, regardless of the language the conversation is in. Proper nouns, code identifiers, and external system/API names stay exactly as given, untranslated. Everything said TO the user (questions, the announcement above, reports) stays in the user's language, unchanged.

## Process

### Step 1: Resolve the scope

Run `pwd` to get the current project path. Call `mcp__octopus__get_or_create_project`. Then call `mcp__octopus__list_artifacts` with `type="task"` and `status="draft"`. If none are returned, tell the user to run `octopus-engineering` first and stop here.

Group the returned tasks by `parent_id` (each group belongs to one design). If there is more than one group, list each group's `parent_id` and how many draft tasks it has, and ask the user which one to process in this run. Proceed with the single chosen group as "the batch" for the rest of this skill.

Also call `mcp__octopus__list_artifacts` with `type="task"` (no `status` filter) and keep only the ones whose `parent_id` matches the chosen design — call this "the design's full task set." This is what lets Step 2 tell a genuinely unknown dependency apart from one that already finished in an earlier run of this skill.

Run `git status --porcelain`. If it prints anything, stop and tell the user to commit or stash their changes before running this skill.

Ask the user one question, once for this whole run (not per wave, not per task): whether to scope test execution to each task's changed/affected files (default, recommended — the full suite already runs in CI) or run the full test suite for every task in this run. Record the answer as `<test-scope>` (`scoped` or `full`) and reuse it for every task in every wave below — never re-ask this within the run.

### Step 2: Build the dependency graph and compute waves

For every task in the batch, read `metadata.depends_on` (treat a missing key as `[]`). For each id listed, resolve it against the design's full task set from Step 1:
- If it matches another task in the batch, it's a real graph edge — used for wave computation below.
- If it matches a task in the design's full task set with `status="done"` (finished in an earlier run of this skill), treat it as already satisfied: it never blocks this task, and it does not become a graph edge.
- Otherwise (it matches no task in the design at all, or matches one with any other status — `in_progress`, `failed`, `blocked`, or a `draft` task somehow missing from the batch): stop and report exactly which task references which unresolved id.

Compute waves with Kahn's algorithm over the batch, using only the real graph edges from above (already-`done` dependencies are pre-satisfied and never create an edge):
- Wave 1 = every task in the batch whose `depends_on` entries are all either empty or already-`done`.
- Each subsequent wave = every not-yet-assigned task whose remaining (in-batch) `depends_on` entries are all in already-assigned waves.
- If, after this process, some tasks remain unassigned, they form a dependency cycle. Stop immediately — before Step 3, before creating anything — and report exactly which tasks are involved in the cycle.

### Step 3: Create the integration branch in its own worktree

Detect the repository's main branch: run `git show-ref --verify --quiet refs/heads/main`; if it exits 0, the main branch is `main`, otherwise it's `master`. Remember this as `<main-branch>` — report it back to the user in Step 6. **Never check it out.**

Create the integration branch directly in its own dedicated worktree, from `<main-branch>`, without ever touching the repository's main worktree:

```bash
git worktree add ../octopus-integration-<design-short> -b octopus/<design-short> <main-branch>
```

(`<design-short>` = the first 8 characters of the design artifact's `id` — the `parent_id` shared by every task in the batch.)

From here on, every git operation in this run uses `git -C ../octopus-integration-<design-short> ...` — never the repository's main directory. This is what lets multiple orchestration runs (different demands, or even different Claude Code sessions) coexist on the same repository without colliding: each run lives entirely inside its own integration worktree, always starting from `<main-branch>`; the main worktree — and whatever else is using it — is never touched.

### Step 4: Execute each wave, in order

For the current wave:

1. **Create worktrees (controller, sequential).** For each task in the wave: `git -C ../octopus-integration-<design-short> worktree add ../octopus-task-<task-short> -b octopus/task-<task-short> octopus/<design-short>` (`<task-short>` = the first 8 characters of that task's `id`). Then call `mcp__octopus__update_artifact_status` with that task's `id` and `status="in_progress"`.
2. **Dispatch implementers (parallel).** In a single message, dispatch one subagent per task in the wave via the `Agent` tool (`general-purpose` type). Each dispatch must include: the absolute path of that task's worktree (the subagent must do all its work there, via `cd`, never in the integration or main worktree); the task's `content` and `metadata.acceptance_criteria`; an instruction to call `mcp__octopus__search_learnings` and `mcp__octopus__search_context` first (both return compact previews - fetch full content of anything relevant via `mcp__octopus__get_learning`/`mcp__octopus__get_artifact` before relying on it), so it reuses whatever the project already knows before writing new code; **an explicit instruction that every one of these `mcp__octopus__*` calls must use `project_path=<the main repository path resolved in Step 1>` — never the worktree path it's `cd`ed into or its own `pwd`, which would otherwise register a spurious separate project per task worktree**; an instruction to implement the minimum necessary to satisfy the acceptance criteria — no speculative abstractions, no unrequested configurability, no code beyond what's asked, except never trimming trust-boundary validation, data-loss handling, security, or accessibility work the criteria call for; an instruction to implement and commit inside that worktree; and a requirement that its final message end with exactly one line: `STATUS: DONE` (implementation complete and committed) or `STATUS: BLOCKED: <reason>` (could not complete). For running tests, follow `<test-scope>` from Step 1: if `scoped`, instruct it to run only the tests relevant to the files it changed — identified using the project's own conventions (test files that mirror the changed source paths, tests referencing the changed symbols, or whatever `search_context`/`search_learnings` surfaced about how this project organizes its tests) — never the full suite; if `full`, instruct it to run the project's entire test suite.
3. **Handle implementer results.** For a task whose implementer reported `BLOCKED`: mark it `failed` via `update_artifact_status` immediately — there is nothing to gate — and note the reason for the final report. For a task whose implementer reported `DONE`, continue to the gate below.
4. **Run the quality/security gate.** For each `DONE` task, get its diff: `git -C ../octopus-task-<task-short> diff octopus/<design-short> HEAD`. Dispatch one gate subagent (via the `Agent` tool, `general-purpose` type) with this exact framing: its job is to review this diff **only for code quality and security issues** — not whether it satisfies the task's acceptance criteria (that's `octopus-homologacao`'s job, run separately by the user later). Code quality explicitly includes over-engineering: speculative abstractions, unrequested configurability, or code beyond what the acceptance criteria require are grounds for `FAILS` — but never flag as over-engineering anything that implements trust-boundary validation, data-loss handling, security, or accessibility work the task actually calls for. Give it the full diff and ask it to report a verdict (`PASSES` or `FAILS`) with concrete issues if it fails. Regardless of `<test-scope>`: if it chooses to run anything to verify a concern, it must never run the full suite on its own initiative — only tests scoped to the diff. Same guardrail as Step 4.2: if it calls any `mcp__octopus__*` tool for any reason (e.g. checking `search_learnings`/`search_context` for a project convention before judging the diff), it must use `project_path=<the main repository path resolved in Step 1>` — never the worktree path or its own `pwd`.
5. **On `FAILS`:** dispatch a fix subagent (via the `Agent` tool) pointed at the same worktree, with the gate's concrete findings, instructing it to fix the issues and commit again — including the same `mcp__octopus__*` project_path guardrail as Step 4.2 and the gate above, in case it searches learnings/context to inform the fix. Then re-run the gate (previous bullet) against the updated diff. Allow up to 3 gate attempts total per task. For re-running tests, follow the same `<test-scope>` rule as the implementer dispatch above: `scoped` re-runs only the task-relevant tests (plus anything newly touched by the fix itself); `full` re-runs the entire suite.
6. **If still `FAILS` after 3 attempts:** mark the task `failed` via `update_artifact_status`. Leave its worktree and branch exactly as they are — do not merge, do not remove — so the user can inspect what was attempted.
7. **On `PASSES`** (on any attempt): merge it into the integration branch — `git -C ../octopus-integration-<design-short> merge --no-ff octopus/task-<task-short>` — mark the task `done` via `update_artifact_status`, then remove its worktree: `git -C ../octopus-integration-<design-short> worktree remove ../octopus-task-<task-short>`.

After every task in the wave has reached `done` or `failed`: for every task in a later wave whose `depends_on` includes a task that ended `failed` (directly, or transitively through another task already marked `blocked`), mark it `blocked` via `update_artifact_status` — it must never be dispatched. Repeat this cascade check after every wave, since a wave can blocked-cascade into the wave after it too.

Proceed to the next wave, considering only its non-`blocked` tasks. A wave left with zero runnable tasks is simply skipped.

### Step 5: Record indicators

For each task that went through the gate (ended `done`, or `failed` after exhausting attempts): call `mcp__octopus__record_indicator` with `key="gate_pass_rate"`, `value={"passed": true|false, "attempts": <n>}`, `source="quality_security_gate"`. Tasks that ended `failed` because their implementer reported `BLOCKED`, or that ended `blocked` via cascade, never reached the gate — do not record this indicator for them.

At the end of the whole run: call `mcp__octopus__record_indicator` with `key="orchestration_summary"`, `value={"tasks_total": <n>, "tasks_done": <n>, "tasks_failed": <n>, "tasks_blocked": <n>}`, `source="orchestration"`.

### Step 6: Report

Tell the user: how many tasks ended `done`, `failed`, and `blocked` — naming each failed/blocked task and why — the integration branch's name (`octopus/<design-short>`) and its worktree path (`../octopus-integration-<design-short>`), and that no merge back into `<main-branch>` was done automatically. From here, the user can ask for a PR to be opened from the integration branch, or merge it into `<main-branch>` manually whenever they're ready — the main worktree was never touched during this run.

## Checklist

- [ ] Resolved the scope: one design's `draft` tasks, confirmed a clean working tree
- [ ] Asked the test-scope question once for the whole run (`scoped` default or `full`), never re-asked per wave/task
- [ ] Built the dependency graph; stopped and reported on any unknown dependency id or cycle, before creating anything
- [ ] Created the integration branch from `<main-branch>`, in its own dedicated worktree — never checked out in the main repository
- [ ] For each wave: created worktrees sequentially, dispatched implementers in parallel honoring `<test-scope>`, ran the quality/security gate (with fix-and-re-gate up to 3 attempts, also honoring `<test-scope>`) before any merge
- [ ] Cascaded `blocked` status correctly to dependents of any `failed` task
- [ ] Merged only tasks that passed the gate, into the integration worktree; preserved worktrees/branches of `failed` tasks
- [ ] Recorded `gate_pass_rate` per gated task and `orchestration_summary` for the run
- [ ] Reported done/failed/blocked counts, the integration branch/worktree location, and did not auto-merge into `<main-branch>`

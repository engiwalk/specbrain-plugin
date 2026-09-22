---
name: specbrain-orchestrate
description: Use after specbrain-engineering has produced tasks (with metadata.depends_on) for a design - builds a dependency graph, executes the tasks in parallel waves (one git worktree per task, off a dedicated integration-branch worktree), and merges each into the integration branch only after the project's own mandatory checks pass on it, with an advisory code quality/security review alongside. Embodies the Software Engineer persona in the Specbrain pipeline, in its parallel-execution phase.
---

# Specbrain Orchestrate

## Overview

Take the tasks produced by `specbrain-engineering` for one design and implement them in parallel — one git worktree per task, grouped into dependency-respecting waves. Embodies the Software Engineer persona in the Specbrain pipeline, in its parallel-execution phase.

**What decides a merge here is deterministic:** the project's own declared checks — tests, lint, types, build — run in the task's worktree, and their exit codes are recorded as a verification. A task cannot even be marked `done` without a passing one; the server refuses. An adversarial code quality/security review still runs on each diff, but as **advice**: one model judging another model's diff has no ground truth, so it informs what to fix rather than deciding what merges. And because each task's checks pass in isolation by construction, the mandatory checks run once more against the integration branch after every wave — that is the only place two individually-green tasks can show up red together.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`), and at least one task artifact with `status="draft"` already saved for this project (normally via `specbrain-engineering`).

**Roles:** the controller (this Claude Code session) is the only one that creates, merges, and removes worktrees — always sequentially, so two `git worktree`/`git merge` operations never race on the same `.git`. Subagents dispatched in parallel (via the `Agent` tool) only implement and review code inside a worktree they're handed already-created — they never create, merge, or remove worktrees themselves.

**Announce at start:** tell the user you are using the `specbrain-orchestrate` skill to implement this demand's tasks in parallel — written **in the language the user is writing in**, not translated from this file. The skill name itself is never translated.

**Content language:** All free text persisted to the database via `save_artifact`/`save_learning` — artifact `content`, `learnings` `pattern`/`content`/`tags`, and any free-text field inside `metadata` (e.g. `acceptance_criteria`, `criteria_results[].evidence`) — must be written in English, regardless of the language the conversation is in. Proper nouns, code identifiers, and external system/API names stay exactly as given, untranslated. Everything said TO the user (questions, the announcement above, reports) stays in the user's language, unchanged.

## Process

### Step 1: Resolve the scope

Run `pwd` to get the current project path. Call `mcp__specbrain__get_or_create_project`. Then call `mcp__specbrain__list_artifacts` with `type="task"` and `status="draft"`. If none are returned, tell the user to run `specbrain-engineering` first and stop here.

**Directives for this skill's stages.** Once the batch's design is known (below), call `mcp__specbrain__get_directives` twice, once per stage this skill drives: `stage="orchestrate.implement"` (steering for the implementer subagents) and `stage="orchestrate.gate"` (steering for the quality/security gate), both with `artifact_id` = the design's `id`. **This controller makes both calls and passes the returned instructions into each subagent's prompt as text — subagents never call `get_directives` themselves**, so one run produces one injection record per stage instead of one per subagent. If `dropped_count` is greater than zero on either call, tell the user some directives didn't fit the context budget: silently truncated steering is worse than none.

Group the returned tasks by `parent_id` (each group belongs to one design). If there is more than one group, list each group's `parent_id` and how many draft tasks it has, and ask the user which one to process in this run. Proceed with the single chosen group as "the batch" for the rest of this skill.

Also call `mcp__specbrain__list_artifacts` with `type="task"` (no `status` filter) and keep only the ones whose `parent_id` matches the chosen design — call this "the design's full task set." This is what lets Step 2 tell a genuinely unknown dependency apart from one that already finished in an earlier run of this skill.

Run `git status --porcelain`. If it prints anything, stop and tell the user to commit or stash their changes before running this skill.

**Resolve this project's checks.** Call `mcp__specbrain__get_project_checks`. If it comes back empty, discover them once from the repository itself (its test/lint/typecheck/build scripts — `package.json`, `pyproject.toml`, `Makefile`, CI config), show the user the exact commands you propose and which should be `mandatory`, and call `mcp__specbrain__set_project_checks` once they confirm. Every later run then reuses them instead of guessing. Keep the resolved list as `<checks>` for the rest of this run.

A task in this run reaches `done` only with a recorded verification whose mandatory checks all exited zero. That rule is enforced by the server, not by this skill: `update_artifact_status` refuses with `{"refused": "verification_required", ...}` otherwise. Treat that refusal as information, not as an obstacle to work around.

Ask the user one question, once for this whole run (not per wave, not per task): whether to scope test execution to each task's changed/affected files (default, recommended — the integration check below runs the mandatory checks in full after each wave) or run the full test suite for every task in this run. Record the answer as `<test-scope>` (`scoped` or `full`) and reuse it for every task in every wave below — never re-ask this within the run.

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
git worktree add ../specbrain-integration-<design-short> -b specbrain/<design-short> <main-branch>
```

(`<design-short>` = the first 8 characters of the design artifact's `id` — the `parent_id` shared by every task in the batch.)

From here on, every git operation in this run uses `git -C ../specbrain-integration-<design-short> ...` — never the repository's main directory. This is what lets multiple orchestration runs (different demands, or even different Claude Code sessions) coexist on the same repository without colliding: each run lives entirely inside its own integration worktree, always starting from `<main-branch>`; the main worktree — and whatever else is using it — is never touched.

### Step 4: Execute each wave, in order

For the current wave:

1. **Create worktrees (controller, sequential).** For each task in the wave: `git -C ../specbrain-integration-<design-short> worktree add ../specbrain-task-<task-short> -b specbrain/task-<task-short> specbrain/<design-short>` (`<task-short>` = the first 8 characters of that task's `id`). Then call `mcp__specbrain__update_artifact_status` with that task's `id` and `status="in_progress"`.
2. **Dispatch implementers (parallel).** In a single message, dispatch one subagent per task in the wave via the `Agent` tool (`general-purpose` type). Each dispatch must include: the `orchestrate.implement` directives from Step 1, quoted verbatim as instructions the subagent must follow; the absolute path of that task's worktree (the subagent must do all its work there, via `cd`, never in the integration or main worktree); the task's `content` and `metadata.acceptance_criteria`; an instruction to call `mcp__specbrain__search_learnings` and `mcp__specbrain__search_context` first (both return compact previews - fetch full content of anything relevant via `mcp__specbrain__get_learning`/`mcp__specbrain__get_artifact` before relying on it), so it reuses whatever the project already knows before writing new code; an instruction to weigh a `proposed` learning as a lead rather than a fact, and to call `mcp__specbrain__record_learning_usage` (with `stage="orchestrate.implement"` and `artifact_id` = its own task's id) for the learnings it actually relied on; **an explicit instruction that every one of these `mcp__specbrain__*` calls must use `project_path=<the main repository path resolved in Step 1>` — never the worktree path it's `cd`ed into or its own `pwd`, which would otherwise register a spurious separate project per task worktree**; an instruction to implement the minimum necessary to satisfy the acceptance criteria — no speculative abstractions, no unrequested configurability, no code beyond what's asked, except never trimming trust-boundary validation, data-loss handling, security, or accessibility work the criteria call for; an instruction to implement and commit inside that worktree; the `<checks>` resolved in Step 1, with an instruction to run every mandatory one inside its worktree and report, for each, the **exact command it ran and the exit code it got** (plus a short excerpt of the output when non-zero) — reporting a check it did not actually run is the one thing that makes this whole gate worthless; and a requirement that its final message end with exactly one line: `STATUS: DONE` (implementation complete and committed) or `STATUS: BLOCKED: <reason>` (could not complete). For running tests, follow `<test-scope>` from Step 1: if `scoped`, instruct it to run only the tests relevant to the files it changed — identified using the project's own conventions (test files that mirror the changed source paths, tests referencing the changed symbols, or whatever `search_context`/`search_learnings` surfaced about how this project organizes its tests) — never the full suite; if `full`, instruct it to run the project's entire test suite.
3. **Handle implementer results.** For a task whose implementer reported `BLOCKED`: mark it `failed` via `update_artifact_status` immediately — there is nothing to gate — and note the reason for the final report. For a task whose implementer reported `DONE`, continue below.
4. **Record the verification (the actual gate).** For each `DONE` task, call `mcp__specbrain__record_verification` with `task_id` and the checks the implementer reported — each with its exact `command`, its `exit_code`, and an `output_excerpt` when it failed. If any mandatory check is non-zero, this task does not merge: dispatch a fix subagent pointed at the same worktree with the failing check's command and output, have it fix and re-run, and record a new verification. Allow up to 3 attempts. If it is still red after that, mark the task `failed`, leave its worktree and branch in place for inspection, and move on. A red mandatory check is the one thing in this skill that no judgment call can override.
5. **Run the quality/security review (advisory).** For each `DONE` task, get its diff: `git -C ../specbrain-task-<task-short> diff specbrain/<design-short> HEAD`. Dispatch one gate subagent (via the `Agent` tool, `general-purpose` type) with the `orchestrate.gate` directives from Step 1 quoted verbatim, plus this exact framing: its job is to review this diff **only for code quality and security issues** — not whether it satisfies the task's acceptance criteria (that's `specbrain-review`'s job, run separately by the user later). Code quality explicitly includes over-engineering: speculative abstractions, unrequested configurability, or code beyond what the acceptance criteria require are grounds for `FAILS` — but never flag as over-engineering anything that implements trust-boundary validation, data-loss handling, security, or accessibility work the task actually calls for. Give it the full diff and ask it to report a verdict (`PASSES` or `FAILS`) with concrete issues if it fails. **This verdict is advice, not a gate.** One model judging another model's diff has no ground truth, so it does not by itself decide what merges — the deterministic checks in Step 4.4 do. Read its findings yourself: act on the ones that hold up against the real code (dispatch a fix subagent, then re-run Step 4.4's checks and record a new verification), and say so plainly when you dismiss one and why. Regardless of `<test-scope>`: if it chooses to run anything to verify a concern, it must never run the full suite on its own initiative — only tests scoped to the diff. Same guardrail as Step 4.2: if it calls any `mcp__specbrain__*` tool for any reason (e.g. checking `search_learnings`/`search_context` for a project convention before judging the diff), it must use `project_path=<the main repository path resolved in Step 1>` — never the worktree path or its own `pwd`.
6. **Fixing what the review found:** dispatch a fix subagent (via the `Agent` tool) pointed at the same worktree, with the concrete findings you judged worth acting on, instructing it to fix them, re-run the mandatory checks and commit again — including the same `mcp__specbrain__*` project_path guardrail as Step 4.2. Record a new verification from what it reports, then re-read the diff. For re-running tests, follow the same `<test-scope>` rule as the implementer dispatch above: `scoped` re-runs only the task-relevant tests (plus anything newly touched by the fix itself); `full` re-runs the entire suite.
7. **Merge when the verification is green:** `git -C ../specbrain-integration-<design-short> merge --no-ff specbrain/task-<task-short>`, mark the task `done` via `update_artifact_status` (which the server accepts only because a passing verification exists), then remove its worktree: `git -C ../specbrain-integration-<design-short> worktree remove ../specbrain-task-<task-short>`. If `update_artifact_status` comes back `{"refused": "verification_required"}`, something is out of order — do not merge, report it.
8. **Verify the integration branch itself, once per wave.** After the wave's merges, run every mandatory check from `<checks>` inside `../specbrain-integration-<design-short>` — in full, regardless of `<test-scope>` — and record the result with `mcp__specbrain__record_verification` using `scope="integration"`, `integration_branch="specbrain/<design-short>"` and no `task_id`. If anything is red, **stop the wave chain here**: report which check failed and its output, and do not start the next wave. This is the only place a merge-interaction failure can surface — each task's own checks passed in isolation by construction, so two green tasks can still be red together.

After every task in the wave has reached `done` or `failed`: for every task in a later wave whose `depends_on` includes a task that ended `failed` (directly, or transitively through another task already marked `blocked`), mark it `blocked` via `update_artifact_status` — it must never be dispatched. Repeat this cascade check after every wave, since a wave can blocked-cascade into the wave after it too.

Proceed to the next wave, considering only its non-`blocked` tasks. A wave left with zero runnable tasks is simply skipped.

### Step 5: Record indicators

For each task the LLM review actually looked at: call `mcp__specbrain__record_indicator` with `key="llm_review_pass_rate"`, `value={"passed": true|false, "attempts": <n>, "checks_were_green": true|false}`, `source="quality_security_review"`. This is a **calibration** metric — it says how often the reviewer approved, which describes the reviewer, not the code. `checks_were_green` is what makes it readable later: a reviewer that always approves work whose deterministic checks were already green is measuring nothing, and one that rejects work the checks call fine is worth reading closely. Tasks whose implementer reported `BLOCKED`, or that ended `blocked` via cascade, were never reviewed — do not record this for them.

(The old `gate_pass_rate`/`quality_security_gate` readings stay in the database as history from when that verdict could block a merge. This step does not keep feeding that key.)

At the end of the whole run: call `mcp__specbrain__record_indicator` with `key="orchestration_summary"`, `value={"tasks_total": <n>, "tasks_done": <n>, "tasks_failed": <n>, "tasks_blocked": <n>}`, `source="orchestration"`.

### Step 6: Report

Tell the user: how many tasks ended `done`, `failed`, and `blocked` — naming each failed/blocked task and why — the integration branch's name (`specbrain/<design-short>`) and its worktree path (`../specbrain-integration-<design-short>`), and that no merge back into `<main-branch>` was done automatically. From here, the user can ask for a PR to be opened from the integration branch, or merge it into `<main-branch>` manually whenever they're ready — the main worktree was never touched during this run.

## Checklist

- [ ] Resolved the scope: one design's `draft` tasks, confirmed a clean working tree
- [ ] Loaded `get_directives` for `orchestrate.implement` and `orchestrate.gate` in the controller, and passed each set verbatim into the matching subagents' prompts
- [ ] Asked the test-scope question once for the whole run (`scoped` default or `full`), never re-asked per wave/task
- [ ] Built the dependency graph; stopped and reported on any unknown dependency id or cycle, before creating anything
- [ ] Created the integration branch from `<main-branch>`, in its own dedicated worktree — never checked out in the main repository
- [ ] Resolved `<checks>` via `get_project_checks` (discovering and saving them with the user if the project had none)
- [ ] For each wave: created worktrees sequentially, dispatched implementers in parallel honoring `<test-scope>`, recorded a verification per task from the real commands and exit codes, and merged only tasks whose mandatory checks were green
- [ ] Treated the LLM review as advice — acted on what held up, said what was dismissed and why — never as the thing that decided a merge
- [ ] Ran the mandatory checks against the integration branch after each wave's merges, recorded them with `scope="integration"`, and stopped the chain if any were red
- [ ] Cascaded `blocked` status correctly to dependents of any `failed` task
- [ ] Merged only tasks that passed the gate, into the integration worktree; preserved worktrees/branches of `failed` tasks
- [ ] Recorded `llm_review_pass_rate` per reviewed task (with `checks_were_green`) and `orchestration_summary` for the run
- [ ] Reported done/failed/blocked counts, the integration branch/worktree location, and did not auto-merge into `<main-branch>`

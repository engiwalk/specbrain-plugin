---
name: specbrain-review
description: Use after tasks produced by specbrain-engineering have been manually implemented - verifies each acceptance criterion against the real code/behavior (reading files, running tests, optionally driving a browser), reports PASS/FAIL per criterion with concrete evidence, and saves the results. Embodies the QA persona in the Specbrain pipeline.
---

# Specbrain Review

## Overview

Verify that what was actually built satisfies the acceptance criteria written during Engenharia — checking real code and real behavior, not re-reading the spec and assuming it was followed. Embodies the QA persona in the Specbrain pipeline. Unlike the multi-lens review in `specbrain-engineering` (which checks a spec before implementation), this skill checks an implementation after the fact — there is no retry loop here: report the truth, and let the user decide what to fix.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`), and at least one task artifact already saved for this project (normally via `specbrain-engineering`).

**Announce at start:** "Estou usando a skill specbrain-review para validar o que foi construído."

**Content language:** All free text persisted to the database via `save_artifact`/`save_learning` — artifact `content`, `learnings` `pattern`/`content`/`tags`, and any free-text field inside `metadata` (e.g. `acceptance_criteria`, `criteria_results[].evidence`) — must be written in English, regardless of the language the conversation is in. Proper nouns, code identifiers, and external system/API names stay exactly as given, untranslated. Everything said TO the user (questions, the announcement above, reports) stays in the user's language, unchanged.

## Process

### Step 1: Resolve the project and find the tasks to validate

Run `pwd` to get the current project path. Call `mcp__specbrain__get_or_create_project`. Then call `mcp__specbrain__list_artifacts` with `type="task"` to find the tasks to validate. If none exist, tell the user to run `specbrain-engineering` first and stop here. If there are multiple tasks and it's not obvious which one(s) the user wants validated now, ask.

### Step 2: Verify each acceptance criterion against real code/behavior

For each task being validated, first call `mcp__specbrain__update_artifact_status` with that task's `id` and `status="in_review"` — this is what lets the Kanban board show which tasks are actively being validated right now. Then read `metadata.acceptance_criteria`. For each criterion:
- Find the relevant implementation using `Glob`/`Grep`/`Read`.
- Run the project's tests or specific commands relevant to this criterion using `Bash`, when doing so is possible and meaningful.
- Reach a verdict: `PASS` or `FAIL`, backed by concrete evidence — a file:line reference, a command and its actual output, or a specific observed behavior. Never a bare "looks correct" without evidence.

Do this for every criterion of every task being validated before moving on — don't stop at the first failure.

### Step 3: Multi-lens check against the real implementation

Reuses the same specialized reviewer agents `specbrain-engineering`'s multi-lens review uses (`specbrain-business-reviewer`, `specbrain-security-reviewer`, `specbrain-architecture-reviewer`, `specbrain-sre-reviewer`, `specbrain-performance-reviewer`) — but grounded against the real diff/implementation instead of a spec draft, which is strictly safer since there's actual code to check rather than a plan.

For each task validated: get its diff (the commits/changes that implemented this task). Decide which lenses are relevant — same judgment call as `specbrain-engineering` Step 3 (business/architecture nearly always relevant; security/performance/sre only when the task's changes actually touch those concerns) — never dispatch a lens "just in case." Dispatch the relevant ones directly, in parallel, via the `Agent` tool with `agentType` set to each lens's name, giving each: the diff, the task's `acceptance_criteria`, and the `project_path` resolved in Step 1 (every one of its `mcp__specbrain__*` calls must use this `project_path`, never its own `pwd` or the path of whatever worktree the code happens to live in).

Read every finding — still tagged `grounded`/`ungrounded`, still never a pass/fail verdict from the lens itself. Decide, together with the user for anything ambiguous, whether it's a real problem worth fixing now or a note for later; fold anything you judge real into the same evidence-backed format Step 2 uses — as a `FAIL` on the criterion it relates to, or as its own entry in the report if it doesn't map to an existing criterion.

### Step 4: Offer the optional browser-based verification

The pipeline chains artifacts as `context → spec → design → task` (each artifact's `parent_id` points to the one before it). To check whether this task's demand involved UI, walk that chain up from the task via `mcp__specbrain__get_artifact`: fetch the task's `parent_id` (a `design` artifact), then that artifact's `parent_id` (a `spec` artifact), then that artifact's `parent_id` (the `context` artifact) — three calls to `get_artifact` in total. If at any point a `parent_id` is missing (e.g., a task created without the full chain), stop walking and treat it as "no UI flag found."

If the resolved context artifact has `metadata.requires_ui_design == true`, ask the user (one question) whether they want to also validate visually/interactively via a real browser. If the context has no UI flag (or none was found), or if the user declines, skip to Step 5.

If they accept:
- Ask for the URL to test against (local dev server or staging) and any credentials needed for this session. Be explicit: **these are used only for this verification and are never saved** — not in `learnings`, not in `artifacts`, not anywhere persistent.
- Invoke the `chrome-devtools-mcp:chrome-devtools` skill (via the `Skill` tool) to drive the browser and check the relevant criteria the same way a real user would (navigate, interact, observe). Fold the results into the same PASS/FAIL-with-evidence format as Step 2.

### Step 5: Save the report

For each task validated, call `mcp__specbrain__save_artifact` with `project_path` from Step 1, `type="review_report"`, `parent_id` set to that task's `id`, `content` summarizing the outcome, and `metadata={"criteria_results": [{"criterion": "...", "passed": true|false, "evidence": "..."}, ...]}` covering every criterion checked (Step 2, Step 3's actioned findings, and Step 4 if run).

Then call `mcp__specbrain__update_artifact_status` for that same task with `status="done"` if every criterion passed, or `status="failed"` if at least one criterion failed — resolving the `in_review` set in Step 2.

### Step 6: Check whether the design is now fully reviewed

For each task validated in Step 5, its `parent_id` is a `design` artifact. For each distinct design touched this run: call `mcp__specbrain__list_artifacts` with `type="task"`, and keep only the ones whose `parent_id` matches that design — this is every task ever created for it, including any added later by `specbrain-refine`, since they share the same `parent_id`. If none of them are `draft`, `in_progress`, or `in_review` (every one has resolved to `done`, `failed`, or `blocked`), call `mcp__specbrain__update_artifact_status` on the design itself with `status="in_review"` and tell the user this demand is now waiting on their confirmation that everything actually works — not just that the acceptance criteria checked out mechanically. If some tasks for that design are still unresolved, leave its status alone; this isn't the run that closes it out.

### Step 7: Record indicators

For each task validated, call `mcp__specbrain__record_indicator` with `project_path` from Step 1, `key="review_pass_rate"`, `value={"criteria_passed": <n>, "criteria_total": <m>}`, `source="review"`.

For each lens dispatched in Step 3 for that task, also call `mcp__specbrain__record_indicator` with `key="review_panel_grounding_rate"`, `source="<lens name, e.g. business>"`, `value={"grounded": <n>, "ungrounded": <n>}` (counts among that lens's findings for this task). Once per task (not per lens): call `mcp__specbrain__record_indicator` with `key="review_panel_summary"`, `source="multi_lens_review_code"`, `value={"findings_total": <n>, "findings_actioned": <n>, "findings_dismissed": <n>}`. This is a distinct `source` from `specbrain-engineering`'s `multi_lens_review_spec` — they measure the same lenses at different stages (spec vs. real code) and should trend separately.

### Step 8: Save new learnings

If the verification surfaced a reusable pattern — a recurring bug shape, a testing gap, a convention worth remembering — save it via `mcp__specbrain__save_learning`, same principle as the other skills: only if something genuinely new was learned, beyond what individual lenses already saved for themselves in Step 3.

### Step 9: Report

Tell the user, per task: how many criteria passed out of how many, and for every failure, exactly what's wrong and where (pointing at the saved `review_report` for full detail) — including anything the multi-lens check in Step 3 surfaced and you judged worth acting on. Be direct about failures — this skill's value is in catching real problems, not in a reassuring summary. If any design was moved to `in_review` in Step 6, say so explicitly and remind the user that `specbrain-refine` is how to report back anything wrong found during that review.

## Checklist

- [ ] Resolved the project and identified the task(s) to validate
- [ ] Set each task's status to `in_review` before validating it
- [ ] Checked every acceptance criterion of every task against real code/behavior, each with concrete evidence
- [ ] Ran the multi-lens check against the real diff (relevant lenses only, judgment call), read every finding's grounding, decided with the user what was worth acting on
- [ ] Offered the optional browser verification when the demand involved UI, and never persisted any credentials used
- [ ] Saved a `review_report` per task validated, covering acceptance criteria and any actioned multi-lens findings
- [ ] Resolved each task's status to `done` or `failed` based on its criteria results
- [ ] For each design touched, checked whether every one of its tasks (across all rounds) is resolved, and if so moved it to `in_review`
- [ ] Recorded `review_pass_rate` per task validated, and `review_panel_grounding_rate`/`review_panel_summary` for the multi-lens check
- [ ] Saved any new learnings beyond what individual lenses already saved (or explicitly confirmed there were none)
- [ ] Reported clear, specific pass/fail results to the user, not a vague summary

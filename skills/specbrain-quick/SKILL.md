---
name: specbrain-quick
description: Use for a small, low-risk change that would be smothered by the full pipeline - a copy fix, a label, a narrow bug with an obvious cause, a config tweak. Classifies the demand's risk from closed questions first and refuses to continue if it comes out medium or high, records a context artifact and a single task, and still requires the project's mandatory checks to pass before that task can be marked done. Embodies the whole Specbrain pipeline compressed to what a small change actually needs. Automatically routed into by specbrain-discovery and specbrain-engineering when a demand classifies as low risk.
---

# Specbrain Quick

## Overview

The full pipeline exists because some changes are expensive to get wrong. Most changes are not. When a one-line copy fix costs the same ceremony as a payment-flow rewrite, people route around the tool for everyday work — and then the shared memory only ever sees the big demands, which is exactly when the habit fails to form.

This skill is the short path: classify the risk, save the context, save one task, verify it for real. **It skips ceremony, never verification** — a small change that breaks the build is still a broken build.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`).

**Announce at start:** tell the user you are using the `specbrain-quick` skill to handle this as a small, low-risk change — written **in the language the user is writing in**, not translated from this file. The skill name itself is never translated.

**Content language:** same rule as every other Specbrain skill — everything persisted via `save_artifact`/`save_learning` is written in English; everything said to the user stays in their language.

## Process

### Step 1: Resolve the project and its steering

Run `pwd`, call `mcp__specbrain__get_or_create_project`.

Call `mcp__specbrain__get_directives` with `stage="quick"` and follow every returned `instruction` verbatim. If `dropped_count` is greater than zero, say so to the user.

### Step 2: Classify the risk — before anything else

Call `mcp__specbrain__classify_demand_risk`, answering every signal. Answer from the repository where you can (does the change touch a migration? a public route? an auth middleware?) and **ask the user** for anything you cannot determine. An unanswered question is not a "no", and the tool refuses a missing answer rather than assuming one.

- **`low`** — continue with this skill.
- **`medium` or `high`** — stop here. Tell the user which signals triggered it, and that this demand goes through `specbrain-discovery` instead. Do not argue the classification down; if an answer was factually wrong, correct the answer and re-run the tool, and say that you did.

This is the entire safety property of the fast lane. The server enforces the other half — a task of a high-risk demand is refused unless it descends from a spec and a design — but by then you have already wasted the user's time.

### Step 3: Reuse what's already known

Call `mcp__specbrain__search_learnings` and `mcp__specbrain__search_context` with a query describing the change. Small demands are exactly where a forgotten convention bites, and this costs almost nothing. Call `mcp__specbrain__record_learning_usage` for anything you actually relied on, with `stage="quick"` and the context artifact's id once it exists.

### Step 4: Save the context

Call `mcp__specbrain__save_artifact` with `type="context"`, `content` describing the change and why (a few sentences is the right size here — a small demand does not earn a long document), and `metadata={"risk": <the full object from Step 2>, "requires_ui_design": false}`.

Keep the risk object whole, not just its level: the signals are what make it possible to check later whether demands classified low are quietly leaking defects.

### Step 5: Save one task

Call `mcp__specbrain__save_artifact` with `type="task"`, `parent_id` = the context artifact, `status="in_progress"`, and `metadata={"task_kind": "<feature|bug|tech_debt|chore>", "acceptance_criteria": [...]}`.

**One task.** If the change genuinely needs more than one, that is the signal that it was not small — stop and hand it to `specbrain-discovery`.

### Step 6: Implement it

Do the work in the current worktree. No subagents, no waves, no integration branch — the overhead of isolating a one-file change costs more than the change.

### Step 7: Verify, for real

Call `mcp__specbrain__get_project_checks`. If the project has none declared, discover them from the repository, confirm the commands with the user, and call `mcp__specbrain__set_project_checks` — every later run then reuses them.

Run every mandatory check and call `mcp__specbrain__record_verification` with each one's exact command and exit code. Then call `mcp__specbrain__update_artifact_status` with `status="done"`.

If it comes back `{"refused": "verification_required"}`, the change is not done. Fix it and record a passing verification. Speed is the point of this skill; skipping the part that tells you whether it works is not speed, it is guessing.

### Step 8: Save a learning, only if there is one

If the change surfaced a durable fact about the domain or the codebase, save it with `mcp__specbrain__save_learning`, passing `source_kind`, `source_ref` and `origin_artifact_id`. Most small changes teach nothing worth keeping — say so and move on rather than manufacturing a learning.

### Step 9: Report

Tell the user: the risk classification and what it was based on, what was changed, which checks ran and their results, and that this demand did not go through spec/design because it classified low. If they disagree with the classification, `specbrain-discovery` is how to run it properly.

## Checklist

- [ ] Loaded `get_directives(stage="quick")` and followed every returned instruction
- [ ] Classified the risk from answered signals — not assumed ones — and stopped if it wasn't `low`
- [ ] Searched existing learnings/context, and recorded usage for whatever was actually used
- [ ] Saved a context artifact carrying the whole risk object, and exactly one task
- [ ] Ran the project's mandatory checks and recorded a real verification before marking the task done
- [ ] Saved a learning only if the change actually taught something
- [ ] Told the user this demand skipped spec/design, and why

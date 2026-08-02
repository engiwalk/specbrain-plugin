---
name: specbrain-engineering
description: Use after specbrain-discovery has captured context for a demand - writes a technical spec, puts it through an adversarial gate, derives a solution design, breaks it into tasks with acceptance criteria and dependencies, and saves everything to the Specbrain shared memory. Embodies the Software Engineer persona in the Specbrain pipeline.
---

# Specbrain Engineering

## Overview

Turn a captured context into a technical spec, a solution design, and a set of isolated, acceptance-criteria-bearing tasks — with an adversarial gate between spec and design so ambiguity gets caught before implementation work is planned, not after. Embodies the Software Engineer persona in the Specbrain pipeline.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`), and a context artifact already saved for this project (normally via `specbrain-discovery`).

**Announce at start:** "Estou usando a skill specbrain-engineering para especificar e planejar esta demanda."

**Content language:** All free text persisted to the database via `save_artifact`/`save_learning` — artifact `content`, `learnings` `pattern`/`content`/`tags`, and any free-text field inside `metadata` (e.g. `acceptance_criteria`, `criteria_results[].evidence`) — must be written in English, regardless of the language the conversation is in. Proper nouns, code identifiers, and external system/API names stay exactly as given, untranslated. Everything said TO the user (questions, the announcement above, reports) stays in the user's language, unchanged.

## Process

### Step 1: Resolve the project and retrieve context

Run `pwd` to get the current project path. Call `mcp__specbrain__get_or_create_project`. Then call `mcp__specbrain__list_artifacts` with `type="context"` to find the most recent context artifact — this is the parent of everything produced in this skill. If none exists, tell the user to run `specbrain-discovery` first and stop here.

Also call `mcp__specbrain__list_artifacts` with `type="ui_design"`. If a UI design artifact exists for this project, it's additional input for Step 2. If none exists, proceed without it — not every demand involves UI, and `specbrain-design` may simply not have been run.

Then call `mcp__specbrain__list_artifacts` with `type="inquiry"`, `status="pending"`, and keep only the ones whose `parent_id` matches the context artifact found above — these are open questions `specbrain-discovery` raised for this exact demand. If any have `metadata.blocking == true`: stop here, before drafting anything, and list them for the user. Offer two outcomes:
1. **Answer now** — fold the answer into a new `context` artifact revision (`save_artifact`, `type="context"`, `parent_id` = the original context artifact, `content` describing the incremental update), mark the inquiry `answered` via `update_artifact_status`, and evaluate it against the same reusable-learning criteria `specbrain-discovery` Step 9 uses (`save_learning` if it's a durable rule). Then continue with this step.
2. **Explicit override** — proceed to Step 2 despite the open blocker. The inquiry stays `pending`.

Pending inquiries without `blocking: true` never stop this step — just note them to the user as still open, and continue.

### Step 2: Draft the spec

Write a technical specification covering: what will be built, the approach, explicit scope boundaries (what's out of scope), and acceptance criteria — in English, per the content-language policy above. If a `ui_design` artifact was found in Step 1, incorporate its component/layout/state decisions into the spec directly — don't re-derive or ignore them.

Keep this as an in-session working draft — do **not** call `mcp__specbrain__save_artifact` yet. Step 3 revises this same draft across gate attempts; exactly one version of it (the one that finally resolves) gets persisted, in Step 3, not here.

### Step 3: Adversarial gate

Dispatch a single subagent (via the `Agent` tool, `general-purpose` type, `run_in_background: true`) as the **gate runner** — its job is to drive the spec to a resolution on its own, without further input from this session until it's done. Give it the full draft text from Step 2, and these exact instructions:

1. Dispatch a fresh subagent (via its own `Agent` tool call, `general-purpose` type) as the **refuting subagent** — one per attempt, never reused across attempts, so each refutation is genuinely independent. Give it the current draft and this exact framing: its job is to **try to refute** the spec, prioritized in this order:
   1. Contradictions internal to the spec.
   2. Core edge cases of the demand that are left undefined.
   3. Unstated assumptions that would cause two different implementers to build different things.
   Style, wording, or scope suggestions that don't fall into one of these three categories are not grounds for `FAILS` — note them separately, but they never block the gate on their own. Ask for a verdict (`PASSES` or `FAILS`) with concrete issues if it fails.
2. If `PASSES`: stop the loop. Return the current draft text, verdict `PASSES`, and the attempt count.
3. If `FAILS`: revise the draft in place to address the concrete blocking issues raised (never the non-blocking notes alone). Go back to step 1 with the revised draft, incrementing the attempt count.
4. If the attempt count reaches 15 without a `PASSES`: stop the loop. Return the current draft text, verdict `SAFETY_CEILING`, the attempt count, and the concrete unresolved issues from the last attempt.

While the gate runner works, this session is free for other work — no periodic check-in interrupts it. A notification arrives when the gate runner finishes (`PASSES` or `SAFETY_CEILING`).

**On `PASSES`:** take the returned draft as the final spec text. This is the one point where the spec actually gets persisted — call `mcp__specbrain__save_artifact` with `type="spec"` and `parent_id` set to the context artifact's `id`. Call `mcp__specbrain__record_indicator` with `key="gate_pass_rate"`, `value={"passed": true, "attempts": <n>}`, `source="spec_gate"`. Proceed to Step 4.

**On `SAFETY_CEILING`:** this is a genuine circuit-breaker, not a routine pause — 15 attempts without resolving means something is genuinely stuck, not merely still working. Show the user the returned draft and the concrete unresolved issues, and ask how to proceed. Four outcomes:
1. **Run another batch** — re-dispatch a fresh gate runner (same process, same 15-attempt ceiling) starting from the returned draft. Keep a running total of attempts across batches — add this batch's returned attempt count to the total from any prior batch(es) for this same demand, so the final report (Step 7) can state the true combined figure, not just the last batch's count.
2. **User edits the draft manually** — incorporate their edit, then re-dispatch a fresh gate runner against the edited draft. Carry forward the running attempt total from outcome 1, if any prior batch already ran.
3. **User explicitly overrides** — accept the returned draft as final despite the unresolved issues.
4. **User declines to override** — the returned draft is still persisted (see below), but no design or tasks are produced for it.

For outcomes 3 and 4, persist the returned draft exactly once via `mcp__specbrain__save_artifact` (`type="spec"`, `parent_id` set to the context artifact's `id`) — the same single-persistence rule as the `PASSES` case, just with a spec that never got a clean `PASSES`. Call `mcp__specbrain__record_indicator` with `key="gate_pass_rate"`, `value={"passed": true or false, "attempts": <n>}` (`true` only for outcome 3, the override; `false` for outcome 4, the decline; `<n>` = the running total across every batch this demand went through, per outcome 1's note above), `source="spec_gate"`. For outcome 3, proceed to Step 4. For outcome 4, do NOT proceed to Step 4 or Step 5 — do not skip Step 6 or Step 7 (a genuinely declined attempt still deserves a report and may still contain a learning worth saving; the persisted spec remains in the shared memory as-is, ready for a human or a future invocation of this skill to revise).

In every case (`PASSES`, override, or decline), exactly one `spec` artifact and exactly one `gate_pass_rate` indicator are produced for this demand — never more, regardless of how many attempts or batches it took to get there.

### Step 4: Derive the design

From the persisted spec (whether it resolved via `PASSES` or an explicit user override), write the solution design (architecture, components, data flow, key decisions). Save via `mcp__specbrain__save_artifact` with `type="design"` and `parent_id` set to the spec artifact's `id`.

### Step 5: Break into tasks

Decompose the design into isolated tasks, each with explicit acceptance criteria. Describe the tasks in dependency order — a task that depends on another must be described (and saved) after the task it depends on, since `save_artifact` returns each task's `id` and a dependent task needs to reference it.

Scope each task's acceptance criteria to the minimum implementation that satisfies the spec — no speculative abstractions, no unrequested configurability, no gold-plating beyond what's actually asked. This never trims anything the spec calls for around trust-boundary validation, data-loss handling, security, or accessibility — that work stays in scope regardless of how minimal the rest of the task is.

For each task, call `mcp__specbrain__save_artifact` with `type="task"`, `parent_id` set to the design artifact's `id`, and `metadata={"task_kind": "feature", "acceptance_criteria": [...], "depends_on": [...]}` — `acceptance_criteria` lists that task's criteria; `depends_on` lists the `id`s of other tasks (from this same design) that must be done first, or `[]` if this task has no dependencies. `task_kind` is always `"feature"` for tasks created here — this is net-new work by definition; `specbrain-refine` is what later creates `bug`/`tech_debt`/`security` tasks against this same design.

### Step 6: Save new learnings

Runs regardless of how the gate resolved — including when the user declined to override. Same principle as `specbrain-discovery` Step 6: if the spec/design/gate process surfaced a reusable pattern, architectural decision, or project convention worth remembering, save it via `mcp__specbrain__save_learning`. This includes patterns surfaced by the refuting subagent even when the spec was never approved — a well-articulated gap is itself worth remembering. Skip if nothing new was learned.

### Step 7: Report

Always runs, regardless of how the gate resolved.

- If the gate resolved to PASSES or an explicit user override: tell the user the spec passed the gate (or was overridden) after N total attempts, the design and tasks (with their dependencies) are saved, and that `specbrain-orchestrate` is the next step to implement them.
- If the user declined to override after the safety ceiling: tell the user the spec remains saved but unresolved, no design or tasks were produced, and that revising the spec (either manually or by re-invoking this skill) is the next step whenever they're ready — this is a valid, deliberate stopping point, not a failure of the skill itself.

## Checklist

- [ ] Resolved the project and found the parent context artifact
- [ ] Checked for open blocking `inquiry` artifacts tied to that context, and either resolved or got an explicit override before proceeding
- [ ] Drafted the spec in English, in-session, without saving it yet
- [ ] Ran the adversarial gate as a background gate runner (prioritized criteria, no periodic check-ins), resolved to PASSES, explicit user override, or a deliberate decline after the 15-attempt safety ceiling
- [ ] Persisted exactly one `spec` artifact for this demand, regardless of how many gate attempts/batches it took
- [ ] Recorded `gate_pass_rate` exactly once for this demand
- [ ] If declined without override: reported that clearly and did not produce a design or tasks
- [ ] Derived and saved the design (only if the gate resolved to PASSES or override)
- [ ] Broke the design into tasks with `task_kind: "feature"`, acceptance criteria, and dependencies (`depends_on`), each saved in dependency order (only if the gate resolved to PASSES or override)
- [ ] Saved any new learnings (or explicitly confirmed there were none)

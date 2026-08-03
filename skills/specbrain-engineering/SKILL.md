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

Before writing anything, call `mcp__specbrain__search_learnings` with a query describing this demand (and `mcp__specbrain__search_context` too, if useful) — results are compact previews, so fetch the full content of anything relevant via `mcp__specbrain__get_learning` before using it. This costs virtually nothing (Specbrain's embeddings are a self-hosted model, not a paid API call) and often surfaces a prior scope/proportionality lesson — e.g. "don't over-specify this kind of integration's edge cases" — that can save the whole demand from needing multiple gate rounds later. Don't re-derive from scratch what's already known.

Write a technical specification covering: what will be built, the approach, explicit scope boundaries (what's out of scope), and acceptance criteria — in English, per the content-language policy above. If a `ui_design` artifact was found in Step 1, incorporate its component/layout/state decisions into the spec directly — don't re-derive or ignore them.

Keep this as an in-session working draft — do **not** call `mcp__specbrain__save_artifact` yet. Step 3 revises this same draft across gate attempts; exactly one version of it (the one that finally resolves) gets persisted, in Step 3, not here.

### Step 3: Adversarial gate

Dispatch a single subagent (via the `Agent` tool, `general-purpose` type, `run_in_background: true`) as the **gate runner** — its job is to drive the spec to a resolution on its own, without further input from this session until it's done. Give it the full draft text from Step 2, the context artifact's `id`, the `project_path` resolved in Step 1, and these exact instructions:

1. Each round, dispatch fresh subagents in parallel (via the `Agent` tool, `general-purpose` type) — never reused across rounds, so every round's judgment is genuinely independent of prior rounds' agents (though not of prior rounds' *content*, via the round log in step 3 below):
   - A **Correctness reviewer**: given the current draft, try to refute it, prioritized in this order: (1) contradictions internal to the spec, (2) core edge cases of the demand left undefined, (3) unstated assumptions that would cause two different implementers to build different things. Style/wording suggestions outside these three categories are non-blocking notes, never grounds for `FAILS` on their own.
   - A **Proportionality reviewer**: given the current draft and its own "Scope boundaries" section, judge whether the draft's level of detail anywhere exceeds what this demand actually needs — it can `FAILS` the round on its own even if the Correctness reviewer `PASSES` (e.g. the previous round's fix over-corrected). Concrete issues must name the specific passage and why it's disproportionate to the stated demand.
   - A **Security reviewer**, only when the draft involves an external tool/service, user data, authentication, or public data exposure: same `PASSES`/`FAILS` framing, focused strictly on trust-boundary/security gaps. Skip this reviewer entirely when none of those apply — don't spawn it by default.
2. Combine verdicts: the round `PASSES` only if every reviewer dispatched this round says `PASSES`. On any `FAILS`, revise the draft in place before the next round:
   - Correctness/Security issues: fix by addressing them directly, the smallest change that resolves the concrete issue.
   - Proportionality issues: fix by removing or simplifying the flagged passage, or by replacing it with an explicit line in the spec's own Scope boundaries ("explicitly not handled: X — because Y") — never by adding more detail. This preference for removal never applies to a genuine Security finding; those always get fixed by addition regardless of what Proportionality says elsewhere.
3. After every round (pass or fail), call `mcp__specbrain__save_artifact` with `project_path` from Step 1, `type="gate_round"`, `parent_id` = the previous round's `gate_round` artifact `id` (or the context artifact's `id` for this batch's first round), `content` = a short summary (each reviewer's verdict and, on a fix, what changed and why), and `metadata={"round": <n>, "verdicts": {"correctness": "PASSES"|"FAILS", "proportionality": "PASSES"|"FAILS", "security": "PASSES"|"FAILS"|null}, "resolution": "added"|"removed"|"passed"}`. Unlike the draft text itself, this is durable, embedded, and searchable — it survives across batches and is discoverable by future demands (including other users') searching for a similar scope dispute.
4. At the start of round 5 only, before dispatching that round's reviewers, compare the current draft's length to the first round's draft length (plain word/character-count arithmetic — no extra agent call). If it has grown past roughly double, stop the loop early: return the current draft, verdict `GROWTH_WARNING`, the round count so far, and the last `gate_round` artifact's `id`.
5. If `PASSES`: stop the loop. Return the current draft text, verdict `PASSES`, the attempt count, and the last `gate_round` artifact's `id`.
6. If the attempt count reaches 15 without a `PASSES`: stop the loop. Return the current draft text, verdict `SAFETY_CEILING`, the attempt count, the concrete unresolved issues from the last round, and the last `gate_round` artifact's `id`.

While the gate runner works, this session is free for other work — no periodic check-in interrupts it. A notification arrives when the gate runner finishes (`PASSES`, `GROWTH_WARNING`, or `SAFETY_CEILING`).

**On `PASSES`:** take the returned draft as the final spec text. This is the one point where the spec actually gets persisted — call `mcp__specbrain__save_artifact` with `type="spec"` and `parent_id` set to the context artifact's `id`. Call `mcp__specbrain__record_indicator` with `key="gate_pass_rate"`, `value={"passed": true, "attempts": <n>}`, `source="spec_gate"`. Proceed to Step 4.

**On `GROWTH_WARNING` or `SAFETY_CEILING`:** both are genuine circuit-breakers, not routine pauses — `GROWTH_WARNING` catches runaway scope creep early (by round 5) instead of waiting for all 15 rounds to burn; `SAFETY_CEILING` means 15 rounds never resolved it at all. Show the user the returned draft and the concrete unresolved issues (or the growth ratio, for `GROWTH_WARNING`), and ask how to proceed. Five outcomes:
1. **Run another batch** — re-dispatch a fresh gate runner starting from the returned draft, its round 1 `parent_id` set to the last `gate_round` artifact's `id` (continuing the same chain, not starting a new one). Keep a running total of attempts across batches — add this batch's returned attempt count to the total from any prior batch(es) for this same demand, so the final report (Step 7) can state the true combined figure, not just the last batch's count.
2. **User edits the draft manually** — incorporate their edit, then re-dispatch a fresh gate runner against the edited draft, same chain-continuation and running-total rules as outcome 1.
3. **Cut scope** — ask the user which specific piece of scope is driving the unresolved complexity, and whether deferring it (to a future, separately spec'd demand) is acceptable. If yes, revise the draft to explicitly exclude it (add it to Scope boundaries), then re-dispatch a fresh gate runner against the simplified draft — same chain-continuation and running-total rules as outcome 1.
4. **User explicitly overrides** — accept the returned draft as final despite the unresolved issues.
5. **User declines to override** — the returned draft is still persisted (see below), but no design or tasks are produced for it.

For outcomes 4 and 5, persist the returned draft exactly once via `mcp__specbrain__save_artifact` (`type="spec"`, `parent_id` set to the context artifact's `id`) — the same single-persistence rule as the `PASSES` case, just with a spec that never got a clean `PASSES`. Call `mcp__specbrain__record_indicator` with `key="gate_pass_rate"`, `value={"passed": true or false, "attempts": <n>}` (`true` only for outcome 4, the override; `false` for outcome 5, the decline; `<n>` = the running total across every batch this demand went through, per outcome 1's note above), `source="spec_gate"`. For outcome 4, proceed to Step 4. For outcome 5, do NOT proceed to Step 4 or Step 5 — do not skip Step 6 or Step 7 (a genuinely declined attempt still deserves a report and may still contain a learning worth saving; the persisted spec remains in the shared memory as-is, ready for a human or a future invocation of this skill to revise).

In every case (`PASSES`, override, or decline), exactly one `spec` artifact and exactly one `gate_pass_rate` indicator are produced for this demand — never more, regardless of how many attempts or batches it took to get there. The `gate_round` chain, by contrast, keeps one entry per round across every batch — it's a process trace, not a single-persistence artifact.

### Step 4: Derive the design

From the persisted spec (whether it resolved via `PASSES` or an explicit user override), write the solution design (architecture, components, data flow, key decisions). Save via `mcp__specbrain__save_artifact` with `type="design"` and `parent_id` set to the spec artifact's `id`.

### Step 5: Break into tasks

Decompose the design into isolated tasks, each with explicit acceptance criteria. Describe the tasks in dependency order — a task that depends on another must be described (and saved) after the task it depends on, since `save_artifact` returns each task's `id` and a dependent task needs to reference it.

Scope each task's acceptance criteria to the minimum implementation that satisfies the spec — no speculative abstractions, no unrequested configurability, no gold-plating beyond what's actually asked. This never trims anything the spec calls for around trust-boundary validation, data-loss handling, security, or accessibility — that work stays in scope regardless of how minimal the rest of the task is.

For each task, call `mcp__specbrain__save_artifact` with `type="task"`, `parent_id` set to the design artifact's `id`, and `metadata={"task_kind": "feature", "acceptance_criteria": [...], "depends_on": [...]}` — `acceptance_criteria` lists that task's criteria; `depends_on` lists the `id`s of other tasks (from this same design) that must be done first, or `[]` if this task has no dependencies. `task_kind` is always `"feature"` for tasks created here — this is net-new work by definition; `specbrain-refine` is what later creates `bug`/`tech_debt`/`security` tasks against this same design.

### Step 6: Save new learnings

Runs regardless of how the gate resolved — including when the user declined to override. Same principle as `specbrain-discovery` Step 6: if the spec/design/gate process surfaced a reusable pattern, architectural decision, or project convention worth remembering, save it via `mcp__specbrain__save_learning`. This includes patterns surfaced by a Correctness/Proportionality/Security reviewer even when the spec was never approved — a well-articulated gap is itself worth remembering. Skip if nothing new was learned.

### Step 7: Report

Always runs, regardless of how the gate resolved.

- If the gate resolved to PASSES or an explicit user override: tell the user the spec passed the gate (or was overridden) after N total attempts, the design and tasks (with their dependencies) are saved, and that `specbrain-orchestrate` is the next step to implement them.
- If the user declined to override after the safety ceiling: tell the user the spec remains saved but unresolved, no design or tasks were produced, and that revising the spec (either manually or by re-invoking this skill) is the next step whenever they're ready — this is a valid, deliberate stopping point, not a failure of the skill itself.

## Checklist

- [ ] Resolved the project and found the parent context artifact
- [ ] Checked for open blocking `inquiry` artifacts tied to that context, and either resolved or got an explicit override before proceeding
- [ ] Searched existing learnings/context before drafting the spec
- [ ] Drafted the spec in English, in-session, without saving it yet
- [ ] Ran the adversarial gate as a background gate runner (Correctness + Proportionality reviewers every round, Security when relevant, no periodic check-ins), persisting a `gate_round` artifact per round, resolved to PASSES, explicit user override, or a deliberate decline after a growth warning or the 15-attempt safety ceiling
- [ ] Persisted exactly one `spec` artifact for this demand, regardless of how many gate attempts/batches it took
- [ ] Recorded `gate_pass_rate` exactly once for this demand
- [ ] If declined without override: reported that clearly and did not produce a design or tasks
- [ ] Derived and saved the design (only if the gate resolved to PASSES or override)
- [ ] Broke the design into tasks with `task_kind: "feature"`, acceptance criteria, and dependencies (`depends_on`), each saved in dependency order (only if the gate resolved to PASSES or override)
- [ ] Saved any new learnings (or explicitly confirmed there were none)

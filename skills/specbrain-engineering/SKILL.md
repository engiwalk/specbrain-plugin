---
name: specbrain-engineering
description: Use after specbrain-discovery has captured context for a demand - writes a technical spec, puts it through a multi-lens review (business/security/architecture/sre/performance), derives a solution design, breaks it into tasks with acceptance criteria and dependencies, and saves everything to the Specbrain shared memory. Embodies the Software Engineer persona in the Specbrain pipeline.
---

# Specbrain Engineering

## Overview

Turn a captured context into a technical spec, a solution design, and a set of isolated, acceptance-criteria-bearing tasks — with a multi-lens review between spec and design so ambiguity gets caught before implementation work is planned, not after. Embodies the Software Engineer persona in the Specbrain pipeline.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`), and a context artifact already saved for this project (normally via `specbrain-discovery`).

**Announce at start:** tell the user you are using the `specbrain-engineering` skill to specify and plan this demand — written **in the language the user is writing in**, not translated from this file. The skill name itself is never translated.

**Content language:** All free text persisted to the database via `save_artifact`/`save_learning` — artifact `content`, `learnings` `pattern`/`content`/`tags`, and any free-text field inside `metadata` (e.g. `acceptance_criteria`, `criteria_results[].evidence`) — must be written in English, regardless of the language the conversation is in. Proper nouns, code identifiers, and external system/API names stay exactly as given, untranslated. Everything said TO the user (questions, the announcement above, reports) stays in the user's language, unchanged.

**Using and saving learnings:** every result from `search_learnings` carries `confidence` (`proposed`, `corroborated`, `confirmed`) and `source_kind` — weigh a `proposed` learning as a lead, not as a fact. After using any of them, call `mcp__specbrain__record_learning_usage` with the ids you **actually used** (not everything returned), the stage name and the demand's `artifact_id`: that trace is what later makes it possible to ask what informed work that turned out to be wrong. When saving, always pass `source_kind` and `source_ref` (commit, PR, file path, ticket — whatever the statement came from) and `origin_artifact_id`. If `save_learning` comes back with `result="conflict"`, **nothing was written**: show the candidates to the user, decide together which is true, and call `mcp__specbrain__resolve_learning_conflict` with `supersede`, `merge` or `keep_both_disputed`. Never rephrase and retry — that only puts two contradictory statements in the memory with equal authority.

## Process

### Step 1: Resolve the project and retrieve context

Run `pwd` to get the current project path. Call `mcp__specbrain__get_or_create_project`. Then call `mcp__specbrain__list_artifacts` with `type="context"` to find the most recent context artifact — this is the parent of everything produced in this skill. If none exists, tell the user to run `specbrain-discovery` first and stop here.

**Directives for this skill's stages.** This skill spans three stages, and each one loads its own steering rules at the moment it starts: `mcp__specbrain__get_directives` with `stage="engineering.spec"` before drafting in Step 2, `stage="engineering.review"` before dispatching reviewers in Step 3, and `stage="engineering.tasks"` before breaking the design down in Step 5. Pass `artifact_id` = the context artifact's `id` on every call. Every returned `instruction` is a steering rule this organization approved for that exact stage — follow each one verbatim, on top of what this skill already says. Directives are retrieved by stage, not by similarity, so they apply whether or not they resemble the demand. If `dropped_count` is greater than zero, tell the user some directives didn't fit the context budget: silently truncated steering is worse than none.

Also call `mcp__specbrain__list_artifacts` with `type="ui_design"`. If a UI design artifact exists for this project, it's additional input for Step 2. If none exists, proceed without it — not every demand involves UI, and `specbrain-design` may simply not have been run.

Then call `mcp__specbrain__list_artifacts` with `type="inquiry"`, `status="pending"`, and keep only the ones whose `parent_id` matches the context artifact found above — these are open questions `specbrain-discovery` raised for this exact demand. If any have `metadata.blocking == true`: stop here, before drafting anything, and list them for the user. Offer two outcomes:
1. **Answer now** — fold the answer into the existing context artifact with `mcp__specbrain__update_artifact` (full corrected `content`, plus a `reason` naming the question that was answered; the previous text is kept as a revision), mark the inquiry `answered` via `update_artifact_status`, and evaluate it against the same reusable-learning criteria `specbrain-discovery` Step 9 uses (`save_learning` if it's a durable rule). Then continue with this step.
2. **Explicit override** — proceed to Step 2 despite the open blocker. The inquiry stays `pending`.

Pending inquiries without `blocking: true` never stop this step — just note them to the user as still open, and continue.

### Step 2: Draft the spec

Before writing anything, call `mcp__specbrain__search_learnings` with a query describing this demand (and `mcp__specbrain__search_context` too, if useful) — results are compact previews, so fetch the full content of anything relevant via `mcp__specbrain__get_learning` before using it. This costs virtually nothing (Specbrain's embeddings are a self-hosted model, not a paid API call) and often surfaces a prior scope/proportionality lesson — e.g. "don't over-specify this kind of integration's edge cases" — that can save the whole demand from needing multiple gate rounds later. Don't re-derive from scratch what's already known.

Write a technical specification covering: what will be built, the approach, explicit scope boundaries (what's out of scope), and acceptance criteria — in English, per the content-language policy above. If a `ui_design` artifact was found in Step 1, incorporate its component/layout/state decisions into the spec directly — don't re-derive or ignore them.

Keep this as an in-session working draft — do **not** call `mcp__specbrain__save_artifact` yet. Step 3 revises this same draft across review rounds; exactly one version of it (the one that finally settles) gets persisted, in Step 3, not here.

### Step 3: Multi-lens review

Unlike a pass/fail gate, this step is advisory: specialized reviewer subagents each analyze the draft through their own lens and report grounded findings — never a verdict — and this session, together with the user for anything ambiguous, decides what's real and worth acting on. There is no background "gate runner" and no fixed round ceiling; this session dispatches reviewers itself, in the foreground, and sees every round's findings directly.

1. **Decide which lenses are relevant to this specific demand.** This is a judgment call, not a mechanical rule — never dispatch a lens "just in case." As a starting orientation:
   - `specbrain-business-reviewer` and `specbrain-architecture-reviewer`: relevant to nearly every demand.
   - `specbrain-security-reviewer`: relevant when the demand touches authentication, user data, an external tool/service, or public data exposure.
   - `specbrain-performance-reviewer`: relevant when the demand introduces new queries, meaningful data volume, or async/background processing.
   - `specbrain-sre-reviewer`: relevant when the demand introduces a new runtime component, or changes something that could fail silently in production.
2. **Dispatch the relevant reviewers directly, in parallel**, via the `Agent` tool with `agentType` set to each lens's name (e.g. `specbrain-business-reviewer`) — never `run_in_background`. Give each: the current draft, the context artifact's full `content` (the demand's real usage profile, so lenses weigh proportionality against reality instead of an imagined worst case), and the `project_path` resolved in Step 1 (every one of its `mcp__specbrain__*` calls must use this `project_path`, never its own `pwd`).
3. **Read every reviewer's findings yourself.** Each finding is tagged `grounded` (backed by a concrete `file:line` citation from the real codebase, or a concrete learning/context reference) or `ungrounded` (no such evidence). Treat an `ungrounded` finding as a hypothesis to weigh, never as an automatic action item.
4. **Decide what's real and worth acting on — always your and the user's judgment, never a lens's own verdict.** For each finding, ask: does it hold up against the actual codebase and the demand's real, stated scope? Does an existing, simpler mechanism already cover it? When it's ambiguous or contested (e.g. two lenses point in different directions), ask the user directly rather than deciding alone. Revise the draft only for findings you both judge genuinely worth addressing — the smallest change that resolves it, preferring an existing project convention over inventing a new mechanism. If a finding keeps surfacing complexity around one specific piece of scope, consider cutting that piece (move it to the spec's own Scope boundaries, to be spec'd separately later) rather than solving it in increasingly elaborate ways.

   For each finding you judge genuinely worth acting on, also decide where the correction actually belongs: if it's just this spec's own drafting (an omission, a misreading of the context, a missing detail), revise the draft only, as above. But if it reveals that the **context artifact itself** — what `specbrain-discovery` originally captured — was incomplete or wrong, and this actually changes the proposed solution, also correct the context: `mcp__specbrain__update_artifact` on the original context artifact, with the full corrected `content` and a `reason` saying what was wrong (same mechanism Step 1 already uses for resolving a blocking inquiry). This is judgment, not automatic — a finding that's merely a spec-wording fix never needs this; one that changes what the demand is actually understood to require does, so future demands searching context via `search_context` inherit the correction too, not just this one spec.
5. **Persist the round**, whether or not anything changed: call `mcp__specbrain__save_artifact` with `project_path` from Step 1, `type="gate_round"`, `parent_id` = the previous round's `gate_round` artifact `id` (or the context artifact's `id` for round 1), `content` = a short summary of each lens's findings and what was decided about them, `metadata={"round": <n>, "findings": [{"lens": "business"|"security"|"architecture"|"sre"|"performance", "severity": "critical"|"attention"|"note", "grounded": true|false, "disposition": "actioned"|"dismissed"}, ...]}`.
6. **Record indicators for this round.** For each lens dispatched this round, call `mcp__specbrain__record_indicator` with `key="review_panel_grounding_rate"`, `source="<lens name, e.g. business>"`, `value={"grounded": <n>, "ungrounded": <n>}` (counts among that lens's findings this round). Once per round (not per lens): call `mcp__specbrain__record_indicator` with `key="review_panel_summary"`, `source="multi_lens_review_spec"`, `value={"rounds": <n so far>, "findings_total": <n>, "findings_actioned": <n>, "findings_dismissed": <n>}` (cumulative across every round this demand has had so far).
7. **Decide whether another round is needed.** Default to stopping after round 1. If you run a second round, dispatch only the lenses whose domain was materially touched by a revision you just made — never re-run a lens whose area didn't change. After that second round, always stop and ask the user explicitly whether to run more, rather than deciding to continue on your own. There is no fixed ceiling here (no 15-attempt safety valve, no growth-ratio checkpoint) — the stopping condition is your and the user's shared judgment that the draft is good enough, not a round count or a mechanical threshold.

Once you (and the user, for anything that was ambiguous) consider the draft settled: this is the one point where the spec text actually gets persisted — call `mcp__specbrain__save_artifact` with `type="spec"` and `parent_id` set to the context artifact's `id`. Proceed to Step 4.

The `gate_pass_rate`/`spec_gate` indicator belonged to the old pass/fail gate design and is not recorded by this step — it remains as historical data from before this redesign, not a metric this step continues.

### Step 4: Derive the design

From the persisted, settled spec, write the solution design (architecture, components, data flow, key decisions) — it already reflects whatever Step 3's review resolved, since that step edits the spec draft directly rather than tracking decisions separately. Save via `mcp__specbrain__save_artifact` with `type="design"` and `parent_id` set to the spec artifact's `id`.

### Step 5: Break into tasks

Decompose the design into isolated tasks, each with explicit acceptance criteria. Describe the tasks in dependency order — a task that depends on another must be described (and saved) after the task it depends on, since `save_artifact` returns each task's `id` and a dependent task needs to reference it.

Scope each task's acceptance criteria to the minimum implementation that satisfies the spec — no speculative abstractions, no unrequested configurability, no gold-plating beyond what's actually asked. This never trims anything the spec calls for around trust-boundary validation, data-loss handling, security, or accessibility — that work stays in scope regardless of how minimal the rest of the task is.

For each task, call `mcp__specbrain__save_artifact` with `type="task"`, `parent_id` set to the design artifact's `id`, and `metadata={"task_kind": "feature", "acceptance_criteria": [...], "depends_on": [...]}` — `acceptance_criteria` lists that task's criteria; `depends_on` lists the `id`s of other tasks (from this same design) that must be done first, or `[]` if this task has no dependencies. `task_kind` is always `"feature"` for tasks created here — this is net-new work by definition; `specbrain-refine` is what later creates `bug`/`tech_debt`/`security` tasks against this same design.

### Step 6: Save new learnings

Runs regardless of how far the demand got. Same principle as `specbrain-discovery` Step 6: if the spec/design/review process surfaced a reusable pattern, architectural decision, or project convention worth remembering — beyond what individual reviewer lenses already saved for themselves in Step 3 — save it via `mcp__specbrain__save_learning`. This includes patterns surfaced by any lens even when a finding was ultimately dismissed as disproportionate — a well-articulated false positive is itself worth remembering, tagged so a future demand doesn't have the same lens re-raise it. Skip if nothing new was learned.

### Step 7: Report

Always runs. Tell the user: how many rounds the multi-lens review took, which lenses were dispatched and why, a summary of findings (how many were actioned vs. dismissed, and the reasoning for anything contested), whether any finding led to a context artifact revision (and why), that the spec/design/tasks are saved, and that `specbrain-orchestrate` is the next step to implement them. If the user chose to stop before the spec felt settled (e.g. to revise it manually first), say so plainly — the spec remains saved as-is, and re-invoking this skill or editing it directly are both valid next steps; this is a deliberate stopping point, not a failure of the skill.

## Checklist

- [ ] Resolved the project and found the parent context artifact
- [ ] Checked for open blocking `inquiry` artifacts tied to that context, and either resolved or got an explicit override before proceeding
- [ ] Loaded `get_directives` for `engineering.spec`, `engineering.review` and `engineering.tasks` at the start of each of those stages, and followed every returned instruction
- [ ] Searched existing learnings/context before drafting the spec
- [ ] Drafted the spec in English, in-session, without saving it yet
- [ ] Ran the multi-lens review as a foreground, judgment-driven process (not a background loop or a pass/fail gate): picked relevant lenses deliberately, read every finding's grounding, decided with the user what was worth acting on, persisted a `gate_round` artifact per round
- [ ] For any actioned finding that revealed a context gap (not just a spec-drafting issue), saved a context artifact revision alongside the spec fix
- [ ] Recorded `review_panel_grounding_rate` per lens dispatched and `review_panel_summary` once per round
- [ ] Persisted exactly one `spec` artifact for this demand, regardless of how many review rounds it took
- [ ] Derived and saved the design from the settled spec
- [ ] Broke the design into tasks with `task_kind: "feature"`, acceptance criteria, and dependencies (`depends_on`), each saved in dependency order
- [ ] Saved any new learnings beyond what individual lenses already saved (or explicitly confirmed there were none)

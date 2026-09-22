---
name: specbrain-consolidate
description: Use when the user confirms a demand actually works end to end (after specbrain-review moved its design to in_review) - marks the design finished, works the shared memory's review queue (disputed learnings, ones due for review, ones this cycle proved out), computes task-kind/defect-rate indicators for the demand, reviews all recorded indicators for process insight, and turns each actionable one into a directive proposed for the pipeline stage it should steer (pending human approval in Admin Web). Suggests specbrain-cleanup at the end, never runs it. Can be invoked by the user directly or by an agent. Embodies the Tech Lead persona in the Specbrain pipeline, closing out a cycle.
---

# Specbrain Consolidate

## Overview

Close out a demand once a human has actually confirmed it works — not just that its acceptance criteria checked out mechanically. Consolidates the project's accumulated learnings so duplicates don't crowd out the shared RAG, computes indicators about this specific demand's quality, looks back at recorded indicators for anything worth knowing about how well the process is actually working, and saves that as new learnings for future demands. Embodies the Tech Lead persona in the Specbrain pipeline.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`).

**Announce at start:** "Estou usando a skill specbrain-consolidate para encerrar esta demanda e consolidar o conhecimento."

**Content language:** same rule as every other Specbrain skill — everything persisted via `save_learning` is written in English; everything said to the user stays in their language.

## Process

### Step 1: Confirm and close the design

Run `pwd`, call `mcp__specbrain__get_or_create_project`. Call `mcp__specbrain__list_artifacts` with `type="design"`, `status="in_review"`. If none, tell the user nothing is currently awaiting confirmation and stop here. If more than one, ask which design this confirmation is for. Ask the user to confirm this demand genuinely works end to end — if they say no, stop and tell them `specbrain-refine` is how to report what's wrong instead. If they confirm: call `mcp__specbrain__update_artifact_status` on the design with `status="finished"`.

**Directives for this stage.** Call `mcp__specbrain__get_directives` with `stage="consolidate"` and `artifact_id` = the closed design's `id`, and follow every returned `instruction` verbatim for the rest of this skill. If `dropped_count` is greater than zero, say so to the user.

### Step 2: Work the memory's review queue

Near-duplicates no longer accumulate silently: `save_learning` refuses to write next to a learning it might contradict, so the work here is the queue the server already produced, not a manual scan of everything.

1. Call `mcp__specbrain__list_learnings` with `status="disputed"` — something contradicted these, and they are not being retrieved while they sit there. For each, with the user: if the correct statement is now clear, `resolve_learning_conflict` with `supersede` (or `update_learning` when only the wording was wrong); if it turned out to be true after all, say so and point the user at Admin Web, which is the only place a learning can be confirmed.
2. Call `mcp__specbrain__list_learnings` with no filter and look for entries whose `review_due_at` has passed. Same treatment: correct, supersede, retire, or leave alone with a reason.
3. Call `mcp__specbrain__list_learnings` with `confidence="proposed"` for this demand's topic. Anything this cycle independently proved out — the implementation and review confirmed it holds — gets `mcp__specbrain__corroborate_learning`. Do not corroborate something merely because it was retrieved; corroboration means it was checked.
4. If a learning is genuinely broader than the project it was saved in (it holds for the whole organization), `update_learning` with `visibility="organization"` so other projects stop rediscovering it.
5. If the queue is empty, say so and move on. Do not invent consolidation work.

Deleting is not part of this step. A learning that turned out to be wrong is disputed or superseded — the wrong statement plus its reason is evidence about how the memory fails, and deleting it throws that away. `delete_learning` is for a learning that should never have existed at all.

### Step 3: Compute this demand's task-kind and defect-rate indicators

Call `mcp__specbrain__list_artifacts` with `type="task"`, keep only the ones whose `parent_id` matches the design closed in Step 1 — this spans every task ever created for it, including any added later by `specbrain-refine` rounds, since they all share the same `parent_id`. Read each one's `metadata.task_kind` (`feature`/`bug`/`tech_debt`/`security`/`chore`).

- Call `mcp__specbrain__record_indicator` with `key="task_kind_distribution"`, `value={"feature": <n>, "bug": <n>, "tech_debt": <n>, "security": <n>, "chore": <n>}` (counts, `0` for kinds not present), `source="consolidate"`, `metadata={"design_id": "<id>"}` — the `design_id` doesn't change how it's displayed today, but keeps which demand this reading belongs to attached for whenever a per-demand breakdown is built.
- If there's at least one `feature` task: call `mcp__specbrain__record_indicator` with `key="demand_defect_rate"`, `value={"bug_count": <n>, "feature_count": <n>}`, `source="consolidate"`, `metadata={"design_id": "<id>"}` — the ratio itself (`bug_count / feature_count`) is derived by whoever reads this later (e.g. Admin Web), not computed here.

### Step 4: Re-evaluate indicators for process insight

1. Call `mcp__specbrain__list_indicators` (no `key` filter) for this project.
2. Group the results by `(key, source)` and look at how each has trended: pass rates, average attempts, token-savings trajectory, task done/failed/blocked totals, and now also `task_kind_distribution`/`demand_defect_rate` (this and prior demands), `review_miss` (recorded by `specbrain-refine` — a case where review said something was fine and it wasn't), and `refine_root_cause` (recorded by `specbrain-refine` — whether a past bug traced to a context gap, a design gap, or a pure implementation slip).
3. Reason about what the numbers actually suggest, not just what they say — e.g. a gate that has never once failed might be too lenient rather than genuinely reflecting flawless work; a high `demand_defect_rate` on a design suggests its spec/discovery was thin going in; a `refine_root_cause` history dominated by `context_gap` suggests `specbrain-discovery` needs to dig deeper before handing off, not that implementation quality is the problem. Only surface something if it's a real, non-obvious observation — with too little data, say that plainly instead of inventing an insight.
4. **An insight is only actionable if it names the stage it should steer.** For each observation, decide which pipeline stage would have to behave differently for it to stop recurring — `discovery`, `design`, `engineering.spec`, `engineering.review`, `engineering.tasks`, `orchestrate.implement`, `orchestrate.gate`, `review`, `refine`, `consolidate` or `quick`. An observation that maps to no stage is reported to the user and goes no further: it is not saved as a directive, and it is not saved as prose either. That is the rule that keeps this from silting up the way `process-insight` learnings did.

### Step 5: Propose directives for what the indicators showed

Process insight does **not** go to `save_learning`. A lesson about how the pipeline should behave, written as prose into the shared RAG, is retrieved by semantic similarity against a *demand's* text — which it never resembles, so it is never read again. Steering rules are retrieved by stage instead.

For each actionable insight from Step 4, call `mcp__specbrain__save_directive` with:
- `stage`: the stage decided in Step 4.3
- `instruction`: **one imperative sentence**, written to be injected verbatim into that stage's prompt (e.g. "Before finishing discovery, ask explicitly which currency any monetary amount is denominated in.") — not a description of the problem, an instruction for what to do
- `rationale`: what was observed and why this follows from it, for the human who will approve it
- `origin_indicator_ids`: the ids of the indicator readings the insight came from
- `scope`: only when the rule genuinely applies to a subset (`{"task_kinds": [...]}`, `{"risk_levels": [...]}`, `{"path_globs": [...]}`) — omit it otherwise
- `project_scoped`: `false` when the rule should steer every project in the organization

Every directive is saved as `proposed`. It does **not** influence anything until a human approves it in Specbrain Admin Web — say that plainly to the user rather than implying the fix is already in place.

`mcp__specbrain__save_learning` is still the right tool in this skill for genuine domain knowledge (Step 2's consolidations, or a business rule learned while closing the demand). It is no longer used for process insight.

### Step 5b: Offer to convert leftover `process-insight` learnings

If `mcp__specbrain__list_learnings` shows learnings tagged `process-insight` from before directives existed, offer to convert them — **one at a time**, never in bulk and never automatically. For each one the user accepts: agree the stage and the one-sentence instruction with them, call `save_directive`, then `delete_learning` on the original. Anything the user skips is left exactly as it is.

### Step 6: Report

Tell the user: that the design was marked `finished`; what was done with the memory's review queue (what was superseded, corroborated, retired, or left alone and why); this demand's task-kind breakdown and defect rate; and which directives were proposed, for which stages — stating explicitly that they are **pending approval in Admin Web and are not yet in effect**, and where to approve them. If the indicators didn't show anything conclusive yet, say that plainly instead of proposing a directive to have something to show. Close by telling them `specbrain-cleanup` is available whenever they've merged the integration branch (via PR or manually) — do not run it, just mention it.

## Checklist

- [ ] Found the design awaiting confirmation (or told the user none exists) and confirmed with the user before marking it `finished`
- [ ] Worked the memory's review queue: disputed learnings, anything past `review_due_at`, and proposed learnings this cycle actually proved out (corroborated only what was checked)
- [ ] Computed `task_kind_distribution` and (if applicable) `demand_defect_rate` for the closed design, spanning every task across all rounds
- [ ] Reviewed all indicators grouped by `(key, source)`, including `review_miss`/`refine_root_cause` history; kept only observations that name a stage they should steer
- [ ] Proposed those as directives via `save_directive` (one imperative sentence each, with `origin_indicator_ids`) — never as `process-insight` learnings
- [ ] Offered to convert leftover `process-insight` learnings one at a time, if any existed
- [ ] Reported the closure, consolidations, this demand's indicators, and every proposed directive — stating clearly that they're pending approval in Admin Web and not yet in effect — and pointed to `specbrain-cleanup` without running it

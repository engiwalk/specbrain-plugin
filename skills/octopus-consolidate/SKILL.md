---
name: octopus-consolidate
description: Use when the user confirms a demand actually works end to end (after octopus-homologacao moved its design to in_review) - marks the design finished, consolidates duplicate/overlapping learnings, computes task-kind/defect-rate indicators for the demand, reviews all recorded indicators for process insight, and saves what it learned back to the shared brain. Suggests octopus-cleanup at the end, never runs it. Can be invoked by the user directly or by an agent. Embodies the Tech Lead persona in the Octopus pipeline, closing out a cycle.
---

# Octopus Consolidate

## Overview

Close out a demand once a human has actually confirmed it works — not just that its acceptance criteria checked out mechanically. Consolidates the project's accumulated learnings so duplicates don't crowd out the shared RAG, computes indicators about this specific demand's quality, looks back at recorded indicators for anything worth knowing about how well the process is actually working, and saves that as new learnings for future demands. Embodies the Tech Lead persona in the Octopus pipeline.

**Requires:** the `octopus` MCP server connected (tools prefixed `mcp__octopus__`).

**Announce at start:** "Estou usando a skill octopus-consolidate para encerrar esta demanda e consolidar o conhecimento."

**Content language:** same rule as every other Octopus skill — everything persisted via `save_learning` is written in English; everything said to the user stays in their language.

## Process

### Step 1: Confirm and close the design

Run `pwd`, call `mcp__octopus__get_or_create_project`. Call `mcp__octopus__list_artifacts` with `type="design"`, `status="in_review"`. If none, tell the user nothing is currently awaiting confirmation and stop here. If more than one, ask which design this confirmation is for. Ask the user to confirm this demand genuinely works end to end — if they say no, stop and tell them `octopus-refine` is how to report what's wrong instead. If they confirm: call `mcp__octopus__update_artifact_status` on the design with `status="finished"`.

### Step 2: Consolidate learnings

1. Call `mcp__octopus__list_learnings` for this project.
2. Review the full list for near-duplicate or clearly overlapping entries (same `pattern`, or different patterns describing the same underlying rule/constraint).
3. For each such cluster: write ONE new, clearer learning via `mcp__octopus__save_learning` that captures everything useful across the cluster — **save this first**, before removing anything, so no information is ever lost mid-step. Then call `mcp__octopus__delete_learning` for each of the old, now-redundant learnings in that cluster.
4. If nothing is actually redundant, don't force a consolidation — say so and move on.

### Step 3: Compute this demand's task-kind and defect-rate indicators

Call `mcp__octopus__list_artifacts` with `type="task"`, keep only the ones whose `parent_id` matches the design closed in Step 1 — this spans every task ever created for it, including any added later by `octopus-refine` rounds, since they all share the same `parent_id`. Read each one's `metadata.task_kind` (`feature`/`bug`/`tech_debt`/`security`/`chore`).

- Call `mcp__octopus__record_indicator` with `key="task_kind_distribution"`, `value={"feature": <n>, "bug": <n>, "tech_debt": <n>, "security": <n>, "chore": <n>}` (counts, `0` for kinds not present), `source="consolidate"`, `metadata={"design_id": "<id>"}` — the `design_id` doesn't change how it's displayed today, but keeps which demand this reading belongs to attached for whenever a per-demand breakdown is built.
- If there's at least one `feature` task: call `mcp__octopus__record_indicator` with `key="demand_defect_rate"`, `value={"bug_count": <n>, "feature_count": <n>}`, `source="consolidate"`, `metadata={"design_id": "<id>"}` — the ratio itself (`bug_count / feature_count`) is derived by whoever reads this later (e.g. Admin Web), not computed here.

### Step 4: Re-evaluate indicators for process insight

1. Call `mcp__octopus__list_indicators` (no `key` filter) for this project.
2. Group the results by `(key, source)` and look at how each has trended: pass rates, average attempts, token-savings trajectory, task done/failed/blocked totals, and now also `task_kind_distribution`/`demand_defect_rate` (this and prior demands), `homologacao_miss` (recorded by `octopus-refine` — a case where review or homologação said something was fine and it wasn't), and `refine_root_cause` (recorded by `octopus-refine` — whether a past bug traced to a context gap, a design gap, or a pure implementation slip).
3. Reason about what the numbers actually suggest, not just what they say — e.g. a gate that has never once failed might be too lenient rather than genuinely reflecting flawless work; a high `demand_defect_rate` on a design suggests its spec/discovery was thin going in; a `refine_root_cause` history dominated by `context_gap` suggests `octopus-discovery` needs to dig deeper before handing off, not that implementation quality is the problem. Only surface something if it's a real, non-obvious observation — with too little data, say that plainly instead of inventing an insight.

### Step 5: Register what was learned

For each genuine insight from Step 4 (and any consolidation from Step 2 already covered that step), call `mcp__octopus__save_learning` with a short `pattern` name and `tags` including `"consolidate"` (plus `"process-insight"` for Step 4's findings) so these are identifiable later and get picked up by `octopus-discovery`'s `search_learnings` step on future demands.

### Step 6: Report

Tell the user: that the design was marked `finished`; which learnings were consolidated (old → new, and how many were removed); this demand's task-kind breakdown and defect rate; and what process insights were saved, if any — or that indicators didn't show anything conclusive yet. Close by telling them `octopus-cleanup` is available whenever they've merged the integration branch (via PR or manually) — do not run it, just mention it.

## Checklist

- [ ] Found the design awaiting confirmation (or told the user none exists) and confirmed with the user before marking it `finished`
- [ ] Reviewed all learnings for the project; consolidated any real duplicates (new learning saved before old ones deleted)
- [ ] Computed `task_kind_distribution` and (if applicable) `demand_defect_rate` for the closed design, spanning every task across all rounds
- [ ] Reviewed all indicators grouped by `(key, source)`, including `homologacao_miss`/`refine_root_cause` history; saved a genuine process insight only if one was actually there
- [ ] Reported the closure, consolidations, this demand's indicators, and any insights — and pointed to `octopus-cleanup` without running it

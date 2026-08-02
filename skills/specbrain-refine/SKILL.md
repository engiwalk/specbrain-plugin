---
name: specbrain-refine
description: Use when a human review (after specbrain-review moved a design to in_review, or even after it was already marked finished) finds a bug or identifies a worthwhile improvement - reopens the demand, gathers enough context to understand what's actually wrong, corrects the existing context/design only if they were genuinely mistaken, creates new tasks against the same design, and hands off to specbrain-orchestrate. Never starts a fresh, disconnected demand for something that's really a continuation of one already in flight. Embodies the Product Owner + Software Engineer personas in the Specbrain pipeline, re-entering an existing cycle.
---

# Specbrain Refine

## Overview

Re-enter an existing demand's cycle when review finds something wrong, instead of treating a bug or improvement as a brand-new, disconnected demand. Reuses everything already known about the demand (its `context`/`spec`/`design`/prior `task`s and learnings) and only regenerates what's actually wrong — new tasks against the existing design by default, a corrected context/design revision only when the investigation shows the mistake was there, not just in the code. Embodies the Product Owner + Software Engineer personas in the Specbrain pipeline.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`).

**Announce at start:** "Estou usando a skill specbrain-refine para retomar esta demanda."

**Content language:** same rule as every other Specbrain skill — everything persisted via `save_artifact`/`save_learning` is written in English; everything said to the user (questions, this announcement, reports) stays in their language.

## Process

### Step 1: Resolve the design being reopened

Run `pwd`, call `mcp__specbrain__get_or_create_project`. If the design is already known from the current conversation (e.g., this follows directly from a review discussion), use it. Otherwise call `mcp__specbrain__list_artifacts` with `type="design"`, `status="in_review"` or `"finished"`, and ask the user which one this report is about if more than one is a plausible match.

### Step 2: Reopen it

Call `mcp__specbrain__update_artifact_status` on the design with `status="draft"`. Record whether it was `in_review` or `finished` beforehand — this distinction matters for Step 6.

### Step 3: Understand what's actually wrong

Before asking the user anything, call `mcp__specbrain__search_context` and `mcp__specbrain__search_learnings` scoped to this demand's topic, so nothing already known gets re-asked. Both return compact previews (id + short excerpt) — fetch full content of anything relevant via `mcp__specbrain__get_artifact`/`mcp__specbrain__get_learning` before relying on it. Then ask the user clarifying questions, one at a time (same discipline as `specbrain-discovery`), until the actual behavior, the expected behavior, and why it matters are all clear. If the report needs input from someone else (a stakeholder, another engineer), `specbrain-discovery-slack` is available the same way it is during initial discovery.

### Step 4: Classify the task kind

From what was reported, decide: `bug` (an actual behavioral defect), `tech_debt` (an improvement to something that already works correctly), or `security` (a security-specific finding — treat this as its own kind rather than folding it into `bug`). This becomes `metadata.task_kind` on every task created in Step 6.

### Step 5: Decide whether context/design were actually wrong

This is the key judgment call — don't default to either answer:
- If the investigation shows the original `context` or `design` reflected a genuine misunderstanding (something was missed, assumed incorrectly, or described in a way that doesn't match reality) — this is different from "the code just didn't match a design that was actually fine." In this case: save a new `context` and/or `design` artifact revision via `mcp__specbrain__save_artifact`, with `parent_id` pointing at the artifact being corrected. This is how "updating the existing one" works in this system — there's no in-place edit; a chained revision reads as the same evolving artifact, exactly like the spec revisions `specbrain-engineering`'s gate already produces. The original is left as-is; the chain itself is what supersedes it.
- If context and design were fine and this is a pure implementation slip, skip this — new tasks in Step 6 attach to the existing design unchanged.
- Either way, call `mcp__specbrain__record_indicator` with `key="refine_root_cause"`, `value={"cause": "context_gap"|"design_gap"|"implementation_slip", "task_kind": "<from Step 4>"}`, `source="refine"`.

### Step 6: Record a review miss, if applicable

If the design was `in_review` or `finished` before Step 2 (i.e., it had already been through review once) **and** `task_kind` is `bug`: call `mcp__specbrain__record_indicator` with `key="review_miss"`, `value={"design_id": "<id>", "note": "<a short, human-readable one-sentence description of what was missed>"}`, `source="refine"`. `note` is drawn from Step 3's investigation of what was actually wrong — already gathered by this point, not a new investigation step. This is what it literally means for something to have passed review and turned out not to be fine. Skip this for `tech_debt`/`security` — an improvement or a newly-surfaced hardening need isn't a miss, it's new information.

### Step 7: Create new tasks

For each piece of work identified: call `mcp__specbrain__save_artifact` with `type="task"`, `parent_id` set to the design from Step 1 (the corrected revision from Step 5 if one was made, otherwise the original), and `metadata={"task_kind": "<from Step 4>", "acceptance_criteria": [...], "depends_on": [...]}` — same shape `specbrain-engineering` already produces.

### Step 8: Save new learnings

If the investigation itself surfaced something worth remembering beyond the root-cause classification already recorded — a business rule that was actually different from what was assumed, a constraint nobody had written down — save it via `mcp__specbrain__save_learning`. Skip if nothing new was learned here specifically.

### Step 9: Hand off

Tell the user: what was reopened and why, whether context/design were revised or left as-is (and why), the new tasks created with their `task_kind`, and that `specbrain-orchestrate` is the next step for them — not invoked automatically here. Once those tasks clear `specbrain-review`, the design naturally returns to `in_review` there, same as any other pass.

## Checklist

- [ ] Resolved which design is being reopened
- [ ] Reopened it to `draft`, noting whether it was `in_review` or `finished` beforehand
- [ ] Searched existing context/learnings before asking the user anything; asked clarifying questions one at a time
- [ ] Classified `task_kind` (`bug`/`tech_debt`/`security`)
- [ ] Judged whether context/design were genuinely wrong (not just the code) — revised via a new chained artifact only if so; recorded `refine_root_cause` either way
- [ ] Recorded `review_miss` when a `bug` task reopens a design that had already been `in_review` or `finished`
- [ ] Created new tasks with `task_kind` set, parented under the current design
- [ ] Saved any new learnings from the investigation (or explicitly confirmed there were none)
- [ ] Told the user `specbrain-orchestrate` is the next step, without invoking it

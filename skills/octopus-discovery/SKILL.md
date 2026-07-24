---
name: octopus-discovery
description: Use when starting work on a new demand/feature for a project connected to the Octopus MCP server - deepens context by searching the shared RAG before asking anything, asks clarifying questions one at a time, and saves the resulting context plus any newly learned business rules back to the shared brain. Embodies the Product Owner persona in the Octopus pipeline.
---

# Octopus Discovery

## Overview

Capture and deepen understanding of a new demand before any engineering work starts, using Octopus Engineer's shared memory (RAG) so the same business context never has to be re-explained from scratch. This skill embodies the Product Owner persona in the Octopus pipeline: discover, don't assume.

**Requires:** the `octopus` MCP server connected (tools prefixed `mcp__octopus__`). If these tools aren't available, tell the user to run `claude mcp add --transport http octopus <server-url> --scope project` before proceeding.

**Optional:** the `claude.ai Slack` MCP connector (tools prefixed `mcp__claude_ai_Slack__`), used only if the user opts in during Step 3. Unlike the `octopus` server, this is never required to run the skill.

**Announce at start:** "Estou usando a skill octopus-discovery para aprofundar o contexto desta demanda."

**Content language:** All free text persisted to the database via `save_artifact`/`save_learning` — artifact `content`, `learnings` `pattern`/`content`/`tags`, and any free-text field inside `metadata` (e.g. `acceptance_criteria`, `criteria_results[].evidence`) — must be written in English, regardless of the language the conversation is in. Proper nouns, code identifiers, and external system/API names stay exactly as given, untranslated. Everything said TO the user (questions, the announcement above, reports) stays in the user's language, unchanged.

**Slack sourcing:** Anything learned from a Slack message (Step 3) must be paraphrased into your own words before it reaches `content` in `save_artifact`/`save_learning` — never quote message text verbatim and never attribute it to a specific person or channel. That content lands in the shared, project-wide RAG, visible to anyone who later runs discovery on this project; treat Slack the way you'd treat a source you're citing in your own words, not transcribing.

## Process

### Step 1: Resolve the project

Run `pwd` to get the current project path. Call `mcp__octopus__get_or_create_project` with that path as `project_path`. This is idempotent — safe to call every time, at the start of every step that needs it.

Then call `mcp__octopus__list_artifacts` with `type="inquiry"`, `status="pending"`. These are questions raised in a previous run of this skill that couldn't be answered at the time (see Step 7) — they are never lost, only carried forward until resolved. If any exist, list them for the user (the question, which demand's context they belong to, and whether they were flagged as blocking) and ask if any now have an answer.

For each one the user answers now: call `mcp__octopus__save_artifact` with `type="context"`, `parent_id` = that inquiry's own `parent_id` (the original context artifact), and `content` describing the incremental update — this is how a demand's context "stays current" without an update-in-place tool, the same pattern `octopus-discovery-slack` uses when a Slack reply lands. Then call `mcp__octopus__update_artifact_status` on the inquiry with `status="answered"`. Evaluate the answer against the same reusable-learning criteria as Step 9 below — if it's a durable business rule, `save_learning` it now rather than waiting.

If none are answered yet, just proceed to the rest of this skill as normal — an unanswered pending inquiry never blocks starting a new demand, only `octopus-engineering` enforces that (see that skill's Step 1).

### Step 2: Search before asking

**Before asking the user anything**, call:
- `mcp__octopus__search_context` with a query describing the demand, to check whether related context already exists.
- `mcp__octopus__search_learnings` with the same query, to check whether relevant business rules or patterns are already known.

Both searches return compact previews (id + short excerpt), not full content. For any result that looks relevant, fetch its full content with `mcp__octopus__get_artifact`/`mcp__octopus__get_learning` before relying on it — the preview alone is usually too short to summarize accurately. Then **use them**: summarize what you already know back to the user and ask only about what's still unclear, instead of re-asking from scratch. This is the whole point of the shared brain — it should get faster to work with over time, not stay static.

### Step 3: Offer Slack as an additional source

Ask the user one question: do they want Slack searched for context on this demand? This is opt-in every time — never search Slack on your own initiative, even if the connector is already authenticated from a previous session.

- If declined, go straight to Step 4.
- If accepted:
  1. If `mcp__claude_ai_Slack__*` tools beyond `authenticate`/`complete_authentication` aren't available yet, tell the user to run `mcp__claude_ai_Slack__authenticate`, then complete it with `mcp__claude_ai_Slack__complete_authentication` and the callback URL, and wait until it's done before continuing.
  2. Ask a second question: which channels and/or people (DMs) should be considered — a free-text answer (e.g. `#project-x, DM with @fulano`). This is a hard scope boundary: never search outside what the user names here.
  3. Using whichever Slack tools the connector exposes, search within that scope for messages/threads relevant to the demand.
  4. Treat relevant findings the same way Step 2's RAG results are treated: summarize what was found back to the user, and use it to answer clarifying questions in Step 4 instead of re-asking what's already known. Remember the paraphrase-only rule above when this later reaches `save_artifact`/`save_learning`.

### Step 4: Ask clarifying questions, one at a time

Following the same discipline as `superpowers:brainstorming`: ask ONE question per message, prefer multiple-choice when possible, until you have enough clarity about:
- What the demand actually needs to accomplish and why.
- Who it affects.
- Any constraints (technical, business, deadline).
- Whether the demand involves a user interface (screens, layout, visual components).

Do not move to Step 5 until you're confident you understand the demand — clarity is built WITH the user, not assumed.

If the user can't answer something now (needs to check with someone, a decision hasn't been made yet, etc.), don't stall trying to force an answer out of the conversation — note the question in-session (it can't be persisted yet; it needs the context artifact's id from Step 6) and ask one follow-up: does this block the demand from moving forward, or can discovery finish and this get resolved later? Carry that `blocking` flag forward to Step 7. Keep asking about everything else the demand still needs clarified — one open question doesn't stall the rest of this step.

### Step 5: Flag UI involvement, if any

If the demand involves UI, note this explicitly for the context artifact's `metadata`: `{"requires_ui_design": true}`. This flag is what `octopus-design` checks to decide whether it applies to this demand.

### Step 6: Save the context

Call `mcp__octopus__save_artifact` with:
- `project_path`: from Step 1
- `type`: `"context"`
- `content`: a clear, complete written summary of the demand, incorporating everything learned in Steps 2-5
- `metadata`: `{"requires_ui_design": true}` or `{"requires_ui_design": false}`

### Step 7: Persist any open questions

For each question captured in Step 4 that's still unanswered, call `mcp__octopus__save_artifact` with:
- `project_path`: from Step 1
- `type`: `"inquiry"`
- `status`: `"pending"`
- `content`: the question itself, written self-contained (someone reading it later, out of context, must understand what's being asked)
- `parent_id`: the context artifact's id (from Step 6)
- `metadata`: `{"blocking": true}` or `{"blocking": false}`, per what the user decided in Step 4

If nothing was left unanswered, skip this step.

### Step 8: Offer an active interview via Slack

Ask one more question: besides what's already been searched, is there something only a specific person knows that's worth asking directly? This runs after Step 6 (not before) because it needs the just-saved context artifact's id to link to.

- If no, continue to Step 9.
- If yes, invoke the `octopus-discovery-slack` skill (Mode A) with the topic, target person/channel, the question, and `parent_id` = the context artifact saved in Step 6. That skill handles composing, approval, sending, and tracking the reply — it does not block here: it sends (or gets approval to send), persists a `pending` inquiry, schedules a re-check, and returns. Tell the user an inquiry is open and that the demand's context will be updated automatically once a reply lands (or when they check manually) — do not wait for a reply before continuing.

### Step 9: Save any newly learned business rules

Review the conversation for anything learned about the client's business that would be useful to know automatically next time — a business rule, a domain constraint, a naming convention, anything non-obvious. For each one, call `mcp__octopus__save_learning` with:
- `project_path`: from Step 1
- `pattern`: a short, searchable name for the lesson (e.g. `"refund-window-policy"`)
- `content`: the lesson itself, written so it's useful without the original conversation
- `tags`: relevant keywords for future retrieval

If nothing new was learned (the demand only used already-known context), skip this step — don't force a learning that isn't one.

### Step 10: Hand off

Tell the user the context has been saved and what's next: if `requires_ui_design` is `true`, `octopus-design` should run first to produce a `ui_design` artifact; otherwise, `octopus-engineering` is the next skill to invoke directly to turn this into a spec, design, and tasks. If any inquiry was persisted in Step 7 with `blocking: true`, say so explicitly: `octopus-engineering` will refuse to proceed on this demand until it's resolved or explicitly overridden.

## Checklist

- [ ] Resolved the project via `get_or_create_project`
- [ ] Checked for pending `inquiry` artifacts from a previous run, and folded in any answers the user now has
- [ ] Searched `search_context` and `search_learnings` before asking anything
- [ ] Offered Slack as an additional source, and if accepted, only searched the scope the user named
- [ ] Asked clarifying questions one at a time until confident; for anything left unanswered, decided with the user whether it's blocking
- [ ] Flagged whether the demand needs UI design
- [ ] Saved the context via `save_artifact`
- [ ] Persisted any open questions as `inquiry` artifacts, with the right `blocking` flag
- [ ] Asked whether a specific person should be interviewed directly (after the context was saved), and handed off to `octopus-discovery-slack` if so
- [ ] Saved any new learnings via `save_learning` (or explicitly confirmed there were none)
- [ ] Told the user, at hand-off, if any blocking inquiry remains open

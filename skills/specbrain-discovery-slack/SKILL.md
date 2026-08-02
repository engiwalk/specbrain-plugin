---
name: specbrain-discovery-slack
description: Use when a demand needs an answer only a specific stakeholder has, and specbrain-discovery's user opted into actively asking someone over Slack (not just searching history) - sends a clearly-framed question via DM or a dedicated channel thread, waits across separate invocations for a reply (never blocking one session), and folds the answer back into the demand's context once it lands. Also invoked directly by the user to open an ad hoc inquiry or check whether a pending one has been answered. Embodies the Product Owner persona's active-interview mode in the Specbrain pipeline.
---

# Specbrain Discovery via Slack

## Overview

Ask a specific person or channel a question over Slack on the user's behalf, exactly as if the user had typed it themselves — then wait for the reply, which may take hours or days, across separate invocations of this skill rather than one blocked session. Every inquiry is tracked as its own artifact so any later invocation (manual or scheduled) knows exactly what's outstanding and where to look for the answer.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`), same as `specbrain-discovery`. Also requires the `claude.ai Slack` MCP connector (tools prefixed `mcp__claude_ai_Slack__`) authenticated in the session — if it isn't, tell the user to run `mcp__claude_ai_Slack__authenticate` and complete it before proceeding.

**Announce at start:** "Estou usando a skill specbrain-discovery-slack para conversar com alguém sobre esta demanda." (Mode A) or "Estou usando a skill specbrain-discovery-slack para checar se houve resposta." (Mode B).

**Content language:** same rule as `specbrain-discovery` — everything persisted via `save_artifact`/`save_learning` is written in English; everything said to the user or sent to Slack stays in the user's language.

**Attribution:** unlike passive Slack history search (a separate, already-shipped capability in `specbrain-discovery`), a reply captured here is folded into the demand's context **with attribution** (e.g. "Fulano confirmed via Slack: ..."). The respondent knowingly answered a discovery question sent for exactly this purpose, so naming them is legitimate provenance — not a private conversation being repurposed without their knowledge.

**Thread discipline for channels:** if the target is a channel, the first message must start a new Slack **thread** whose opening text is also its title; every message after that — approval-gated sends, re-checks, anything — replies inside that same thread, never as a new top-level channel message. This is what keeps an open-ended inquiry from spamming the channel. For a DM this doesn't apply the same way, but replies still go in the existing conversation, not a fresh one.

## Which mode am I in?

- **Mode A (open a new inquiry):** invoked with a topic, target(s), and question already known — either handed off from `specbrain-discovery` Step 7, or given directly by the user.
- **Mode B (check pending inquiries):** invoked to check on outstanding inquiries — by the user directly ("acho que fulano respondeu", "confere o Slack"), or by a scheduled re-check set up in a prior Mode A run.

If it's ambiguous which mode applies, ask the user directly.

## Mode A: Open a new inquiry

### Step 1: Resolve the project

Run `pwd`, call `mcp__specbrain__get_or_create_project`. Same as `specbrain-discovery`.

### Step 2: Confirm targets, question, and re-check interval

If not already provided by the caller, ask (one question at a time, per the same discipline `specbrain-discovery` uses):
- Which people and/or channels should be asked.
- What exactly to ask each of them (may be the same question for all, or tailored per recipient).
- How long to wait before the first automatic re-check — suggest a sensible default (e.g. a few hours) and let the user override it.

### Step 3: Compose the message per recipient

Format: `[Discovery] <topic>: <question>`. The `<topic>` must be specific enough that the message is understandable completely out of context (e.g. "discovery do tema refund window", not just "discovery"). For a channel target, this text is also the opening message of the new thread it starts.

### Step 4: Get approval before the first send to each new recipient

Show the exact composed text for that recipient and get explicit approval before sending. This is a hard checkpoint — never skip it, even if the user approved the recipient list and topic in Step 2. It does not repeat for later messages to a recipient already approved within this inquiry (e.g. sending the re-check nudge doesn't need re-approval).

### Step 5: Send and persist

Using the Slack connector's send-message tool (starting a thread if the target is a channel), send the approved message. Then call `mcp__specbrain__save_artifact` once per recipient:
- `project_path`: from Step 1
- `type`: `"slack_inquiry"`
- `status`: `"pending"`
- `content`: the exact message sent
- `parent_id`: the demand's `context` artifact id (from the `specbrain-discovery` handoff, or looked up via `search_context`/`list_artifacts` if invoked standalone)
- `metadata`: `{"target": "<channel id or user id>", "target_label": "<human-readable, e.g. #proj-x or @fulano>", "asked_at": "<now, ISO>", "thread_ref": "<the thread/message id to reply into and re-read later>", "recheck_interval_minutes": <n>, "recheck_count": 0, "max_rechecks": 3}`

### Step 6: Schedule the re-check

Use this environment's own scheduling capability (a cron/scheduled-run mechanism — check what's available in this session, e.g. the `schedule`/`loop` skill or `CronCreate` tool) to re-invoke this skill in Mode B after `recheck_interval_minutes`, targeting this specific inquiry. Tell the user an inquiry is open and when the first automatic check will happen, and that they can also just tell you directly the moment they know a reply landed.

## Mode B: Check pending inquiries

### Step 1: Find what's pending

Call `mcp__specbrain__list_artifacts` with `type="slack_inquiry"`, `status="pending"` — scoped to one `parent_id` if the user named a specific demand, otherwise all of them for the project.

If there's more than one pending inquiry, dispatch one sub-agent per inquiry to do the Slack read and initial read of "was this answered" — this keeps the Slack thread contents and back-and-forth out of the main context window; only the distilled outcome (answered: yes/no, and if yes, the paraphrased-with-attribution answer) needs to come back.

### Step 2: For each inquiry, check `thread_ref` for a reply

**No reply yet:**
- Call `mcp__specbrain__update_artifact_metadata` with the same metadata plus `recheck_count` incremented by one.
- If the new `recheck_count` is still below `max_rechecks`: leave `status="pending"` and schedule another re-check after `recheck_interval_minutes`.
- If it reached `max_rechecks`: call `mcp__specbrain__update_artifact_status` with `status="stale"` and stop auto-rescheduling. Tell the user this inquiry stopped auto-checking but remains open — invoking this skill again on it (manually) re-arms checking (reset `recheck_count` to `0` via `update_artifact_metadata` and set `status="pending"` again before scheduling a fresh re-check).

**Reply landed:**
- Paraphrase the answer, with attribution (e.g. "Fulano confirmed via Slack: the refund window is 14 days for digital goods").
- Call `mcp__specbrain__save_artifact` with `type="context"`, `parent_id` = the original demand context artifact id, and `content` describing the incremental update — this is how the demand's context artifact "stays current" without an update-in-place tool; future `search_context` calls surface both the original and this revision.
- If it's a reusable business rule (same criteria `specbrain-discovery` Step 8 uses), also call `mcp__specbrain__save_learning`.
- Call `mcp__specbrain__update_artifact_status` on the `slack_inquiry` artifact with `status="answered"`.
- Tell the user what came back and that the demand's context was updated.

## Checklist

- [ ] Resolved the project via `get_or_create_project`
- [ ] (Mode A) Confirmed targets, question, and re-check interval before composing anything
- [ ] (Mode A) Got explicit approval on the exact text before the first send to each recipient
- [ ] (Mode A) Started a thread for any channel target; never posted a bare top-level follow-up
- [ ] (Mode A) Saved one `pending` `slack_inquiry` artifact per recipient, with `target`/`target_label`/`thread_ref` set
- [ ] (Mode A) Scheduled the re-check
- [ ] (Mode B) Used a sub-agent per inquiry when checking more than one
- [ ] (Mode B) Incremented `recheck_count` via `update_artifact_metadata` when no reply landed, and moved to `stale` at the cap
- [ ] (Mode B) Folded any reply into the context (with attribution) and, if applicable, a learning
- [ ] (Mode B) Updated the `slack_inquiry` artifact's status (`answered` or `stale`) accordingly

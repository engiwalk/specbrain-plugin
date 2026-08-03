---
name: specbrain-design
description: Use after specbrain-discovery flags a demand as requiring UI (context artifact metadata.requires_ui_design is true) - learns the project's design system by reading its code first, asks the user only what can't be inferred, saves reusable design-system knowledge, and produces a UI design artifact for the current demand. Embodies the Designer persona in the Specbrain pipeline.
---

# Specbrain Design

## Overview

Learn a project's design system well enough to describe how a specific screen or flow should look, without generating UI from scratch or replacing a human designer. This skill embodies the Designer persona in the Specbrain pipeline: read what already exists, ask only about genuine gaps, and get better at UI work over time by remembering what's learned.

**Requires:** the `specbrain` MCP server connected (tools prefixed `mcp__specbrain__`), and a context artifact already saved for this project (normally via `specbrain-discovery`) with `metadata.requires_ui_design == true`.

**Announce at start:** "Estou usando a skill specbrain-design para aprender o design system e desenhar esta tela."

**Content language:** All free text persisted to the database via `save_artifact`/`save_learning` — artifact `content`, `learnings` `pattern`/`content`/`tags`, and any free-text field inside `metadata` (e.g. `acceptance_criteria`, `criteria_results[].evidence`) — must be written in English, regardless of the language the conversation is in. Proper nouns, code identifiers, and external system/API names stay exactly as given, untranslated. Everything said TO the user (questions, the announcement above, reports) stays in the user's language, unchanged.

## Process

### Step 1: Resolve the project and check applicability

Run `pwd` to get the current project path. Call `mcp__specbrain__get_or_create_project`. Then call `mcp__specbrain__list_artifacts` with `type="context"` to find the most recent context artifact. If none exists, tell the user to run `specbrain-discovery` first and stop here. If it exists but `metadata.requires_ui_design` is `false`, tell the user this skill isn't needed for this demand and stop here.

### Step 2: Search existing design-system knowledge

Call `mcp__specbrain__search_learnings` with a query describing the demand's UI (the kind of screen/component involved). Results are compact previews (id + short excerpt) — fetch the full content of anything relevant with `mcp__specbrain__get_learning` before using it. Use whatever comes back as your starting point — don't re-derive from scratch what's already known.

### Step 3: Read the project's actual design system

Use `Glob`/`Grep`/`Read` to look for real evidence of an existing design system before asking anything:
- A components/UI directory (e.g., `components/`, `ui/`, `design-system/`).
- Design token or theme configuration (e.g., `tailwind.config.*`, CSS custom-property files, a theme object).
- Storybook configuration (`.storybook/`) or component documentation.
- UI library dependencies in the project's package manifest (e.g., `package.json`).

Synthesize whatever you find: naming conventions, spacing/color patterns, component composition style.

### Step 4: Ask only what's still missing

Following the same one-question-at-a-time discipline as `specbrain-discovery`: ask the user, one question per message, only about what Steps 2-3 couldn't resolve (e.g., no design tokens found at all, or the demand needs a component type the project doesn't have yet). Prefer multiple-choice when possible. If Steps 2-3 already gave you enough to proceed, skip this step entirely — don't ask questions you can already answer.

### Step 5: Save newly learned design-system knowledge

For each genuinely new fact learned in Steps 3-4 (not already covered by Step 2's search results), call `mcp__specbrain__save_learning` with:
- `project_path`: from Step 1
- `pattern`: a short, searchable name (e.g., `"design-system-button-variants"`)
- `content`: the fact itself, written so it's useful without this conversation
- `tags`: include `"design-system"` plus specific keywords

Skip if nothing new was learned (Step 2's search already had everything needed).

### Step 6: Produce the UI design for this demand

Write a description of how this specific screen/flow should look — components used, layout, states (loading/empty/error/success) — informed by the design system from Steps 2-4. Save it via `mcp__specbrain__save_artifact` with `project_path` from Step 1, `type="ui_design"`, `parent_id` set to the context artifact's `id` from Step 1.

### Step 7: Offer an optional prototype

This step is optional and must never block progression to hand-off. Every branch below — Excalidraw unavailable, the user skipping, or any failure partway through — leads straight to Step 8.

`<project_root>` in this step means the path resolved by this skill's own Step 1 `pwd` call — the demand's project, which is normally a different repo/directory than wherever the specbrain-plugin itself lives.

1. **Check availability.** Before offering anything, check whether the `mcp__claude_ai_Excalidraw__read_me` tool is currently available in the session. This is a silent check — it never prompts the user and never itself fails the flow.
2. **Offer.**
   - If available, ask the user one question: whether they'd like a quick Excalidraw prototype of this screen/flow, or to skip. Skipping is the frictionless default.
   - If not available, skip the interactive offer: tell the user in one line that connecting an Excalidraw MCP integration would enable this optional step, pointing them to their Claude client's own MCP/connector settings (setup mechanics vary by client, so don't assert one specific command). Then continue straight to Step 8.
3. **If the user skips** (or Excalidraw wasn't available): go straight to Step 8. Nothing further happens in this step.
4. **If the user opts in**, run this pipeline. Each numbered call has its own failure handling: report the failure to the user and fall through to Step 8 — never retry indefinitely, never abort the whole skill run.
   a. Call `mcp__claude_ai_Excalidraw__read_me` to learn the current elements JSON schema. On failure, report and fall through to Step 8.
   b. Author the Excalidraw elements JSON directly yourself, with labels/text written in the conversation's language — not the `ui_design` artifact's persisted English content (this skill's "Content language" rule governs only what's saved via `save_artifact`/`save_learning`, not this user-facing prototype).
      - Multi-screen flow: represent each screen as a labeled background-zone rectangle within the one file, with that screen's real elements positioned over it — not separate files.
      - Multi-state screen (loading/empty/error/success): depict only the primary/success state by default. The other states stay described in the `ui_design` artifact's text only; they aren't separately drawn here.
   c. Call `mcp__claude_ai_Excalidraw__create_view` with those elements so the prototype renders inline in the conversation. This inline render IS the "early visual feedback" this step exists to deliver, so it's mandatory once the user has opted in. On failure, report it but continue the pipeline anyway — the on-disk file below is still produced regardless of whether the inline render worked.
   d. Never call `mcp__claude_ai_Excalidraw__export_to_excalidraw`. That tool uploads the drawing to excalidraw.com and returns an unauthenticated public link — anyone with the URL can view or edit it, no login required — which would expose potentially sensitive product/business content. This constraint is permanent.
   e. Wrap the elements array in the standard `.excalidraw` file envelope (`type`, `version`, `source`, `elements`, `appState`) — `read_me` only documents the per-element schema, not this on-disk wrapper.
   f. Ensure `<project_root>/specbrain/mockups/` exists (create it if missing), then write the wrapped JSON there as a `.excalidraw` file. If a file with that name already exists, append a numeric suffix (`-2`, `-3`, ...) to keep it unique. On failure (directory creation or write), report and fall through to Step 8.
   g. Report the resulting file path to the user, plus a brief note that this is a new untracked file and that `specbrain-orchestrate` requires a clean working tree, so they may want to commit or gitignore it before running that skill.
   h. Call `mcp__specbrain__get_artifact` on the `ui_design` artifact saved in Step 6 to read its current `metadata`, then call `mcp__specbrain__update_artifact_metadata` with that existing metadata plus a new `prototype` field (`{"tool": "excalidraw", "location": "<file path>"}`) — fetch-then-merge, so this update doesn't overwrite unrelated existing metadata. On failure, report it; the file path was already delivered in (g) either way. Proceed to Step 8 regardless.

### Step 8: Hand off

Tell the user the UI design has been saved and that `specbrain-engineering` is the next step — it will read this `ui_design` artifact when writing the spec.

## Checklist

- [ ] Resolved the project, found the context artifact, confirmed `requires_ui_design` is true
- [ ] Searched existing design-system learnings before reading code or asking
- [ ] Read the project's actual code for design-system evidence before asking the user anything
- [ ] Asked only about genuine gaps, one question at a time (or asked nothing if Steps 2-3 sufficed)
- [ ] Saved any newly learned design-system facts (or explicitly confirmed there were none)
- [ ] Saved the `ui_design` artifact for this demand, parented to the context
- [ ] Offered the optional Excalidraw prototype (or skipped/unavailable, which is a valid outcome)

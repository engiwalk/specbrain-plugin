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

### Step 7: Hand off

Tell the user the UI design has been saved and that `specbrain-engineering` is the next step — it will read this `ui_design` artifact when writing the spec.

## Checklist

- [ ] Resolved the project, found the context artifact, confirmed `requires_ui_design` is true
- [ ] Searched existing design-system learnings before reading code or asking
- [ ] Read the project's actual code for design-system evidence before asking the user anything
- [ ] Asked only about genuine gaps, one question at a time (or asked nothing if Steps 2-3 sufficed)
- [ ] Saved any newly learned design-system facts (or explicitly confirmed there were none)
- [ ] Saved the `ui_design` artifact for this demand, parented to the context

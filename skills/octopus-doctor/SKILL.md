---
name: octopus-doctor
description: Use when a user reports the Octopus MCP connection isn't working, a tool call is slow/hanging/timing out (especially search_context or search_learnings), or as a quick sanity check before starting real work in a new project. Diagnoses whether the octopus MCP server is even connected, and if so, checks the database and the embedding model used by search - the embedding model is lazily loaded on first use, so a fresh server instance can make the very first search take over a minute, which otherwise looks like a hang. Does not embody a pipeline persona - it's a support/diagnostic utility.
---

# Octopus Doctor

## Overview

A quick diagnostic for the Octopus MCP connection itself, not for a demand's content. Run this first whenever something *about the tooling* seems wrong - a tool call that never returns, a fresh project that hasn't been used yet, or before reporting a bug to Octopus support.

**Announce at start:** "Estou usando a skill octopus-doctor para verificar a conexão com o Octopus."

## Process

### Step 1: Confirm the MCP tools are even available

Check whether any `mcp__octopus__*` tool (e.g. `health_check`) is available to you at all.

- **Not available:** the Octopus MCP server isn't connected in this project yet. Tell the user to connect it:
  1. Run `claude mcp add --transport http octopus https://mcp-server-domz34jjcq-uc.a.run.app/mcp`.
  2. A browser window opens automatically to sign in with Google.
  3. This only works for an account that already has a company registered at the Octopus admin panel - if sign-in is rejected, that account needs to register there first.
  Stop here - the remaining steps need the tool to exist.
- **Available:** continue to Step 2.

### Step 2: Run `health_check`

Call `health_check` with no arguments. It returns `{"company_id": ..., "checks": {"database": {...}, "embedding_model": {...}}}`, each with `ok` and `duration_ms`.

### Step 3: Interpret and report

- Both checks `ok: true` and fast (a few hundred ms or less): connection is healthy, report that plainly.
- `embedding_model` took noticeably longer (several seconds to over a minute): this is the one-time cost of loading the embedding model on a fresh server instance - explain that to the user as expected, one-time, and that the *next* `search_context`/`search_learnings` call in this session will now be fast, since `health_check` just warmed it up.
- Either check fails (tool call itself errors, not just slow): report the raw error - this is a real backend issue, not something to self-diagnose further from inside the skill.

## Checklist

- [ ] Confirmed whether Octopus MCP tools are available at all; gave connect instructions if not
- [ ] Ran `health_check` if available
- [ ] Reported plain health, or explained a slow embedding_model check as an expected one-time warm-up, or reported a real failure as-is

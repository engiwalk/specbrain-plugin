---
name: specbrain-onboarding
description: Use the first time a user in this project engages with Specbrain, when they ask "how do I get started with Specbrain" or "do I need an account," or when a Specbrain tool call fails with an authentication/access_denied error. Explains the one-time account prerequisite and what to expect from the automatic sign-in. Does not embody a pipeline persona - it's a setup/support utility.
---

# Specbrain Onboarding

## Overview

Specbrain's MCP connection is already configured by this plugin - no manual setup needed for the connection itself. The one real prerequisite is an **existing company/user registration**: the MCP server only issues access to Google accounts that have already registered a company through the Specbrain admin panel. This skill explains that, once, before the surprise of an unexpected sign-in failure.

**Announce at start:** "Estou usando a skill specbrain-onboarding para explicar o que é preciso antes de usar o Specbrain."

## Process

### Step 1: Check whether this is a fresh setup or a reported failure

- **Fresh setup / "how do I get started"**: go to Step 2.
- **A tool call just failed** (an OAuth/`access_denied` error, or a sign-in that didn't complete): go to Step 3.

### Step 2: Explain what happens next

Tell the user, plainly:
1. The first time any Specbrain skill actually calls a tool (e.g. `specbrain-discovery`), a browser window will open automatically asking them to sign in with Google.
2. This only works if that Google account already has a company registered at **https://admin-api-domz34jjcq-uc.a.run.app** — registration takes under a minute (Google sign-in + the company's CNPJ; the rest of the company's data is filled in automatically).
3. If they already have an account, they can proceed directly - no need to visit that page again.

### Step 3: Interpret a failure that already happened

If the sign-in was rejected (`access_denied`, or the browser flow closed without granting access), this means **the Google account used has no Specbrain registration** - it is not a bug and nothing else needs debugging. Point the user at https://admin-api-domz34jjcq-uc.a.run.app to register, or to whoever administers their company's Specbrain account to be invited instead.

If the account has a real registration and it's still failing, use `specbrain-doctor` instead - that's a connection/backend problem, not a missing-account one.

## Checklist

- [ ] Identified whether this is a fresh setup or an already-observed failure
- [ ] Explained the registration prerequisite and URL, or correctly interpreted an `access_denied` as "no registration yet" rather than a bug
- [ ] Pointed to `specbrain-doctor` if the account is confirmed registered but something else is wrong

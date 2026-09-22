# Specbrain

A Claude Code plugin that turns Claude into a full AI-driven engineering pipeline: discovery, spec writing, design, parallel task execution, QA, and retrospective — all backed by a shared organizational memory (context, learnings, and process indicators) that gets smarter the more your team uses it.

## Requires a Specbrain account

The skills in this plugin talk to Specbrain's MCP server, which requires an organization account. If your Google account doesn't have one yet, register your organization first at:

**https://admin.specbrain.dev**

(Google sign-in only — takes under a minute.) Once registered, the plugin's MCP connection authenticates automatically the first time you use any Specbrain skill; no separate token or setup step.

If you're not sure whether you're set up correctly, use the `specbrain-doctor` skill.

## Install

```
/plugin marketplace add engiwalk/specbrain-plugin
/plugin install specbrain@specbrain-marketplace
```

## What's included

| Skill | Role | Does |
|---|---|---|
| `specbrain-onboarding` | — | First-time setup guidance |
| `specbrain-discovery` | Product Owner | Gathers context for a new demand, searches shared memory first |
| `specbrain-discovery-slack` | Product Owner | Asks a stakeholder over Slack when only they know the answer |
| `specbrain-engineering` | Software Engineer | Spec → multi-lens review → design → tasks |
| `specbrain-design` | Designer | Learns the project's design system, produces UI designs |
| `specbrain-orchestrate` | Software Engineer | Parallel task execution with quality/security gates |
| `specbrain-review` | QA | Verifies acceptance criteria against real code/behavior |
| `specbrain-refine` | PO + Engineer | Reopens a demand to fix a bug or add an improvement |
| `specbrain-consolidate` | Tech Lead | Closes a cycle: consolidates learnings, computes indicators, proposes directives |
| `specbrain-cleanup` | Tech Lead | Removes merged worktrees/branches |
| `specbrain-doctor` | — | Diagnoses the MCP connection |

## Directives

A **directive** is a steering rule for one pipeline stage: one imperative sentence, injected verbatim into that stage's prompt every time it runs.

Directives are retrieved by **stage**, never by similarity search — that's the whole point. A lesson like "discovery keeps handing off without asking which currency an amount is in" has almost no semantic resemblance to the next demand's text, so as a searchable learning it would essentially never be read again. As a directive on `discovery`, it can't be missed.

`specbrain-consolidate` proposes directives from what the indicators actually showed, with the readings they came from attached. Every directive is saved as `proposed` and **influences nothing until a human approves it** in the Directives screen of Specbrain Admin Web — a bad instruction would otherwise degrade every future run of that stage, diffusely. Pausing an approved directive takes effect on the next call, and editing an active directive's instruction sends it back for approval, because an edited rule is a new rule.

Every skill loads the directives for its own stage right after resolving the project. `specbrain-orchestrate` loads them for `orchestrate.implement` and `orchestrate.gate` and passes them into its subagents' prompts.

## Learnings and how much they can be trusted

A **learning** is what the shared memory knows about the domain, the business or the codebase. Unlike a directive, it is retrieved by similarity — it is knowledge, not instruction.

Every learning carries where it came from (`source_kind` and `source_ref`: a commit, a PR, a file, a conversation, an incident) and how much it has earned:

| Confidence | Means |
|---|---|
| `proposed` | A model wrote it down. Treat it as a lead. |
| `corroborated` | Something independently checked out against it — usually `specbrain-review` verifying an acceptance criterion. |
| `confirmed` | A human said it is true, in Admin Web. No skill and no MCP tool can set this. |

Three rules keep the memory from quietly rotting:

- **`save_learning` refuses to write next to a statement it might contradict.** It returns the candidates instead, and the skill has to resolve it with you — supersede, merge, or mark both disputed. Noticing that two statements are close is deterministic, so the server does it; deciding whether they conflict is judgment, so you do.
- **Corrections are versioned, never destructive.** Every change keeps the previous state, with the reason.
- **`specbrain-refine` must ask whether a learning caused the defect.** If one did, it is disputed and immediately stops being retrieved. That is the only path by which the memory learns it was wrong.

Retrieval reaches this project, any project linked to it, and anything marked organization-wide — so a frontend and the API it calls can be declared one system (`link_projects`) and stop rediscovering each other's rules. Superseded, retired and disputed learnings are never returned.

`specbrain-engineering` and `specbrain-review` also dispatch five specialized reviewer agents (`agents/specbrain-{business,security,architecture,sre,performance}-reviewer.md`) — each grounds its findings in the real target codebase and the shared memory before reporting, and never issues a pass/fail verdict; only a human (with the dispatching skill) decides what's worth acting on.

## License

MIT

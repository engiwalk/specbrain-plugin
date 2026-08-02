# Specbrain

A Claude Code plugin that turns Claude into a full AI-driven engineering pipeline: discovery, spec writing, design, parallel task execution, QA, and retrospective — all backed by a shared organizational memory (context, learnings, and process indicators) that gets smarter the more your team uses it.

## Requires a Specbrain account

The skills in this plugin talk to Specbrain's MCP server, which requires an organization account. If your Google account doesn't have one yet, register your organization first at:

**https://specbrain.dev**

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
| `specbrain-engineering` | Software Engineer | Spec → adversarial gate → design → tasks |
| `specbrain-design` | Designer | Learns the project's design system, produces UI designs |
| `specbrain-orchestrate` | Software Engineer | Parallel task execution with quality/security gates |
| `specbrain-review` | QA | Verifies acceptance criteria against real code/behavior |
| `specbrain-refine` | PO + Engineer | Reopens a demand to fix a bug or add an improvement |
| `specbrain-consolidate` | Tech Lead | Closes a cycle: consolidates learnings, computes indicators |
| `specbrain-cleanup` | Tech Lead | Removes merged worktrees/branches |
| `specbrain-doctor` | — | Diagnoses the MCP connection |

## License

MIT

# Octopus Engineer

A Claude Code plugin that turns Claude into a full AI-driven engineering pipeline: discovery, spec writing, design, parallel task execution, QA, and retrospective — all backed by a shared organizational memory (context, learnings, and process indicators) that gets smarter the more your team uses it.

## Requires an Octopus Engineer account

The skills in this plugin talk to Octopus's MCP server, which requires a company account. If your Google account doesn't have one yet, register your company first at:

**https://admin-api-domz34jjcq-uc.a.run.app**

(Google sign-in + your CNPJ — takes under a minute.) Once registered, the plugin's MCP connection authenticates automatically the first time you use any Octopus skill; no separate token or setup step.

If you're not sure whether you're set up correctly, use the `octopus-doctor` skill.

## Install

```
/plugin marketplace add engiwalk/octopus-plugin
/plugin install octopus-engineer@octopus-engineer-marketplace
```

## What's included

| Skill | Role | Does |
|---|---|---|
| `octopus-onboarding` | — | First-time setup guidance |
| `octopus-discovery` | Product Owner | Gathers context for a new demand, searches shared memory first |
| `octopus-discovery-slack` | Product Owner | Asks a stakeholder over Slack when only they know the answer |
| `octopus-engineering` | Software Engineer | Spec → adversarial gate → design → tasks |
| `octopus-design` | Designer | Learns the project's design system, produces UI designs |
| `octopus-orchestrate` | Software Engineer | Parallel task execution with quality/security gates |
| `octopus-homologacao` | QA | Verifies acceptance criteria against real code/behavior |
| `octopus-refine` | PO + Engineer | Reopens a demand to fix a bug or add an improvement |
| `octopus-consolidate` | Tech Lead | Closes a cycle: consolidates learnings, computes indicators |
| `octopus-cleanup` | Tech Lead | Removes merged worktrees/branches |
| `octopus-doctor` | — | Diagnoses the MCP connection |

## License

MIT

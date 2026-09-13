---
name: gova-build
description: Translate a gova-monolith web app into a native SwiftUI iOS app. Use when the developer asks to build the iOS app, run the build workflow, or turn SEED.md's Generated Context into screens.
---

# GOVA iOS Build

The workflow is `.claude/commands/build.md`. Read that file completely, then
follow it step by step. It is the same workflow Claude Code runs as `/build`;
this file exists because Codex reaches a workflow through a skill directory and
that one is a single command file.

Nothing about the workflow is restated here. Do not act on this file alone.

## Codex specifics for the steps that name a harness

- **Dispatch.** This repo pins no custom agents, so `spawn_agent` with
  `agent_type` `worker` (implementers, fixes) or `explorer` (reviews, which read
  and do not write), plus the explicit `model` the plan's tier calls for. Naming
  a model means `fork_turns` must be `"none"` or a turn count, never the default.
- **Questions.** Codex has no batched-question tool, so ask a batch as one
  numbered list in a single message and wait for the whole set.
- **Plan mode.** `/plan`.

---
name: gova-prep
description: Gather everything SEED.md needs, populate it, and get the repo ready for the build. Use before the first iOS build, or when SEED.md's Generated Context is empty or stale.
---

# GOVA iOS Prep

The workflow is `.claude/commands/prep.md`. Read that file completely, then
follow it step by step. It is the same workflow Claude Code runs as `/prep`;
this file exists because Codex reaches a workflow through a skill directory and
that one is a single command file.

Nothing about the workflow is restated here. Do not act on this file alone.

Where it says to ask for everything in one `AskUserQuestion` call: Codex has no
such tool. Ask all of it as one numbered list in a single message, each question
with its options, and wait for the whole set.

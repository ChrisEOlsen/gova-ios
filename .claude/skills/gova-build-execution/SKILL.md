---
name: gova-build-execution
description: Use to execute a GOVA iOS implementation plan — dispatches a fresh implementer subagent per task, reviews spec compliance and code quality after each, and runs a final whole-branch review.
---

# GOVA iOS Build Execution

Fresh implementer subagent per task, a task review after each, and one broad
whole-branch review at the end.

Subagents never inherit your session's history — you construct exactly the
context each needs, which keeps them focused and preserves your own context for
coordination.

**Narrate at most one short line between tool calls.**

**Do not pause between tasks.** Execute the whole plan. Stop only for a BLOCKED
status you cannot resolve, ambiguity that genuinely prevents progress, or
completion.

## The model: parallel authoring, serial touching

Subagents **author Swift**. You own every shared resource. That split is what
makes parallelism safe without any locking.

`xcodegen generate` rewrites a single `GovaApp.xcodeproj`, and `xcodebuild`
compiles the whole target — so two implementers running either at once race for
the project file, or fail each other's builds on half-written code. The git
index is shared too. None of that is fixed by giving tasks disjoint file lists,
so nobody but you touches them.

| | Implementer | You |
|---|---|---|
| Write Swift files | its own task's list only | no |
| `xcodegen` / `xcodebuild` | never | once per batch |
| `git add` / `commit` | never | once per task |

**Form a batch** of up to 3 tasks with no dependency edge and disjoint file
lists. Dispatch them, then run `scripts/verify` once — it regenerates the
project, builds, and runs the tests. A failure names a file, and every file
belongs to exactly one task, so re-dispatch that implementer. Then commit per
task and review in parallel.

A task that rewrites `ContentView.swift`, or that needs to iterate against a
running simulator, runs **solo** — batch of one, and it may verify itself.
Batches of one are always valid.

## The loop

1. Read the plan, note its Global Constraints, create a todo per task.
2. Per task:
   - `scripts/task-brief PLAN N` → dispatch an implementer with the printed path
   - Answer any questions it asks
   - `scripts/review-package BASE HEAD` → dispatch the task reviewer with the
     printed path
   - Critical/Important findings → fix subagent → re-review
   - Clean → mark complete in the todos and the ledger
3. Final whole-branch review against the commit the branch started from. Use
   the bundled `code-review` skill if this harness has it; otherwise dispatch
   one reviewer over the whole-branch diff with the task-reviewer prompt,
   scoped to the branch rather than to one task.
4. Findings from that → ONE fix subagent with the complete list.

## Pre-flight

Before Task 1, scan the plan for tasks that contradict each other or the Global
Constraints, and for anything the plan mandates that the review rubric treats as
a defect. Present all of it as one batched question before execution begins. If
the scan is clean, proceed without comment.

## Model selection

Use the least powerful model that can do the job.

- **Mechanical** (one model struct, one straightforward View): fast model.
- **Integration or judgment** (a ViewModel coordinating several endpoints,
  navigation wiring): standard model.
- **Architecture, and the final whole-branch review**: the most capable model.

**Always name the model explicitly** — an omitted one inherits your session's,
usually the most expensive. Turn count beats token price: the cheapest models
take 2–3× the turns on multi-step Swift and cost more overall. Mid-tier is the
floor for reviewers and for any task that writes a View plus its ViewModel.

## Implementer statuses

- **DONE** → build the review package and dispatch the reviewer. BASE is the
  commit before dispatch; HEAD is the SHA the implementer reported.
- **DONE_WITH_CONCERNS** → read them. Correctness or scope concerns get
  addressed before review; observations get noted.
- **NEEDS_CONTEXT** → provide it, re-dispatch.
- **BLOCKED** → missing context (provide it), needs more reasoning (stronger
  model), too large (split it), or the plan is wrong (escalate). **Never**
  re-dispatch unchanged.

## Reviewer output

⚠️ "Cannot verify from diff" items do not block the review, but resolve each
before marking the task complete — you hold the cross-task context the reviewer
lacks. A confirmed gap is a failed spec review: send it back.

Dispatch fix subagents for Critical and Important findings; record Minor ones in
the ledger for the final review to triage. A finding that conflicts with what the
plan requires is the human's call.

## Constructing dispatch prompts

- Hand over artifacts as **files** — anything pasted stays in your context for
  the rest of the session.
- A dispatch describes one task, not the session's history.
- Copy the plan's binding requirements verbatim into `[GLOBAL_CONSTRAINTS]`.
- **Never tell a reviewer what not to flag**, and never pre-rate a severity.

## Durable progress

- At skill start: `cat "$(git rev-parse --show-toplevel)/.gova-build/progress.md"`.
  Tasks marked complete are DONE — resume at the first that is not.
- On a clean review, append
  `Task N: complete (commits <base7>..<head7>, review clean)`.
- After compaction, trust the ledger and `git log` over your own recollection.

## Templates

- [implementer-prompt.md](implementer-prompt.md)
- [task-reviewer-prompt.md](task-reviewer-prompt.md)

## Never

- Start on `main` without explicit consent
- Let an implementer run xcodegen, xcodebuild, or git (see § The model)
- Put two tasks with a dependency edge or a shared file in one batch
- Skip a task review, or accept a report missing either verdict
- Move on with unfixed Critical/Important findings
- Make a subagent read the whole plan file — hand it its brief
- Let implementer self-review replace actual review
- Re-dispatch a task the ledger already marks complete

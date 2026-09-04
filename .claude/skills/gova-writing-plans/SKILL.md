---
name: gova-writing-plans
description: Use when you have an approved GOVA iOS screen design and need an implementation plan of Swift file tasks, before writing any Swift.
---

# Writing Plans

## Overview

Write a comprehensive implementation plan assuming the engineer has zero context for this codebase. Document which Swift files each task creates, what each one is responsible for, and how to verify it. Bite-sized tasks. DRY. YAGNI. Frequent commits.

Assume they are a skilled Swift developer who knows nothing about this template. Verification is `scripts/verify` — xcodegen, build, tests — plus the per-resource UI assertions in Step 3b.

## Specify Contracts, Not Bodies

**The plan specifies what is not inferable. It does not pre-write the implementation.**

Writing the customization code into the plan and then having an implementer transcribe it means the code is generated twice — once at planning cost, once at implementation cost — and the plan balloons to several times the size of the spec it came from. That is the single largest source of slow builds in this stack. Do not do it.

**Verbatim in the plan — these are contracts the implementer cannot guess:**
- The exact model fields and their Swift types, copied from the Generated Context
- Exact file paths
- Exact names crossing a task boundary: type names, ViewModel method names, API paths, accessibility identifiers
- Exact literal values the spec fixes: user-facing copy, error codes, defaults, limits
- Any logic that is genuinely non-obvious: a security-sensitive check, a non-trivial algorithm, an ordering or concurrency requirement

**Described, not written — the implementer writes this once, at implementation time:**
- The body of a customization whose behavior follows from the interfaces above ("filter the list to `status = 'active'` before rendering", "add a delete button per row calling `del('/api/v1/projects/:id')` and re-running `loadList()` on success")
- Standard List/Form/sheet wiring — it follows the patterns in `CLAUDE.md`; describe only what differs
- Test bodies (see Step 3b) — state what the test must prove, not its source

A customization step is well-specified when a competent implementer with the task brief, the interfaces block, and `CLAUDE.md` can write exactly one reasonable implementation. If two reasonable implementations differ in a way that matters, that difference is a contract — pin it. If they differ only in style, let the implementer choose.

**Announce at start:** "I'm using the gova-writing-plans skill to create the implementation plan."

**Context:** The feature branch should already exist (created via `/build` Step 4 — `git checkout -b build/<app-name>` in the main checkout, no worktree).

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

**Input:** on the Standard path this is a committed spec under `docs/specs/`. On the Small path there is no spec file — the approved design is the conversation, and this plan is the only written artifact, so it carries the user review gate that the spec would otherwise hold. Ask the user to review the saved plan before invoking `gova-build-execution`.

## Cover the whole design

One plan covers every screen the approved design asks for. Do not split an app
across several plans, and do not quietly leave a resource for "later".

## Plan Size

The plan is a task list with contracts, not a second copy of the implementation. A single-screen plan is typically under 150 lines; a whole app, several hundred. If a plan is running several times the length of its spec, you are pre-writing implementation code — go back to "Specify Contracts, Not Bodies" and cut it. Length is a symptom, not a target: do not pad a short plan, and never drop a screen to hit a length.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for.

- Design units with clear boundaries: model files, handler files, JS modules, one per feature.
- Files that change together should live together. Split by feature, not by technical layer.
- In existing codebases, follow established patterns (`inspect_app`). If a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs how you split the work into tasks. Each task should produce self-contained changes that make sense independently.

Tasks run one at a time here (`xcodegen generate` rewrites a single project
file), so they need not be file-disjoint — but a task that touches
`ContentView.swift` should still say so, since every screen task wants to.

## Task Right-Sizing

A task is one implementer's assignment and one reviewer's gate. One resource — its model, its ViewModel and its View(s) — is usually one task.

Beyond that, size tasks by your own read of the work. There is no line count and no complexity rubric: a task ends with something verifiable — the app builds, the screen renders, the row opens its detail — and that is the only rule.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the model struct" - step
- "Verify the generated files" - step
- "Customize the generated handler/JS" - step
- "Restart the container and check logs" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use gova-build-execution to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** SwiftUI, MVVM, async/await, XcodeGen

## Global Constraints

[The project-wide requirements — auth required?, external integrations,
naming and copy rules — one line each, with exact values copied verbatim from
the spec (or, on the Small path, from the approved design in the conversation).
Every task's requirements implicitly include this section, plus the Critical
Constraints in CLAUDE.md (no raw SQL in handlers, no innerHTML with user data,
no screen an endpoint kind does not authorize).]

---
```

## Task Structure

````markdown
### Task N: [Resource or screen name]

**Files:**
- Create: `ios/GovaApp/Models/Name.swift` — Codable/Identifiable struct
- Create: `ios/GovaApp/ViewModels/NameViewModel.swift` — one async method per
  available endpoint kind, plus `isLoading` and `errorMessage`
- Create: `ios/GovaApp/Views/NameListView.swift` — [what it shows]
- Create: `ios/GovaApp/Views/NameDetailView.swift` — [only if a `detail` kind exists]
- Modify: `ios/GovaApp/ContentView.swift` — [navigation wiring]

**Endpoint kinds available for this resource:** list, detail, create, update, delete
[Copy verbatim from SEED.md's Generated Context. These authorize exactly which
screens and actions this task may build — nothing more.]

**Interfaces:**
- Consumes: [types and methods from earlier tasks, by exact name]
- Produces: [what later tasks rely on — the implementer sees only their own brief]

- [ ] **Step 1: The model**

Fields, with their Swift types and CodingKeys, copied from the Generated Context.

- [ ] **Step 2: The ViewModel**

[State it owns and one async method per available kind. Name the API paths.]

- [ ] **Step 3: The View(s)**

[What renders, which controls each `format` field needs, the accessibility
identifiers to set. Describe the behavior; the implementer writes the SwiftUI.]

- [ ] **Step 3b: UI assertion** (required for any resource with a `detail` kind)

In `ios/GovaAppUITests`, assert that tapping this resource's row opens a detail
showing its data. State which identifier or label to assert on.

- [ ] **Step 4: Verify**

Run `scripts/verify` — xcodegen, build, tests.

- [ ] **Step 5: Commit**

```bash
git add <the exact files this task created or modified>
git commit -m "feat: add Name screens"
```
````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases" — these name a category without saying which errors, which fields, or which cases
- "Similar to Task N" (restate the contract — the engineer may be reading tasks out of order, and sees only their own brief)
- A file path or type name left as a placeholder
- References to models, endpoints, or fields not present in the Generated Context

A described View body is **not** a placeholder — see "Specify Contracts, Not
Bodies". The test is whether the description pins the behavior: "a DatePicker
for `due_at`, sending `yyyy-MM-dd'T'HH:mm`" is specified; "an appropriate
control" is a placeholder.

## Remember
- Exact file paths always
- Exact file paths and type names — never abbreviated, never a placeholder
- Contracts verbatim, bodies described — the implementer writes the code once
- DRY, YAGNI, frequent commits
- Every screen traces to an endpoint kind; never design an operation the manifest does not expose
- Every resource with a `detail` kind gets a UI assertion (Step 3b)

## Self-Review

After writing the complete plan, look at the source requirements with fresh eyes and check the plan against them. This is a checklist you run yourself — not a subagent dispatch.

**1. Requirement coverage:** Skim each section/requirement in the spec (or the approved design, on the Small path). Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Naming consistency:** Do the model names, route paths, and field names you used in later tasks match what you defined in earlier tasks? A model called `Project` in Task 3 but `Projects` in Task 7 is a bug.

**4. Kind fidelity:** Does every screen and action in the plan trace to an endpoint kind in the Generated Context? Does every available kind have a screen? An invented operation and a missing one are both bugs.

**5. Contract vs body:** Scan each customization step. Is anything there a full implementation the implementer could have written from the interfaces? Cut it to the contract. Conversely, is any step's behavior open to two materially different implementations? Pin it.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a requirement with no task, add the task.

## Execution Handoff

After saving the plan:

> "Plan complete and saved to `docs/plans/<filename>.md`. Executing with gova-build-execution — fresh subagent per task, review between tasks."

On the Small path, ask for the user's review of the plan first (see **Input** above) — it is the only written artifact, so it carries the review gate.

**REQUIRED SUB-SKILL:** Use `gova-build-execution` — fresh subagent per task + review, one at a time.

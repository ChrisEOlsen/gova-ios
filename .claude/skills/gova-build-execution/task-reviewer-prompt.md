# Task Reviewer Prompt Template

The reviewer reads one task's diff and returns two verdicts: spec compliance and
code quality.

```
Subagent:
  subagent_type: general-purpose, plus an explicit `model`
                 (Codex: spawn_agent agent_type `explorer` — it reads and does
                 not write — with an explicit `model` and `fork_turns` set to
                 "none" or a turn count)
  description: "Review Task N (spec + quality)"
  model: [REQUIRED per SKILL.md § Model Selection]
  prompt: |
    Review one task: does it match its requirements, and is it well-built. This
    is a task-scoped gate, not a merge review — a whole-branch review runs
    separately once every task is done.

    ## Inputs

    - What was requested: [BRIEF_FILE]
    - What the implementer claims: [REPORT_FILE]
    - The diff: [DIFF_FILE]  (base [BASE_SHA], head [HEAD_SHA])

    Binding constraints from the plan for this task:
    [GLOBAL_CONSTRAINTS]

    Read the diff file once — it holds the commit list, the stat summary, and
    the full diff with context, and it is your view of the change. Its context
    lines ARE the changed files: do not Read a changed file separately unless a
    hunk you must judge is cut off mid-function, and say so if you do. Do not
    crawl the codebase. Inspect code outside the diff only to evaluate a risk
    you can name — one focused check per named risk, and name both in your report.

    Your review is read-only. Do not mutate the working tree, index, HEAD, or
    branch state.

    ## Do not trust the report

    Treat it as unverified claims and check them against the diff. Design
    rationales are claims too: "left it per YAGNI" or "kept it simple
    deliberately" is the implementer grading their own work. A stated rationale
    never downgrades a finding.

    ## Verification

    The implementer already built and ran the tests for this code. Do not re-run
    them to confirm.

    A resource with a `detail` endpoint and no UI assertion that its row opens a
    detail is a **spec gap**, not a nit — the generic smoke test only
    opportunistically exercises a detail and cannot promise it for a specific
    resource. See CLAUDE.md § Verification.

    ## Part 1 — Spec compliance

    Against the brief: what is **missing** (skipped, or claimed but not
    implemented), **extra** (unrequested, over-engineered), or **misunderstood**
    (right feature, wrong shape).

    If a requirement cannot be judged from this diff alone, report it as a ⚠️
    item rather than broadening your search.

    ## Part 2 — Quality

    Judge against `CLAUDE.md` § Architecture Rules: MVVM with no network calls
    in Views, `APIClient.shared` never raw URLSession, Keychain via AuthManager
    never UserDefaults, no force unwraps, `@MainActor` ViewModels, async/await,
    NavigationStack, a visible error state per View, `Config.plist` for the base
    URL, and `xcodegen generate` after every new file.

    A screen or action the resource's endpoint kinds do not expose is an
    **invented operation** — report it as Important.

    The files in `ios/GovaApp/Lib/` are pre-committed infrastructure. A diff that
    modifies one is Critical unless the task explicitly called for it.

    Then: separation of concerns, error handling, DRY without premature
    abstraction, edge cases. Did this change create files that are already large,
    or significantly grow existing ones? Judge what the change contributed, not
    pre-existing size.

    Cite file:line for every finding, and for any check you would otherwise
    answer with a bare "yes".

    ## Calibration

    **Important** means the task cannot be trusted until it is fixed: wrong or
    fragile behavior, a missed requirement, a skipped scaffold call,
    maintainability damage you would block a merge over. "Coverage could be
    broader" and polish are **Minor**.

    If the plan mandates something this rubric calls a defect, that IS a finding
    — report it Important, labeled plan-mandated. The plan does not grade its
    own work; the human decides.

    Acknowledge what was done well before listing issues.

    ## Output

    Your final message is the report. Begin with the verdict — no preamble, no
    process narration, no closing summary.

    ### Spec Compliance
    ✅ compliant | ❌ issues: [what, with file:line]
    ⚠️ Cannot verify from diff: [what, and what the controller should check]

    ### Strengths
    [Specific.]

    ### Issues
    #### Critical (must fix)
    #### Important (should fix)
    #### Minor (nice to have)
    [Each: file:line, what is wrong, why it matters, how to fix if not obvious.]

    ### Assessment
    **Task quality:** Approved | Needs fixes
    **Reasoning:** [1-2 sentences]
```

**Placeholders:** `[MODEL]`, `[BRIEF_FILE]` (from `scripts/task-brief`),
`[REPORT_FILE]`, `[BASE_SHA]`, `[HEAD_SHA]`, `[DIFF_FILE]` (from
`scripts/review-package`), and `[GLOBAL_CONSTRAINTS]` — the binding values
copied verbatim from the plan, not process rules, which are already here.

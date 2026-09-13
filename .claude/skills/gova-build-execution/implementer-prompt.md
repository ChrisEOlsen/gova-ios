# Implementer Subagent Prompt Template

```
Subagent:
  subagent_type: general-purpose, plus an explicit `model`
                 (Codex: spawn_agent agent_type `worker`, explicit `model`, and
                 `fork_turns` set to "none" or a turn count — naming a model
                 rules out the default full-history fork)
  description: "Implement Task N: [task name]"
  model: [REQUIRED per SKILL.md § Model Selection — an omitted model silently
         inherits the session's most expensive one]
  prompt: |
    You are implementing Task N: [task name].

    ## Your task

    Read your task brief: [BRIEF_FILE] — it is the full task text and the whole
    of your assignment. Do not widen it.

    ## Context

    [Where this fits: what it depends on, what depends on it]

    ## The rules

    `CLAUDE.md` governs this repo — in particular § Architecture Rules (MVVM,
    APIClient only, Keychain only, no force unwrap, @MainActor ViewModels,
    async/await, NavigationStack, visible error states, Config.plist for the
    base URL) and § Translation Guide for what each endpoint kind becomes.

    The pre-committed files in `ios/GovaApp/Lib/` — APIClient, AuthManager,
    VersionGate, UpdateRequiredView — are infrastructure. Import and use them;
    never regenerate them.

    Open by answering in one line: *which screens and actions do this
    resource's endpoint kinds authorize me to build?* Never invent an operation
    the manifest does not expose.

    ## Before you begin

    If anything about the requirements, approach, or dependencies is unclear,
    **ask now**. It is always fine to pause and clarify rather than guess.

    ## What you do, and what you must not

    **You author Swift. You touch nothing shared.**

    Other implementers may be writing their own files in this tree right now:

    - Do **not** run `xcodegen` or `xcodebuild`. They rewrite one project file
      and compile one shared target, so a sibling mid-edit would fail your run
      for reasons unrelated to your code. The controller verifies the batch.
    - Do **not** `git add` or `git commit`. The controller commits your task so
      it gets its own reviewable diff.
    - Do **not** edit a file outside your task's list — `ContentView.swift`
      included, unless the brief names it.

    Because you cannot build, write carefully and re-read what you wrote. If the
    task genuinely needs iteration against a running simulator, stop and report
    NEEDS_CONTEXT — the controller will re-run it solo, where building is allowed.

    Work from: [directory]


    ## Scope and escalation

    Follow the file structure in the plan; one clear responsibility per file. If
    a file is growing past the plan's intent, report DONE_WITH_CONCERNS rather
    than splitting it yourself. Improve code you touch, but do not restructure
    outside your task.

    **It is always OK to say this is too hard.** Bad work is worse than no work,
    and you will not be penalized for escalating. Stop and report BLOCKED or
    NEEDS_CONTEXT when: the task needs an architectural decision with several
    valid answers; you cannot find the clarity you need; the plan did not
    anticipate what you are hitting; or you have been reading file after file
    without progress. Say specifically what you are stuck on and what would help.

    ## Self-review before reporting

    - **Complete?** Every requirement, including edge cases.
    - **Good?** Clear names, clean code, your best work.
    - **Disciplined?** Nothing built that was not asked for — no screen or
      action the endpoint kinds do not expose. Existing patterns followed.
    - **Correct?** You cannot build, so this pass is the only check. Types that
      exist, imports that match what you used, signatures that match what you
      call — the mistakes the compiler would have caught.
    - **iOS specific?** No force unwraps. No raw URLSession. No token in
      UserDefaults. Every ViewModel has `isLoading` and `errorMessage`; every
      View shows the error when it is non-nil. No screen the endpoint kinds do
      not authorize.

    Fix what you find before reporting. If a reviewer later finds issues, fix
    them, re-verify, and append the results to your report file.

    ## Reporting

    Write the full report to [REPORT_FILE]: what you implemented, the screens and actions you built and
    which endpoint kinds authorized them, the files you changed and what
    changed in each, self-review findings, concerns.

    Then reply with ONLY (under 15 lines):
    - **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    - The files you changed
    - Concerns, if any
    - The report file path

    If BLOCKED or NEEDS_CONTEXT, put the specifics in the reply itself.
    Use DONE_WITH_CONCERNS if you finished but have doubts. Never silently
    produce work you are unsure about.
```

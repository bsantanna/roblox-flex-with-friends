# Development lifecycle reference

How work moves from idea to committed code in this repo.

## Contents
- [Phased plan](#phased-plan)
- [Goal-driven steps](#goal-driven-steps)
- [Branching and commits](#branching-and-commits)
- [Runtime verification](#runtime-verification)
- [Working guidelines](#working-guidelines)

## Phased plan

`doc/002_implementation_plan.md` is the roadmap. Each phase has steps with a **Build** task and a
verifiable **Verify** criterion. Summary:

- **Phase 0** — scaffolding & toolchain (done): Rojo project, Wally + ProfileStore, bootstrappers, CI.
- **Phase 1** — MVP vertical slice: data persistence → follower economy + scoreboard → Home lobby →
  travel (Airport minigame → Beach) → photo system (solo + co-op) → Personal Trainer NPC + minigame →
  friend-invite bonus → offline decay. Ends at an MVP review gate.
- **Phase 2** — real multi-place travel + the full place list with unlock gating.
- **Phase 3** — NPC roster + a reusable minigame framework + party mode.
- **Phase 4** — phone/computer/feed, moral-dilemma events, reputation depth.
- **Phase 5** — Robux/VIP/philanthropy monetization.
- **Phase 6** — anti-exploit, balancing, analytics, performance, onboarding.

Read the doc for the current phase before starting; keep it updated as phases complete (mark status,
record any plan premises that turned out wrong and how they were resolved).

## Goal-driven steps

Turn a task into a checkable goal before coding. Weak criteria ("make it work") force constant
re-clarification; strong criteria let you loop independently and know when you're done.

- "Add validation" → "write the invalid-input case, then make it pass".
- "Fix the bug" → "write a test/repro that fails, then make it pass".
- "Add a Service" → its Verify line: gated correctly, server-validated, reward credited, persists.

For multi-step work, state the plan as `step → verify` pairs and execute one at a time. The plan
doc's Verify lines are the model.

## Branching and commits

- Branch off `main` before committing (e.g. `phase-1-data-persistence`, or a task-named branch).
- **One phase-step per commit**, each independently verifiable against its Verify line.
- Don't bundle unrelated cleanup into a feature commit; every changed line should trace to the task.
- Commit messages end with the project trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Commit or push only when asked. Surface test/verify failures honestly — never report a step done
  if its Verify didn't actually pass.

## Runtime verification

A green `make build` does **not** prove code runs — Rojo packages Luau without compiling it. Layer
the checks:

1. `make analyze` — static types and unknown globals.
2. Studio runtime check — for anything that must execute. Connect via the Roblox Studio MCP and run
   the real logic with `execute_luau`, or run a Play session. Two practical notes learned on this
   repo:
   - `get_console_output` can return a **stale cached snapshot**, so don't rely on it to see your
     `print`s. Instead have the executed code **return** its evidence.
   - To verify a bootstrapped flow without polluting the open place, instantiate the real module
     source in a temp Instance, exercise it, assert on a returned trace, then destroy it.

   Example shape that proved the bootstrapper's Init-before-Start ordering:
   ```lua
   -- build two stub modules with Init/Start that append to a trace,
   -- run Bootstrap.run(container), then:
   return trace  -- expected "A-init;B-init;A-start;B-start;"
   ```
   A live Rojo-plugin Play test needs a manual "Connect" click in Studio; the MCP `execute_luau`
   check is the automatable equivalent.

## Working guidelines

This repo follows `.claude/CLAUDE.md` (Karpathy-inspired). The essence:

- **Think before coding.** State assumptions; if multiple interpretations exist, surface them
  instead of silently picking; if something's unclear, ask.
- **Simplicity first.** Minimum code that solves the problem; no speculative features, abstractions,
  or error handling for impossible cases. If 200 lines could be 50, rewrite to 50.
- **Surgical changes.** Touch only what the task needs; match existing style; don't refactor what
  isn't broken; only remove orphans *your* change created. Mention unrelated dead code, don't delete it.
- **Verify.** Define success criteria and loop until they hold.

When a plan premise turns out to be wrong mid-task (a package isn't where you expected, a tool
behaves differently), fix it with the obviously-correct engineering choice, keep moving, and record
the correction — don't silently diverge from the written plan.

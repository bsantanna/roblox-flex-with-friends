# ADR 0001 — No game framework (thin bootstrapper instead)

Status: accepted (2026-06-01) · Context: Phase 0

## Decision

Use a ~20-line `Bootstrap` (require each module, `:Init()` all, then `:Start()` all) instead of a
framework such as Knit or Flamework. Server **Services** live in `src/server/services/`, client
**Controllers** in `src/client/controllers/`; both are booted automatically.

## Why

- The two-phase `Init`-then-`Start` contract is all the ordering this game needs; cross-service
  calls are safe in `Start` because every `Init` has run.
- Frameworks add a DI container, networking sugar, and lifecycle conventions we don't need yet, plus
  a learning/maintenance surface and an upgrade treadmill.
- Simplicity-first (see `.claude/CLAUDE.md`): add abstraction only when a concrete need appears.

## Consequences

- No DI/auto-injection — modules `require` their dependencies directly. Fine at this size.
- If we later need framework features (typed networking, lifecycle hooks, component systems),
  revisit this ADR rather than bolting them on ad hoc.
- Newcomers read one small `Bootstrap.lua` instead of learning a framework.

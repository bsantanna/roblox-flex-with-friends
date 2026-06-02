# ADR 0002 — Functional core / imperative shell for headless tests

Status: accepted (2026-06-02) · Context: post-Phase-1 hardening

## Decision

Put pure domain logic in `src/shared/Logic/` (no Roblox globals) and unit-test it with **Lune** in
`make ci`. Services/controllers stay thin shells that wire the pure logic to Roblox.

## Why

- Manual Studio "Verify" steps don't catch regressions and aren't repeatable in CI — the biggest
  long-term maintainability gap.
- Lune runs Luau headlessly (no Studio) in milliseconds, but has no `game`/`Vector3`/`Enum`, so it
  can only require Roblox-free modules. Extracting pure logic makes the high-value rules testable.
- The split also clarifies the code: decisions (pure, tested) vs. side effects (thin shell).

## Consequences

- New rules-bearing logic should be added to `Logic/` with a spec, not buried in a service.
- A shell↔core type impedance can occur (e.g. `ProfileData` vs a `Logic` module's narrower type);
  cast with `:: any` at that single boundary (see `FriendInviteService`).
- UI/remotes/DataStore/SocialService still need a running place; keep that surface thin. See
  `TESTING.md`.

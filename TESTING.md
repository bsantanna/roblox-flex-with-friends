# Testing

Unit tests run **headless under [Lune](https://lune-org.github.io/docs)** — no Roblox, no Studio —
so they execute in milliseconds in `make ci` and on every PR.

```sh
make test            # runs every tests/*.spec.luau
```

## What can be tested headlessly

Lune is a standalone Luau runtime: there is **no `game`, `Vector3`, `Enum`, `Instance`**, etc. A
module that touches those at load time cannot be required under Lune. So tests target the
**functional core**: pure modules in `src/shared/Logic/` that take plain tables/numbers and return
values, with no Roblox globals.

This is the **functional core / imperative shell** pattern: domain logic is pure and tested; the
service/controller is a thin shell that wires the pure logic to Roblox (remotes, Instances,
DataStores). When a service has logic worth testing, extract it to `Logic/` and have the service
call it. Example: `FollowerService` → `Logic/Followers`, `Logic/Decay`; `FriendInviteService` →
`Logic/Referral`.

## Writing a spec

Create `tests/<Name>.spec.luau` — `run.luau` auto-discovers it:

```lua
--!strict
local framework = require("./framework")
local Followers = require("../src/shared/Logic/Followers")
local test = framework.test
local expect = framework.expect

test("deduct never goes below zero", function()
	expect(Followers.afterDeduct(30, 100)).toEqual(0)
end)
```

Note the two require styles: `./` for test files, `../src/...` for the modules under test — Lune
resolves these as file paths (unlike Roblox's instance-based `require`). The same `Logic` module is
required by Roblox services via `require(ReplicatedStorage.Shared.Logic.X)` and by specs via the
relative path; it stays portable by avoiding Roblox globals.

## Harness

`tests/framework.luau` is a ~40-line harness: `test(name, fn)`, `expect(v).toEqual/toBeTrue/toBeFalse`,
and `run()` (used by `tests/run.luau`, which exits non-zero on any failure). Intentionally tiny and
dependency-free; reach for a richer framework only if a concrete need appears.

## What still needs a running place

Lune can't exercise UI, remotes, ProximityPrompts, CaptureService, SocialService, or DataStores.
Verify those in a Studio play session (the Studio MCP `execute_luau` is the automated-ish path for
server-side checks). Keep that surface thin by pushing logic into `Logic/`.

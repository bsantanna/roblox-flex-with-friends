# Makefile / CI reference

The `Makefile` is the single entry point for builds and quality gates, locally and in CI. It is the
source of truth for the exact commands — this file explains *why* each exists and the non-obvious
bits. If a command here ever disagrees with the `Makefile`, the `Makefile` wins.

## Contents
- [Toolchain and pinning](#toolchain-and-pinning)
- [Targets](#targets)
- [PATH requirement](#path-requirement)
- [The analyze target in detail](#the-analyze-target-in-detail)
- [Configs](#configs)
- [Suggested GitHub Actions](#suggested-github-actions)

## Toolchain and pinning

Every tool is pinned in `rokit.toml` so local and CI runs are identical: `rojo`, `wally`, `StyLua`,
`selene`, `luau-lsp`. `make install` runs `rokit install` (tools) then `wally install` (deps).
Adding a tool: `rokit trust <owner>/<tool>` then `rokit add <owner>/<tool>` (Rokit gates new authors
behind a trust step; non-interactive `add` errors until trusted).

## Targets

| Target | Command(s) | Purpose |
|---|---|---|
| `help` | grep/awk over the Makefile | Default goal; lists targets from their `## ` comments. |
| `install` | `rokit install` + `wally install` | Provision pinned tools and dependencies. |
| `fmt` | `stylua src` | Auto-format in place. Run before committing. |
| `fmt-check` | `stylua --check src` | Formatting gate (no writes). |
| `lint` | `selene src` | Lint with the Roblox standard library. |
| `sourcemap` | `rojo sourcemap` | Generate `sourcemap.json` (input to analyze). |
| `defs` | `curl` pinned defs | Download Roblox type definitions if missing. |
| `analyze` | `luau-lsp analyze ...` | Static type-check. Depends on `sourcemap` + `defs`. |
| `build` | `rojo build -o build.rbxl` | Produce the place file. |
| `serve` | `rojo serve` | Live-sync to Studio during development. |
| `ci` | `fmt-check lint analyze build` | Full gate. Run before every commit/PR. |
| `clean` | `rm -f` artifacts | Remove `build.rbxl`, `sourcemap.json`, defs, etc. |

`sourcemap.json`, `globalTypes.d.luau`, `build.rbxl`, and editor `.vscode/` are generated and
git-ignored. `wally.lock` is **committed** (a `!wally.lock` negation overrides the `*.lock` ignore)
for reproducible installs.

## PATH requirement

The Makefile does **not** munge `PATH`. It relies on the Rokit bin dir (`~/.rokit/bin`) already
being on `PATH` — the Rokit installer adds it locally, and a `setup-rokit` action does it in CI.

Why not just export it in the Makefile? GNU Make 3.81 (macOS default) execs simple, single-command
recipe lines **directly via `execvp`, bypassing the shell**, and that direct exec ignores a
makefile-level `export PATH := ...`. So `stylua` would be "not found" despite the export. Recipes
with shell metacharacters go through `/bin/sh` and would see it — which is why the failure looks
inconsistent. Relying on the environment `PATH` (the conventional approach) sidesteps the quirk
entirely.

## The analyze target in detail

`luau-lsp analyze` needs three things beyond the source:

1. `--sourcemap=sourcemap.json` — from `rojo sourcemap`, so the analyzer understands the DataModel.
2. `--definitions=globalTypes.d.luau` — Roblox global type defs, fetched from the project's
   luau-lsp fork (`DEFS_URL` in the Makefile) — the `None` security variant, because game scripts
   run at "None" security and higher-security defs would falsely allow APIs that don't exist at
   runtime.
3. `--base-luaurc=.luaurc` — base language config (strict mode).

`--ignore="**/ServerPackages/**"` and `**/Packages/**` suppress diagnostics from third-party Wally
packages once `src/` starts requiring them.

**Dynamic-require gotcha:** analyze reports `Unknown require: unsupported path` on
`require(instanceVariable)`. That's expected for a generic loader. Cast it: `(require :: any)(child)`
(as in `Bootstrap.lua`). Keep static requires statically typed so analyze still checks them.

## Configs

- `selene.toml` — `std = "roblox"` (Selene 0.31+ bundles the Roblox std; no generated file needed).
- `.luaurc` — `languageMode: strict`, used by both `make analyze` and editors/luau-lsp.
- StyLua runs with defaults; the existing `src/` is already conformant.

## Suggested GitHub Actions

A CI workflow should mirror local CI exactly:

```yaml
# .github/workflows/ci.yml
on: [push, pull_request]
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: CompeyDev/setup-rokit@v0   # puts ~/.rokit/bin on PATH
      - run: make install
      - run: make ci
```

The point of routing everything through `make` is that "what CI runs" and "what I run" are the same
command — no drift between local and remote.

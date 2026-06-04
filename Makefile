# Makefile — CI tasks for the Flex-with-Friends Roblox project.
# The toolchain is pinned in rokit.toml; `make install` provisions it.
# Requires the Rokit bin dir (~/.rokit/bin) on PATH — added by the Rokit
# installer locally, and by setup-rokit in CI.

PROJECT   := default.project.json
BUILD     := build.rbxl
SOURCEMAP := sourcemap.json
DEFS      := globalTypes.d.luau

# Roblox type definitions for luau-lsp, fetched from the project's fork.
# The `None` security variant matches the security context of in-game scripts.
DEFS_URL := https://raw.githubusercontent.com/bsantanna/luau-lsp/main/scripts/globalTypes.None.d.luau

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Install pinned toolchain (Rokit) and dependencies (Wally)
	rokit install
	wally install

.PHONY: fmt
fmt: ## Format Luau sources in place (StyLua)
	stylua src

.PHONY: fmt-check
fmt-check: ## Check Luau formatting without writing (StyLua)
	stylua --check src

.PHONY: lint
lint: ## Lint Luau sources (Selene)
	selene src

.PHONY: sourcemap
sourcemap: ## Generate the Rojo instance sourcemap
	rojo sourcemap $(PROJECT) -o $(SOURCEMAP)

$(DEFS):
	curl -fsSL $(DEFS_URL) -o $(DEFS)

.PHONY: defs
defs: $(DEFS) ## Download pinned Roblox type definitions if missing

.PHONY: analyze
analyze: sourcemap $(DEFS) ## Type-check Luau sources (luau-lsp)
	luau-lsp analyze \
		--sourcemap=$(SOURCEMAP) \
		--definitions=$(DEFS) \
		--base-luaurc=.luaurc \
		--ignore="**/ServerPackages/**" \
		--ignore="**/Packages/**" \
		src

.PHONY: test
test: ## Run unit tests (Lune, headless — pure Logic modules)
	lune run tests/run.luau

.PHONY: assets-upload
assets-upload: ## Upload pending mesh assets (GLB, or OBJ auto-converted) via Open Cloud (see assets/PIPELINE.md). ARGS=--force re-uploads all
	lune run tools/upload-assets.luau $(ARGS)

.PHONY: build
build: ## Build the place file
	rojo build $(PROJECT) -o $(BUILD)

.PHONY: serve
serve: ## Start the Rojo live-sync server (development)
	rojo serve $(PROJECT)

.PHONY: ci
ci: fmt-check lint analyze test build ## Run the full CI pipeline

.PHONY: clean
clean: ## Remove generated build artifacts
	rm -f $(BUILD) build.rbxlx $(SOURCEMAP) $(DEFS)

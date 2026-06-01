# Makefile — CI tasks for the Flex-with-Friends Roblox project.
# The toolchain is pinned in rokit.toml; `make install` provisions it.
# Requires the Rokit bin dir (~/.rokit/bin) on PATH — added by the Rokit
# installer locally, and by setup-rokit in CI.

PROJECT   := default.project.json
BUILD     := build.rbxl
SOURCEMAP := sourcemap.json
DEFS      := globalTypes.d.luau

# Roblox type definitions for luau-lsp, pinned to the installed luau-lsp
# version. Keep LUAU_LSP_VERSION in sync with the luau-lsp pin in rokit.toml.
LUAU_LSP_VERSION := 1.68.0
DEFS_URL := https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$(LUAU_LSP_VERSION)/scripts/globalTypes.None.d.luau

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

.PHONY: build
build: ## Build the place file
	rojo build $(PROJECT) -o $(BUILD)

.PHONY: serve
serve: ## Start the Rojo live-sync server (development)
	rojo serve $(PROJECT)

.PHONY: ci
ci: fmt-check lint analyze build ## Run the full CI pipeline

.PHONY: clean
clean: ## Remove generated build artifacts
	rm -f $(BUILD) build.rbxlx $(SOURCEMAP) $(DEFS)

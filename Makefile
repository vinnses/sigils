SHELL := /bin/bash
.DEFAULT_GOAL := help

SPELLS_DIR := spells
ROOT_BIN := bin

.PHONY: help
help:
	@echo "Sigils spells workspace"
	@echo "Usage: make <target>"
	@echo "  link | unlink | list | executable | new SPELL=<name>"
	@echo "  test | check | fmt | clean"

.PHONY: link
link:
	@mkdir -p "$(ROOT_BIN)"
	@shopt -s nullglob; \
	for cmd in $(SPELLS_DIR)/*/bin/*; do \
		if [ -f "$$cmd" ] && [ -x "$$cmd" ]; then \
			name="$$(basename "$$cmd")"; \
			rel_target="../$$cmd"; \
			if [ -L "$(ROOT_BIN)/$$name" ] && [ "$$(readlink "$(ROOT_BIN)/$$name")" = "$$rel_target" ]; then \
				:; \
			else \
				ln -sfn "$$rel_target" "$(ROOT_BIN)/$$name"; \
			fi; \
		fi; \
	done

.PHONY: unlink
unlink:
	@mkdir -p "$(ROOT_BIN)"
	@for f in $(ROOT_BIN)/*; do [ -L "$$f" ] && rm -f "$$f" || true; done

.PHONY: list
list:
	@shopt -s nullglob; \
	for spell_dir in $(SPELLS_DIR)/*; do \
		[ -d "$$spell_dir" ] || continue; \
		spell="$$(basename "$$spell_dir")"; \
		entries=(); \
		for cmd in "$$spell_dir"/bin/*; do [ -f "$$cmd" ] && entries+=("$$(basename "$$cmd")"); done; \
		if [ $${#entries[@]} -eq 0 ]; then echo "$$spell: (no entrypoints)"; else echo "$$spell: $${entries[*]}"; fi; \
	done

.PHONY: executable
executable:
	@shopt -s nullglob; for cmd in $(SPELLS_DIR)/*/bin/*; do [ -f "$$cmd" ] && chmod +x "$$cmd"; done

.PHONY: new
new:
	@if [ -z "$(SPELL)" ]; then echo "ERROR: use make new SPELL=<name>"; exit 1; fi
	@mkdir -p "$(SPELLS_DIR)/$(SPELL)"/{bin,lib,tests,docs,config,data,logs,completions/bash,completions/zsh,completions/fish,services/systemd/user,services/systemd/system,desktop}
	@touch "$(SPELLS_DIR)/$(SPELL)/data/.gitkeep" "$(SPELLS_DIR)/$(SPELL)/logs/.gitkeep" \
		"$(SPELLS_DIR)/$(SPELL)/completions/zsh/.gitkeep" "$(SPELLS_DIR)/$(SPELL)/completions/fish/.gitkeep" \
		"$(SPELLS_DIR)/$(SPELL)/desktop/.gitkeep"
	@[ -f "$(SPELLS_DIR)/$(SPELL)/README.md" ] || printf '# %s\n\nSpell scaffold for actions, binaries, configs, docs, tests, services, and completions.\n' "$(SPELL)" > "$(SPELLS_DIR)/$(SPELL)/README.md"
	@[ -f "$(SPELLS_DIR)/$(SPELL)/Makefile" ] || printf '.PHONY: test check fmt clean\n\ntest:\n\t@echo "[skip] no spell-local tests configured"\n\ncheck:\n\t@echo "[skip] no spell-local checks configured"\n\nfmt:\n\t@echo "[skip] no spell-local formatting configured"\n\nclean:\n\t@echo "[skip] no spell-local cleanup configured"\n' > "$(SPELLS_DIR)/$(SPELL)/Makefile"
	@$(MAKE) link

.PHONY: test check fmt clean
test check fmt clean:
	@target="$@"; \
	for spell_dir in $(SPELLS_DIR)/*; do \
		[ -d "$$spell_dir" ] || continue; \
		if [ -f "$$spell_dir/Makefile" ]; then \
			if rg -n "^$$target:" "$$spell_dir/Makefile" >/dev/null; then \
				echo "--> $$target: $$(basename "$$spell_dir")"; \
				$(MAKE) -C "$$spell_dir" "$$target"; \
			else \
				echo "[warn] $$spell_dir does not implement target '$$target', skipping"; \
			fi; \
		else \
			echo "[warn] $$spell_dir has no Makefile, skipping"; \
		fi; \
	done

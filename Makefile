SHELL := /bin/bash
.DEFAULT_GOAL := help

SPELLS_DIR := spells
ROOT_BIN := bin
SPELL_HELPERS := lib/common/spells.bash

.PHONY: help
help:
	@echo "Sigils spells workspace"
	@echo "Usage: make <target>"
	@echo "  link | unlink | list | executable | new SPELL=<name>"
	@echo "  install | install-dev | test | check | fmt | clean [SPELL=<name>]"

.PHONY: link
link:
	@mkdir -p "$(ROOT_BIN)"
	@find "$(ROOT_BIN)" -mindepth 1 -maxdepth 1 -type l -delete
	@source "$(SPELL_HELPERS)"; \
	while IFS=$$'\t' read -r spell spell_dir; do \
		for cmd in "$$spell_dir"/bin/*; do \
			if [ -f "$$cmd" ] && [ -x "$$cmd" ]; then \
				name="$$(basename "$$cmd")"; \
				rel_target="../$${cmd#$(CURDIR)/}"; \
				ln -sfn "$$rel_target" "$(ROOT_BIN)/$$name"; \
			fi; \
		done; \
	done < <(sigils_iter_enabled_spells)

.PHONY: unlink
unlink:
	@mkdir -p "$(ROOT_BIN)"
	@find "$(ROOT_BIN)" -mindepth 1 -maxdepth 1 -type l -delete

.PHONY: list
list:
	@source "$(SPELL_HELPERS)"; \
	while IFS=$$'\t' read -r spell status spell_dir; do \
		entries=(); \
		for cmd in "$$spell_dir"/bin/*; do [ -f "$$cmd" ] && entries+=("$$(basename "$$cmd")"); done; \
		if [ $${#entries[@]} -eq 0 ]; then \
			echo "$$status $$spell: (no entrypoints)"; \
		else \
			echo "$$status $$spell: $${entries[*]}"; \
		fi; \
	done < <(sigils_iter_spells)

.PHONY: executable
executable:
	@shopt -s nullglob; for cmd in $(SPELLS_DIR)/*/bin/*; do [ -f "$$cmd" ] && chmod +x "$$cmd"; done

.PHONY: new
new:
	@if [ -z "$(SPELL)" ]; then echo "ERROR: use make new SPELL=<name>"; exit 1; fi
	@mkdir -p "$(SPELLS_DIR)/$(SPELL)"/{bin,lib,tests,docs,config,data,logs,inits/bash,inits/zsh,inits/fish,completions/bash,completions/zsh,completions/fish,services/systemd/user,services/systemd/system,desktop}
	@touch "$(SPELLS_DIR)/$(SPELL)/data/.gitkeep" "$(SPELLS_DIR)/$(SPELL)/logs/.gitkeep" \
		"$(SPELLS_DIR)/$(SPELL)/inits/zsh/.gitkeep" "$(SPELLS_DIR)/$(SPELL)/inits/fish/.gitkeep" \
		"$(SPELLS_DIR)/$(SPELL)/completions/zsh/.gitkeep" "$(SPELLS_DIR)/$(SPELL)/completions/fish/.gitkeep" \
		"$(SPELLS_DIR)/$(SPELL)/desktop/.gitkeep"
	@[ -f "$(SPELLS_DIR)/$(SPELL)/README.md" ] || printf '# %s\n\nSpell scaffold for actions, binaries, configs, docs, tests, services, and completions.\n' "$(SPELL)" > "$(SPELLS_DIR)/$(SPELL)/README.md"
	@[ -f "$(SPELLS_DIR)/$(SPELL)/Makefile" ] || printf 'SHELL := /bin/bash\n\n.PHONY: test check fmt clean\n\ntest:\n\t@echo "[skip] no spell-local tests configured"\n\ncheck:\n\t@echo "[skip] no spell-local checks configured"\n\nfmt:\n\t@echo "[skip] no spell-local formatting configured"\n\nclean:\n\t@echo "[skip] no spell-local cleanup configured"\n' > "$(SPELLS_DIR)/$(SPELL)/Makefile"
	@source "$(SPELL_HELPERS)"; sigils_enable_spell "$(SPELL)"
	@$(MAKE) link

.PHONY: install install-dev test check fmt clean
install install-dev test check fmt clean:
	@target="$@"; \
	source "$(SPELL_HELPERS)"; \
	spell_dirs=(); \
	if [[ -n "$(SPELL)" ]]; then \
		if ! sigils_spell_exists "$(SPELL)"; then \
			echo "ERROR: unknown spell: $(SPELL)"; \
			exit 1; \
		fi; \
		spell_dirs+=("$(SPELLS_DIR)/$(SPELL)"); \
	else \
		while IFS=$$'\t' read -r _spell _status spell_dir; do \
			spell_dirs+=("$$spell_dir"); \
		done < <(sigils_iter_spells); \
	fi; \
	for spell_dir in "$${spell_dirs[@]}"; do \
		if [ -f "$$spell_dir/Makefile" ]; then \
			if grep -Eq "^$$target:" "$$spell_dir/Makefile"; then \
				echo "--> $$target: $$(basename "$$spell_dir")"; \
				$(MAKE) -C "$$spell_dir" "$$target"; \
			else \
				echo "[warn] $$spell_dir does not implement target '$$target', skipping"; \
			fi; \
		else \
			echo "[warn] $$spell_dir has no Makefile, skipping"; \
		fi; \
	done

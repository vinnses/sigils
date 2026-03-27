SHELL := /bin/bash
SPELL_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

.PHONY: install install-dev test clean purge prompt

install:
	cd "$(SPELL_DIR)" && uv sync

install-dev:
	cd "$(SPELL_DIR)" && uv sync --dev

test:
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python tests/zotcli/smoke.py

clean:
	rm -f "$(SPELL_DIR)/data/cache.json" "$(SPELL_DIR)/data/state.json"
	@echo "Removed cache.json and state.json"

purge: clean
	rm -rf "$(SPELL_DIR)/.venv"
	@echo "Removed .venv"

prompt:
	@printf '%s\n' '# zotcli prompt snippet (_update_prompt style)'
	@printf '%s\n' 'local zot_info="$$(__zotcli_ps1)"'
	@printf '%s\n' 'if [[ -n "$$zot_info" ]]; then'
	@printf '%s\n' "    local C_ZOT='\\[\\e[36m\\]'"
	@printf '%s\n' '    PS1+="$${C_ZOT}$$zot_info$${C_RESET} "'
	@printf '%s\n' 'fi'

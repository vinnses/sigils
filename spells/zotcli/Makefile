SHELL := /bin/bash
SPELL_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

.PHONY: install install-dev test clean purge prompt prompt-session

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
	rm -rf "$(SPELL_DIR)/uv.lock" 
	@echo "Removed .venv"

prompt:
	@command zotcli shell-init --mode static

prompt-session:
	@command zotcli shell-init --mode session

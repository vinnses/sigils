SHELL := /bin/bash
SPELL_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

.PHONY: install install-dev test check clean purge prompt prompt-session

install:
	cd "$(SPELL_DIR)" && uv sync

install-dev:
	cd "$(SPELL_DIR)" && uv sync --dev

test:
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python tests/zotcli/smoke.py
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python tests/zotcli/test_db.py
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python tests/zotcli/test_vfs.py
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python tests/zotcli/test_sync.py
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python tests/zotcli/test_mutations.py
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python tests/zotcli/test_finder_db.py
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" bash tests/zotcli/test_shell_wrapper.sh

check:
	@bash -n "$(SPELL_DIR)/bin/zotcli"
	@bash -n "$(SPELL_DIR)/inits/bash/zotcli.bash"
	@bash -n "$(SPELL_DIR)/completions/bash/zotcli.bash"
	@python3 -m py_compile "$(SPELL_DIR)"/lib/*.py

clean:
	rm -f "$(SPELL_DIR)/data/cache.json" "$(SPELL_DIR)/data/state.json"
	@echo "Removed cache.json and state.json"

purge: clean
	rm -rf "$(SPELL_DIR)/.venv"
	rm -rf "$(SPELL_DIR)/uv.lock" 
	@echo "Removed .venv"

prompt:
	@echo "[info] zotcli prompt support loads automatically when the spell is enabled and init/env.bash is sourced."
	@echo "[info] Use: source init/env.bash"

prompt-session:
	@echo "[info] session prompt hook is installed by spells/zotcli/inits/bash/zotcli.bash."

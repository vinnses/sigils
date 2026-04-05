SHELL := /bin/bash
SPELL_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

.PHONY: install install-dev test check clean

install:
	cd "$(SPELL_DIR)" && uv sync

install-dev:
	cd "$(SPELL_DIR)" && uv sync --dev

test:
	cd "$(SPELL_DIR)" && SPELL_DIR="$(SPELL_DIR)" uv run python -m pytest tests/mdview -q

check:
	cd "$(SPELL_DIR)" && python3 -m py_compile lib/*.py
	@bash -n bin/mdview

clean:
	rm -f "$(SPELL_DIR)"/data/*.json
	rm -f "$(SPELL_DIR)"/logs/*.log

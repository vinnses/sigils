SHELL := /bin/bash

SPELL_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

.PHONY: install test check fmt clean

install:
	pip install pyzotero --break-system-packages

test:
	@SPELL_DIR="$(SPELL_DIR)" python3 "$(SPELL_DIR)/tests/zotcli/smoke.py"

check:
	@echo "[skip] no spell-local checks configured"

fmt:
	@echo "[skip] no spell-local formatting configured"

clean:
	@echo "[skip] no spell-local cleanup configured"

SHELL := /bin/bash

.PHONY: test check fmt clean

test:
	@bash tests/sigils/units.sh

check:
	@bash -n bin/sigils && echo "[ok] bin/sigils syntax" || echo "[fail] bin/sigils syntax"

fmt:
	@echo "[skip] no spell-local formatting configured"

clean:
	@echo "[skip] no spell-local cleanup configured"

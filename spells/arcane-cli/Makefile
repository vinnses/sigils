SHELL := /bin/bash

.PHONY: test check fmt clean

test:
	@bash tests/arcane/units.sh

check:
	@bash -n bin/arcane && echo "[ok] bin/arcane syntax" || echo "[fail] bin/arcane syntax"
	@bash -n lib/core.bash && echo "[ok] lib/core.bash syntax" || echo "[fail] lib/core.bash syntax"
	@bash -n completions/bash/arcane.bash && echo "[ok] completions/bash/arcane.bash syntax" || echo "[fail] completions/bash/arcane.bash syntax"
	@bash -n inits/bash/arcane.bash && echo "[ok] inits/bash/arcane.bash syntax" || echo "[fail] inits/bash/arcane.bash syntax"
	@command -v docker >/dev/null 2>&1 && echo "[ok] docker found" || echo "[warn] docker not found"

fmt:
	@echo "[skip] no spell-local formatting configured"

clean:
	@echo "[skip] no spell-local cleanup configured"

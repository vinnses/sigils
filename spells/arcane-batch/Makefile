.PHONY: test check fmt clean

check:
	@bash -n bin/arcane && echo "[ok] bin/arcane syntax" || echo "[fail] bin/arcane syntax"
	@bash -n lib/core.bash && echo "[ok] lib/core.bash syntax" || echo "[fail] lib/core.bash syntax"
	@bash -n completions/bash/arcane.bash && echo "[ok] completions/bash/arcane.bash syntax" || echo "[fail] completions/bash/arcane.bash syntax"
	@command -v docker >/dev/null 2>&1 && echo "[ok] docker found" || echo "[warn] docker not found"

test:
	@echo "[skip] no spell-local tests configured"

fmt:
	@echo "[skip] no spell-local formatting configured"

clean:
	@echo "[skip] no spell-local cleanup configured"

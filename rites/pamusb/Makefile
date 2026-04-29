.PHONY: test check fmt clean install link

SPELL_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
BIN       := $(SPELL_DIR)/bin/pamusb

install:
	@echo "pamusb has no automatic package install — dependencies must be met manually."
	@echo "Required tools: cryptsetup lsblk blkid parted mkfs.ext4 mkfs.vfat jq udevadm visudo loginctl"
	@echo "pam_usb must be built from source: https://github.com/aluzzardi/pam_usb"

test:
	@echo "[skip] no automated tests (requires live USB hardware)"

check:
	@echo "--- syntax checks ---"
	@bash -n "$(BIN)" && echo "[ok]  bin/pamusb" || echo "[fail] bin/pamusb"
	@for f in $(SPELL_DIR)/lib/*.sh; do \
		bash -n "$$f" && echo "[ok]  $$f" || echo "[fail] $$f"; \
	done
	@for f in $(SPELL_DIR)/templates/guard.sh $(SPELL_DIR)/templates/dispatch.sh; do \
		bash -n "$$f" && echo "[ok]  $$f" || echo "[fail] $$f"; \
	done
	@bash -n "$(SPELL_DIR)/completions/bash/pamusb.bash" \
		&& echo "[ok]  completions/bash/pamusb.bash" \
		|| echo "[fail] completions/bash/pamusb.bash"
	@echo "--- dependency check ---"
	@for cmd in cryptsetup lsblk blkid parted mkfs.ext4 mkfs.vfat jq udevadm loginctl; do \
		command -v "$$cmd" >/dev/null 2>&1 \
			&& echo "[ok]  $$cmd" \
			|| echo "[warn] $$cmd not found"; \
	done
	@command -v pamusb-conf >/dev/null 2>&1 && echo "[ok]  pamusb-conf" || echo "[warn] pamusb-conf not found (pam_usb not installed)"
	@command -v pamusb-check >/dev/null 2>&1 && echo "[ok]  pamusb-check" || echo "[warn] pamusb-check not found (pam_usb not installed)"

fmt:
	@echo "[skip] no spell-local formatting configured"

clean:
	@echo "[skip] no spell-local cleanup configured"

link:
	@chmod +x "$(BIN)"

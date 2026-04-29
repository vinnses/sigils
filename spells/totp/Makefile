.PHONY: test check fmt clean install

install:
	@echo "Installing totp dependencies..."
	@if [ -f /etc/os-release ]; then \
		. /etc/os-release; \
		case "$$ID" in \
			ubuntu|debian|linuxmint|pop) \
				echo "Detected: $$PRETTY_NAME"; \
				sudo apt install -y oathtool xclip openssl gnupg ;; \
			arch|manjaro|endeavouros) \
				echo "Detected: $$PRETTY_NAME"; \
				sudo pacman -S --needed oath-toolkit xclip openssl gnupg ;; \
			fedora) \
				echo "Detected: $$PRETTY_NAME"; \
				sudo dnf install -y oathtool xclip openssl gnupg ;; \
			*) \
				echo "Unknown distro: $$ID. Install manually: oathtool, openssl, gnupg, xclip" ;; \
		esac; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "Detected: macOS (Homebrew)"; \
		brew install oath-toolkit openssl gnupg; \
	else \
		echo "Could not detect OS. Install manually: oathtool, openssl, gnupg, xclip"; \
	fi

test:
	@bash tests/totp/units.sh

check:
	@command -v oathtool >/dev/null 2>&1 && echo "[ok] oathtool found" || echo "[fail] oathtool not found"
	@command -v gpg >/dev/null 2>&1 && echo "[ok] gpg found (recommended backend)" || echo "[fail] gpg not found"
	@command -v openssl >/dev/null 2>&1 && echo "[ok] openssl found" || echo "[fail] openssl not found"
	@command -v secret-tool >/dev/null 2>&1 && echo "[ok] secret-tool found (legacy keyring backend)" || echo "[warn] secret-tool not found (legacy keyring backend unavailable)"
	@command -v xclip >/dev/null 2>&1 || command -v wl-copy >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1 || command -v pbcopy >/dev/null 2>&1 \
		&& echo "[ok] clipboard tool found" || echo "[warn] no clipboard tool found (optional)"
	@bash -n bin/totp && echo "[ok] bin/totp syntax valid" || echo "[fail] bin/totp syntax error"
	@bash -n completions/bash/totp.bash && echo "[ok] completions/bash/totp.bash syntax valid" || echo "[fail] completions syntax error"

fmt:
	@echo "[skip] no spell-local formatting configured"

clean:
	@echo "[skip] no spell-local cleanup configured"

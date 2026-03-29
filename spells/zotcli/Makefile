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
	@printf '%s\n' '# zotcli prompt snippet (adicione DENTRO de _update_prompt, executado a cada prompt)'
	@printf '%s\n' 'zot_info="$$(__zotcli_ps1)"'
	@printf '%s\n' 'if [[ -n "$$zot_info" ]]; then'
	@printf '%s\n' "    C_ZOT='\\[\\e[36m\\]'"
	@printf '%s\n' '    PS1+="$${C_ZOT}$${zot_info}\[\e[0m\] "'
	@printf '%s\n' 'fi'

prompt-session:
	@printf '%s\n' '# session-only zotcli prompt (nao grava em arquivo algum)'
	@printf '%s\n' '__zotcli_prompt_apply() {'
	@printf '%s\n' '  local zot_info'
	@printf '%s\n' '  zot_info="$$(__zotcli_ps1)"'
	@printf '%s\n' '  [[ -z "$$zot_info" ]] && return'
	@printf '%s\n' '  PS1="$${PS1%\[zotcli:*\]}\\[zotcli:$${zot_info}\\] "'
	@printf '%s\n' '}'
	@printf '%s\n' 'case ";$${PROMPT_COMMAND};" in'
	@printf '%s\n' '  *";__zotcli_prompt_apply;"*) ;;'
	@printf '%s\n' '  *) PROMPT_COMMAND="$${PROMPT_COMMAND:+$${PROMPT_COMMAND}; }__zotcli_prompt_apply" ;;'
	@printf '%s\n' 'esac'

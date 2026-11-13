# Developer command catalog. Implementation lives in tool/*.sh (hooks call those directly).
# Windows: use Git Bash or WSL (same as the bash scripts).

DEVICE ?= linux

# Resolve flutter like tool/flutter_checks.sh: PATH, then FLUTTER_ROOT, then ~/flutter.
ifeq ($(shell command -v flutter 2>/dev/null),)
  ifneq ($(FLUTTER_ROOT),)
    export PATH := $(FLUTTER_ROOT)/bin:$(PATH)
  else ifneq ($(wildcard $(HOME)/flutter/bin/flutter),)
    export PATH := $(HOME)/flutter/bin:$(PATH)
  endif
endif

.PHONY: help ensure-env get analyze test check run doctor icons \
	hooks hooks-run agents-setup bump-patch clean

help:
	@echo "Omniscope developer targets:"
	@echo "  make get              flutter pub get (+ ensure .env)"
	@echo "  make analyze          tool/flutter_checks.sh analyze"
	@echo "  make test             tool/flutter_checks.sh test"
	@echo "  make check            analyze + test (same as pre-push)"
	@echo "  make run              flutter run -d \$$(DEVICE)  (default: linux)"
	@echo "  make run DEVICE=chrome"
	@echo "  make doctor           flutter doctor"
	@echo "  make icons            tool/regen_icons.sh"
	@echo "  make hooks            install pre-commit + pre-push hooks"
	@echo "  make hooks-run        pre-commit run --all-files"
	@echo "  make agents-setup     agents/ venv + pip install -e ."
	@echo "  make bump-patch       bump pubspec + AppInfo patch (CI does this on main)"
	@echo "  make clean            flutter clean"

ensure-env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "note: created .env from .env.example (fill in API keys locally)" >&2; \
	fi

get: ensure-env
	flutter pub get

analyze:
	tool/flutter_checks.sh analyze

test:
	tool/flutter_checks.sh test

check:
	tool/flutter_checks.sh all

run: ensure-env
	flutter run -d $(DEVICE)

doctor:
	flutter doctor

icons:
	tool/regen_icons.sh

hooks:
	pre-commit install --hook-type pre-commit --hook-type pre-push

hooks-run:
	pre-commit run --all-files

agents-setup:
	cd agents && python3 -m venv .venv && .venv/bin/pip install -e .

bump-patch:
	tool/bump_patch_version.sh

clean:
	flutter clean

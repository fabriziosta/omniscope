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
	hooks hooks-run agents-setup bump-patch clean \
	build build-linux build-windows build-macos build-ios \
	build-apk build-appbundle build-web

help:
	@echo "Omniscope developer targets:"
	@echo "  make get              flutter pub get (+ ensure .env)"
	@echo "  make analyze          tool/flutter_checks.sh analyze"
	@echo "  make test             tool/flutter_checks.sh test"
	@echo "  make check            analyze + test (same as pre-push)"
	@echo "  make run              flutter run -d \$$(DEVICE)  (default: linux)"
	@echo "  make run DEVICE=chrome"
	@echo "  make build            release builds this host can produce"
	@echo "  make build-linux      flutter build linux --release"
	@echo "  make build-windows    flutter build windows --release  (Windows host)"
	@echo "  make build-macos      flutter build macos --release    (macOS host)"
	@echo "  make build-ios        flutter build ios --release --no-codesign  (macOS)"
	@echo "  make build-apk        flutter build apk --release"
	@echo "  make build-appbundle  flutter build appbundle --release"
	@echo "  make build-web        flutter build web --release"
	@echo "  make doctor           flutter doctor"
	@echo "  make icons            tool/regen_icons.sh"
	@echo "  make hooks            install pre-commit + pre-push hooks"
	@echo "  make hooks-run        pre-commit run --all-files"
	@echo "  make agents-setup     agents/ venv + pip install -e ."
	@echo "  make bump-patch       bump pubspec + AppInfo patch (CI does this on main)"
	@echo "  make clean            flutter clean"
	@echo ""
	@echo "Note: Flutter does not cross-compile every desktop/iOS binary from one OS."
	@echo "  Linux host → linux + apk + web; macOS → macos + ios + apk + web;"
	@echo "  Windows host → windows + apk + web."

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

build-linux: ensure-env
	flutter build linux --release

build-windows: ensure-env
	flutter build windows --release

build-macos: ensure-env
	flutter build macos --release

build-ios: ensure-env
	flutter build ios --release --no-codesign

build-apk: ensure-env
	flutter build apk --release

build-appbundle: ensure-env
	flutter build appbundle --release

build-web: ensure-env
	flutter build web --release

# Host-aware: only platforms this machine can produce (skips the rest with a note).
build: ensure-env
	@os=$$(uname -s 2>/dev/null || echo unknown); \
	case "$$os" in \
		Linux) \
			echo "Building host-capable targets: linux, apk, web"; \
			$(MAKE) build-linux build-apk build-web; \
			echo "Skipped (need other hosts): windows, macos, ios"; \
			;; \
		Darwin) \
			echo "Building host-capable targets: macos, ios, apk, web"; \
			$(MAKE) build-macos build-ios build-apk build-web; \
			echo "Skipped (need other hosts): linux, windows"; \
			;; \
		MINGW*|MSYS*|CYGWIN*) \
			echo "Building host-capable targets: windows, apk, web"; \
			$(MAKE) build-windows build-apk build-web; \
			echo "Skipped (need other hosts): linux, macos, ios"; \
			;; \
		*) \
			echo "error: unrecognized host '$$os'; use a platform-specific build-* target" >&2; \
			exit 1; \
			;; \
	esac

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

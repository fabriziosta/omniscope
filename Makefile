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
	hooks hooks-run agent-skills bump-patch clean \
	build build-linux build-windows build-macos build-ios \
	build-apk build-appbundle build-web \
	container-build container-run venue-canary

help:
	@echo "Omniscope developer targets:"
	@echo "  make get              flutter pub get (+ ensure .env)"
	@echo "  make analyze          tool/flutter_checks.sh analyze"
	@echo "  make test             tool/flutter_checks.sh test"
	@echo "  make check            analyze + test (same as pre-push)"
	@echo "  make venue-canary     live venue API probes (not part of check)"
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
	@echo "  make agent-skills     refresh Flutter/Dart/Genkit skills into .agents/skills/"
	@echo "  make bump-patch       bump patch; AppInfo gets +short SHA (CI on main)"
	@echo "  make clean            flutter clean"
	@echo "  make container-build  podman build slim Linux runtime image (omniscope:runtime)"
	@echo "  make container-run    podman run omniscope:runtime (needs DISPLAY)"
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

# Live network probes through Dart adapters (Yahoo / Crypto.com / Alpaca).
# Not part of make check / pre-push — public always; portfolio when .env has keys.
# Uses flutter test (package needs dart:ui); do not add to flutter_checks.sh.
venue-canary: ensure-env
	flutter test test/venue_canary_test.dart --tags live_canary --reporter expanded

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

# Refresh official Flutter + Dart + Genkit Agent Skills into .agents/skills/ (coding assistants).
# Re-run whenever upstream skills change: https://genkit.dev/docs/dart/get-started/
agent-skills:
	npx skills add flutter/agent-plugins --skill '*' --agent universal --yes
	npx skills add dart-lang/skills --skill '*' --agent universal --yes
	npx skills add genkit-ai/skills --skill developing-genkit-dart --agent universal --yes

bump-patch:
	tool/bump_patch_version.sh

clean:
	flutter clean

# Slim Linux desktop runtime image (multi-stage; Flutter SDK discarded).
container-build:
	podman build -t omniscope:runtime -f Containerfile .

# GUI app — forwards host X11 display. Wayland hosts may need extra flags.
container-run:
	podman run --rm -it \
		-e DISPLAY \
		-v /tmp/.X11-unix:/tmp/.X11-unix:ro \
		omniscope:runtime

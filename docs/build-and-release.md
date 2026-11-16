# Build and release

Agent handbook: [`AGENTS.md`](../AGENTS.md). Setup: [`development.md`](development.md). Container image: [`container.md`](container.md).

## Release builds

Flutter does **not** cross-compile every desktop/iOS binary from one machine. Prefer per-platform targets, or `make build` for whatever the current host can produce:

```bash
make build               # Linux → linux+apk+web; macOS → macos+ios+apk+web; Windows → windows+apk+web
make build-linux         # flutter build linux --release
make build-windows       # Windows host
make build-macos         # macOS host
make build-ios           # macOS; unsigned (--no-codesign)
make build-apk           # Android APK (needs Android SDK)
make build-appbundle     # Android AAB for Play Store
make build-web
```

| Artifact | Target | Host needed |
|----------|--------|-------------|
| Linux desktop | `build-linux` | Linux + GTK toolchain |
| Windows desktop | `build-windows` | Windows |
| macOS desktop | `build-macos` | macOS + Xcode |
| iOS (unsigned `.app`) | `build-ios` | macOS + Xcode |
| Android APK / AAB | `build-apk` / `build-appbundle` | any + Android SDK |
| Web | `build-web` | any |

Artifacts land under `build/` (e.g. Linux `build/linux/x64/release/bundle/`, APK `build/app/outputs/flutter-apk/app-release.apk`, Web `build/web/`).

## CI (GitHub Actions)

Linux runners only (`.github/workflows/`):

| Workflow | When | What |
|----------|------|------|
| **CI** ([`ci.yml`](../.github/workflows/ci.yml)) | PR + push to `main` | Gitleaks + `tool/flutter_checks.sh all` (analyze + test); `flutter build linux` as compile smoke (no artifact upload). Web smoke paused. |
| **Release** ([`release.yml`](../.github/workflows/release.yml)) | Push tag `v*` only | Build Linux + APK and attach them to a GitHub Release (web asset paused) |
| **Container** ([`container.yml`](../.github/workflows/container.yml)) | Push tag `v*` + manual | Build [`Containerfile`](../Containerfile) and push `ghcr.io/<owner>/omniscope` (`:latest`, semver tags) |
| **Bump patch** ([`bump-patch-version.yml`](../.github/workflows/bump-patch-version.yml)) | Push to `main` | Auto-increments patch in `pubspec.yaml` / AppInfo (does **not** create tags) |

Optional: enable branch protection required checks for CI jobs `check` and `build-linux`.

## Cutting a release

After merge + auto patch bump on `main`:

```bash
# Tag uses MAJOR.MINOR.PATCH from the single pubspec/AppInfo version (e.g. 1.0.1+2 → v1.0.1)
git checkout main && git pull
VERSION="$(tool/bump_patch_version.sh --check | cut -d+ -f1)"
git tag "v${VERSION}"
git push origin "v${VERSION}"
```

Or tag explicitly: `git tag v1.0.1 && git push origin v1.0.1`. Release assets: `omniscope-linux.tar.gz`, `omniscope.apk`. The same tag also triggers the Container workflow → `ghcr.io/fabriziosta/omniscope:<version>`.

Versioning rules (one `MAJOR.MINOR.PATCH+BUILD` in pubspec and AppInfo, patch bump script): see [`AGENTS.md`](../AGENTS.md) **Commands → Versioning**.

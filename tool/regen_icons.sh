#!/usr/bin/env bash
# Regenerate platform launcher icons from assets/brand/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/flutter/bin:${PATH}"

dart run flutter_launcher_icons

python3 - <<'PY'
from pathlib import Path
from PIL import Image

root = Path(".")
src = Image.open(root / "assets/brand/app_icon.png").convert("RGBA")
out_dir = root / "linux/runner/resources"
out_dir.mkdir(parents=True, exist_ok=True)
for size in (256, 512):
    src.resize((size, size), Image.Resampling.LANCZOS).save(
        out_dir / f"app_icon_{size}.png", "PNG", optimize=True
    )
src.resize((256, 256), Image.Resampling.LANCZOS).save(
    out_dir / "app_icon.png", "PNG", optimize=True
)
print("Updated linux/runner/resources/app_icon*.png")
PY

echo "Done. Masters: assets/brand/ — launchers refreshed for Android/iOS/macOS/Web/Windows + Linux."

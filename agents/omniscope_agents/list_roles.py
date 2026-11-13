"""Print roles from manifest.json (same source Flutter uses)."""

from __future__ import annotations

import json
from pathlib import Path


def main() -> None:
    path = Path(__file__).with_name("manifest.json")
    data = json.loads(path.read_text(encoding="utf-8"))
    for role in data.get("roles", []):
        suggested = role.get("suggestedModels") or {}
        print(
            f"{role.get('id')}: {role.get('title')} "
            f"[{role.get('framework')}/{role.get('workload')}] "
            f"module={role.get('module')}"
        )
        if suggested:
            print(f"  suggested: {suggested}")


if __name__ == "__main__":
    main()

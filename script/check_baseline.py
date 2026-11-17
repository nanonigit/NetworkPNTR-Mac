#!/usr/bin/env python3
"""Compare the tracked inventory to a supplied, pinned upstream checkout."""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
inventory = json.loads((root / "docs/feature-map.json").read_text())
revision = subprocess.check_output(["git", "-C", str(args.source), "rev-parse", "HEAD"], text=True).strip()
if revision != inventory["baseline"]:
    raise SystemExit("Baseline commit differs; review changes before changing parity requirements.")
nav = (args.source / "web/src/navigation/sidebar/sidebar-items.ts").read_text()
actual = re.findall(r'\{ id: "([^"]+)", title: "[^"]+", url: "([^"]+)", icon:', nav)
expected = [(item["id"], item["browserPath"]) for item in inventory["features"]]
assert actual == expected, "Navigation omission or reordering"
pages = sorted(str(path.relative_to(args.source)) for path in (args.source / "web/src/app").rglob("page.tsx"))
assert pages == sorted(item["source"] for item in inventory["routes"]), "Page omitted"
endpoints = re.findall(r'mux.HandleFunc\("([^"]+)"', (args.source / "server/server.go").read_text())
assert endpoints == inventory["endpoints"], "API handler omitted"
copied = json.loads((root / "Sources/NetworkPNTRCore/Resources/feature-map.json").read_text())
assert copied == inventory, "Native catalog and tracked parity inventory differ"
print(json.dumps({"baseline": revision, "navigation_features": len(actual), "page_routes": len(pages), "api_handlers": len(endpoints), "inventory_parity": True, "native_workflow_parity": "pending"}, indent=2))

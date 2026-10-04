#!/usr/bin/env bash
# Regenerates the website images (docs/screenshot.png, docs/styles.png) from the
# real views, rendered offscreen with sample data (no screen recording needed).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=.screens
mkdir -p "$OUT/bin"
# the renderer sets the store's state directly, so compile a settable copy
sed -e 's/@Published private(set) var/@Published var/' Sources/Headroom/UsageStore.swift > "$OUT/bin/UsageStore.swift"
swiftc -swift-version 5 -o "$OUT/bin/render" scripts/screens/main.swift "$OUT/bin/UsageStore.swift" \
	$(ls Sources/Headroom/*.swift | grep -v -e '/main.swift' -e '/UsageStore.swift')
"$OUT/bin/render" "$OUT" scripts/screens/sample-usage.json
node scripts/screens/compose.mjs "$OUT" docs

#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_file="$(mktemp /tmp/codex-panel-test.XXXXXX.swift)"
trap 'rm -f "$test_file"' EXIT
print 'import AppKit' > "$test_file"
sed -n '/^func quotaPanelFrame/,/^}/p' "$project_dir/Sources/CodexQuota/main.swift" >> "$test_file"
cat >> "$test_file" <<'SWIFT'
let screens = [NSRect(x: 0, y: 40, width: 1440, height: 835), NSRect(x: -1920, y: 0, width: 1920, height: 1055), NSRect(x: 0, y: 1080, width: 1280, height: 695), NSRect(x: 0, y: 0, width: 320, height: 380)]
for screen in screens {
    for x in [screen.minX, screen.midX, screen.maxX - 24] {
        let anchor = NSRect(x: x, y: screen.maxY, width: 24, height: 24)
        let frame = quotaPanelFrame(anchor: anchor, visibleFrame: screen)
        assert(screen.insetBy(dx: 10, dy: 10).contains(frame), "Panel escaped screen: \(frame)")
        assert(frame.maxY <= anchor.minY)
    }
}
print("Passed: left/right edges, negative display origin, stacked displays, short screen")
SWIFT
swift "$test_file"

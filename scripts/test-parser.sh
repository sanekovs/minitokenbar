#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_file="$(mktemp /tmp/codex-quota-test.XXXXXX.swift)"
trap 'rm -f "$test_file"' EXIT
sed '/^final class QuotaModel/,$d' "$project_dir/Sources/CodexQuota/main.swift" > "$test_file"
cat "$project_dir/scripts/test-parser.swift" >> "$test_file"
swift "$test_file"

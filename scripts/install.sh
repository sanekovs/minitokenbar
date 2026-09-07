#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/CodexQuota.app"
binary="$project_dir/.build/release/CodexQuota"

cd "$project_dir"
swift build -c release

mkdir -p "$app_dir/Contents/MacOS"
cp "$binary" "$app_dir/Contents/MacOS/CodexQuota"
cp "$project_dir/support/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
ditto "$app_dir" /Applications/CodexQuota.app
open -a /Applications/CodexQuota.app

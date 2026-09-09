#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]] || (( ${$(sw_vers -productVersion)%%.*} < 14 )); then
  print -u2 'CodexQuota requires macOS 14 or newer.'
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  print -u2 'Install Apple Command Line Tools with xcode-select --install, then run this script again.'
  exit 1
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/CodexQuota.app"
install_root="/Applications"
if [[ ! -w "$install_root" ]]; then
  install_root="$HOME/Applications"
  mkdir -p "$install_root"
fi
# Keep updates at their existing per-user location when present.
if [[ -d "$HOME/Applications/CodexQuota.app" && ! -d /Applications/CodexQuota.app ]]; then
  install_root="$HOME/Applications"
fi
installed_app="$install_root/CodexQuota.app"

cd "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/CodexQuota" "$app_dir/Contents/MacOS/CodexQuota"
cp "$project_dir/support/Info.plist" "$app_dir/Contents/Info.plist"
mkdir -p "$app_dir/Contents/Resources"
ditto "$binary_dir/CodexQuota_CodexQuota.bundle" "$app_dir/Contents/Resources/CodexQuota_CodexQuota.bundle"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
# Replace the app only after the new build is ready.
pkill -x CodexQuota 2>/dev/null || true
ditto "$app_dir" "$installed_app"
open "$installed_app"
print "Installed and launched: $installed_app"

#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]] || (( ${$(sw_vers -productVersion)%%.*} < 14 )); then
  print -u2 'MiniTokenBar requires macOS 14 or newer.'
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  print -u2 'Install Apple Command Line Tools with xcode-select --install, then run this script again.'
  exit 1
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/MiniTokenBar.app"
install_root="/Applications"
if [[ ! -w "$install_root" ]]; then
  install_root="$HOME/Applications"
  mkdir -p "$install_root"
fi
# Keep updates at their existing per-user location when present.
if [[ -d "$HOME/Applications/MiniTokenBar.app" && ! -d /Applications/MiniTokenBar.app ]]; then
  install_root="$HOME/Applications"
fi
installed_app="$install_root/MiniTokenBar.app"

cd "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/MiniTokenBar" "$app_dir/Contents/MacOS/MiniTokenBar"
cp "$project_dir/support/Info.plist" "$app_dir/Contents/Info.plist"
mkdir -p "$app_dir/Contents/Resources"
ditto "$binary_dir/MiniTokenBar_MiniTokenBar.bundle" "$app_dir/Contents/Resources/MiniTokenBar_MiniTokenBar.bundle"
# SwiftPM resource bundling can leave Finder metadata on copied resources, which codesign rejects.
xattr -rc "$app_dir"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
# Replace the app only after the new build is ready.
pkill -x MiniTokenBar 2>/dev/null || true
ditto "$app_dir" "$installed_app"
# Retire the pre-rename app (was called CodexQuota) so there's no stale duplicate.
pkill -x CodexQuota 2>/dev/null || true
rm -rf /Applications/CodexQuota.app "$HOME/Applications/CodexQuota.app"
open "$installed_app"
sleep 3
if ! pgrep -x MiniTokenBar >/dev/null; then
  print -u2 "Installed, but MiniTokenBar exited during launch: $installed_app"
  print -u2 'Check Console → Crash Reports for MiniTokenBar. Do not share session credentials.'
  exit 1
fi
print "Installed and running: $installed_app"
print 'The usage panel opens at launch. Afterwards, click the percentages in the macOS menu bar.'
print 'Opening MiniTokenBar from Applications shows the panel again; it has no Dock icon.'

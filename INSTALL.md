# Install CodexQuota with Codex

These instructions apply when the user asks to install this app on their Mac.

1. Check that the host is macOS 14 or newer (`sw_vers -productVersion`). Check `xcode-select -p` and `xcrun --find swift`. If Apple Command Line Tools are missing, start `xcode-select --install` and ask the user to complete Apple's installer, then continue. Never accept a license on their behalf.
2. Clone `https://github.com/sanekovs/minitokenbar.git` into an unused local directory. If a checkout already exists, verify its origin and preserve uncommitted changes. Do not reset or overwrite existing work; use a fresh directory if needed.
3. Read `scripts/install.sh`, then run `zsh scripts/test-parser.sh` and `./scripts/install.sh` from the checkout. The installer builds before stopping the existing app, signs the local build, chooses a writable Applications folder, and launches it. It does not require sudo or change security settings.
4. Verify `pgrep -x CodexQuota` returns a running process and the installed bundle passes `codesign --verify --deep --strict <installed-app-path>`. If UI access is available, open the menu-bar popover and check that it loads usage. Otherwise report process verification separately from visual verification.
5. Tell the user where the app was installed. If it reports a missing or expired session, ask them to sign in through Codex and refresh the app. Do not read, print, copy, modify, or upload `~/.codex/auth.json` as part of installation. The running app reads the session itself.

Do not purchase credits, consume usage resets, change the user's subscription, enable login items, or disable Gatekeeper. The install request needs none of these actions.

## Update

In a clean checkout with the correct origin, run `git pull --ff-only`, then rerun `./scripts/install.sh`. Preserve local changes or use a new checkout instead. The installer replaces only CodexQuota's application bundle.

## If it appears not to launch

CodexQuota lives in the macOS menu bar and has no Dock icon. The panel opens on launch; opening the app again from Applications brings it back. Look for a percentage, `Codex …`, or `Codex !` at the top of the screen.

If the panel never appears, check `pgrep -x CodexQuota`. A missing process means launch failed; inspect the CodexQuota crash report in Console before diagnosing the cause. A generic Finder icon alone does not mean the app is broken. Report the macOS version, Mac architecture, and relevant crash error, without credentials or session files.

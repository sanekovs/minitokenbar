# CodexQuota

A deliberately small macOS menu-bar app for monitoring Codex usage.

The menu bar shows two equal-weight numbers:

```text
5-hour remaining · weekly remaining
```

Click the numbers for:

- 5-hour and weekly quota remaining
- reset dates and times
- subscription/API source
- today's largest local Codex task and model
- manual refresh

## Privacy

CodexQuota reads `~/.codex/auth.json` to request quota data from OpenAI and reads the local Codex SQLite database for task activity. Credentials and task history stay on the Mac; task history is never uploaded by this app.

The quota request uses the same authenticated ChatGPT usage endpoint used by Codex-compatible quota monitors. This is an unofficial project and is not affiliated with OpenAI.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- Codex signed in with a ChatGPT subscription, or API-key mode for source detection

## Build

```sh
swift build -c release
```

To create and install the menu-bar app:

```sh
./scripts/install.sh
```

## License

MIT

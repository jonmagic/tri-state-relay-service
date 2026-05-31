# Tri-State Relay Service

Tri-State Relay Service is a local macOS agent voicemail inbox. Agents submit short status messages with the `voicemail` CLI, TSRS stores them in a local SQLite queue, and a single playback path speaks one message at a time.

The first useful contract is intentionally small:

```sh
voicemail --project "Brain" --message "The daily project note is ready."
voicemail --project "Brain" --type complete --priority normal --message "The plan is ready to review."
voicemail list
voicemail ready
voicemail-processor
voicemail mute
voicemail unmute
voicemail clear
voicemail clear-heard
voicemail skip-next
voicemail mark-handled
voicemail replay-last
voicemail source
voicemail reveal-source
voicemail copy-source
voicemail status
```

## Project shape

This repository starts with the queue core and CLI before a menu bar UI. The invariant is more important than the surface: many producers can enqueue messages, but only the app-owned processor loop may speak.

1. The CLI never calls `/usr/bin/say` directly.
2. The app-owned processor loop claims and speaks ready messages through the locked processor path.
3. The SQLite store owns message state and persistent mode.
4. Focus mode is the safe default.
5. Ready mode releases exactly one voicemail, then returns to focus.
6. Messages stay short and intentionally authored.

## Getting started

Install dependencies:

```sh
npm install
```

Run checks:

```sh
npm run validate
```

Build the CLI:

```sh
npm run build
npm link
```

Build native Perry binaries:

```sh
npm run build:native
```

Perry currently compiles the CLI and processor entrypoints, but the
native runtime requires Perry-compatible dependencies. The SQLite store
uses `better-sqlite3`, which is covered by the Perry dependency check and
native runtime smoke test.

Build and run the macOS menu bar app:

```sh
npm run build:macos
open "dist/macos/Tri-State Relay Service.app"
```

The first interactable app is a SwiftUI `MenuBarExtra` host that shells
out to the Perry-built `voicemail` and `voicemail-processor` binaries.
It exposes ready, focus, mute, unmute, clear, refresh, and quit controls.
The app reads `voicemail status` JSON rather than scraping message text.
It also exposes lifecycle controls for skipping the next queued message,
replaying the last heard message, marking heard messages handled, and
clearing heard messages.
Source controls can reveal the latest captured working directory or copy
the latest captured working directory/URL without exposing message text.

By default, TSRS stores its database at `~/Library/Application Support/Tri-State Relay Service/voicemail.db`. For tests or local experiments, set `TSRS_DB_PATH` to another path.

## Next slices

1. Replace shell-out app actions with a native library boundary or direct Swift/Perry bridge.
2. Add safe aggregate queue views that summarize producers, projects, priorities, and stale blockers without exposing message text.

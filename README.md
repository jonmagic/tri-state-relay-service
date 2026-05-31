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

By default, TSRS stores its database at `~/Library/Application Support/Tri-State Relay Service/voicemail.db`. For tests or local experiments, set `TSRS_DB_PATH` to another path.

## Next slices

1. Add the first menu bar wrapper for ready, focus, replay last, mute, and queue status.
2. Add source-context actions for opening or revealing captured project paths.
3. Add safe aggregate queue views that summarize producers, projects, priorities, and stale blockers without exposing message text.

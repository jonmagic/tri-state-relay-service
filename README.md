# Tri-State Relay Service

Tri-State Relay Service is a local macOS agent voicemail inbox. Agents submit short status messages with the `voicemail` CLI, TSRS stores them in a local SQLite queue, and a single playback path speaks one message at a time.

The first useful contract is intentionally small:

```sh
voicemail --project "Brain" --message "The daily project note is ready."
voicemail --project "Brain" --type complete --priority normal --message "The plan is ready to review."
voicemail list
voicemail ready
voicemail mute
voicemail unmute
voicemail clear
```

## Project shape

This repository starts with the queue core and CLI before a menu bar UI. The invariant is more important than the surface: many producers can enqueue messages, but only the processor may speak.

1. The CLI never calls `/usr/bin/say` directly.
2. The SQLite store owns message state and persistent mode.
3. Focus mode is the safe default.
4. Ready mode releases exactly one voicemail, then returns to focus.
5. Messages stay short and intentionally authored.

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

By default, TSRS stores its database at `~/Library/Application Support/Tri-State Relay Service/voicemail.db`. For tests or local experiments, set `TSRS_DB_PATH` to another path.

## Next slices

1. Add an explicit processor command that claims and speaks one ready message through `/usr/bin/say`.
2. Add a launchd-friendly daemon loop with a single-writer lock.
3. Add the first menu bar wrapper for ready, focus, replay last, mute, and queue status.
4. Add source-context actions for opening or revealing captured project paths.

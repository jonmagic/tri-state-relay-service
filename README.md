# Tri-State Relay Service

Tri-State Relay Service is a local macOS agent voicemail inbox. Agents submit short status messages with the `voicemail` CLI, TSRS stores them in a local SQLite queue, and a single playback path speaks one message at a time.

The first useful contract is intentionally small:

```sh
voicemail --line "Brain" --message "The daily line note is ready."
voicemail --line "Brain" --type complete --priority normal --message "The plan is ready to review."
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
voicemail line
voicemail line "Tri-State Relay Service"
voicemail combiner
voicemail combiner --tool none|llm|apfel
voicemail status
```

## Line shape

The invariant is more important than the surface: many producers can enqueue messages, but only the app-owned processor loop may speak.

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

The menu bar app is an AppKit `NSStatusItem` host that shells out to the
Perry-built `voicemail` and `voicemail-processor` binaries. The app reads
`voicemail status` JSON rather than scraping message text. Right click
opens line controls; left click plays one queued voicemail and makes that
line active before speaking. When unmuted, the app keeps playing incoming
messages on the active line. Other lines stay quiet and can be pulled from
their line submenu.

Each line submenu scopes lifecycle controls to that line: play next, skip
next, clear queue, replay last, mark handled, and clear heard. Global
controls cover focus, ready, mute, unmute, clear, refresh, and quit.
Source controls can reveal the latest captured working directory or copy
the latest captured working directory/URL without exposing message text.

By default, TSRS stores its database at `~/Library/Application Support/Tri-State Relay Service/voicemail.db`. For tests or local experiments, set `TSRS_DB_PATH` to another path.

## Dogfooding

When developing TSRS, use the built native CLI to enqueue real progress
messages:

```sh
./dist/native/voicemail --line "Tri-State Relay Service" --type update --priority normal --cwd "$PWD" --message "I am starting the next implementation slice."
```

Good dogfood messages are short, intentionally authored status updates:
start of a meaningful slice, phase changes, blockers, requests for human
input, and completion summaries. Do not enqueue raw terminal output,
code, logs, secrets, private data, or long explanations.

## LLM evaluation

Inactive-line voicemail combination has a manual evaluation suite:

```sh
npm run eval:inactive-line
```

The suite runs `apfel` and `llm` against fixtures in
`evals/inactive-line-fixtures.json`, validates the JSON contract, and uses
an LLM judge prompt to score whether each candidate sounds like one useful
voicemail instead of a log summary. Results are written to
`evals/results/inactive-line-results.json`.

## Inactive-line combiner setting

Inactive-line rollups are configurable:

```sh
voicemail combiner --tool none
voicemail combiner --tool llm
voicemail combiner --tool apfel
```

`none` is the default and works without any LLM tool. In that mode TSRS
should avoid rollups and use latest-message-only behavior for inactive
lines. `llm` and `apfel` enable the prompt-driven combination workflow
described in `docs/inactive-line-combination.md`.

Current implementation note: the Node CLI path can invoke `llm` and
`apfel` for combination. The Perry native CLI falls back to latest-only
behavior even when a combiner is selected, because native child-process
handling is not reliable enough for multi-message LLM combination yet.

## Lines

TSRS tracks an active line:

```sh
voicemail line
voicemail line "Tri-State Relay Service"
```

The menu bar app shows the active line and queued lines in the right-click
menu. When unmuted, the app keeps playing queued messages from the active
line as they arrive. Messages from other lines remain queued until you
switch lines or pull them manually. Pulling a message from another line
makes that line active.

## Next slices

1. Add safe aggregate queue views that summarize producers, lines, priorities, and stale blockers without exposing message text.
2. Replace shell-out app actions with a native library boundary or direct Swift/Perry bridge.
3. Refine source controls so line submenus can reveal or copy source context for that specific line.

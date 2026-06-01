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
voicemail combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
voicemail settings
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
Perry-built `voicemail` binary for queue controls and supervises one
app-owned `voicemail-processor --app-loop` child for playback. The app reads
`voicemail status` JSON rather than scraping message text. Right click opens
line controls; left click selects the next queued line for playback. When
unmuted, the processor loop keeps playing incoming messages on the active
line. Other lines stay quiet and can be pulled from their line submenu.

The processor binary refuses direct terminal launches unless the app injects
`TSRS_PROCESSOR_AUTH=app-owned-processor`. This keeps the CLI as a queue and
control interface while preserving the app-owned speech path.

Each line submenu scopes lifecycle controls to that line: play next, skip
next, clear queue, replay last, mark handled, and clear heard. Global controls cover mute, unmute, settings, refresh, and quit.
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

Inactive-line rollups are configured with a command template. The Settings
window has an Inactive Combiner tab with commented examples for `llm` and
`apfel`, including their GitHub project URLs. Leave the template commented,
or clear it and save, to use latest-only inactive-line behavior.

```sh
voicemail combiner
voicemail combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
voicemail combiner --command none
```

The command is parsed into argv without a shell. Placeholders such as
`<input>`, `<system>`, and `<message>` are inserted as single argv values.
Pipes, redirects, command substitution, and shell expansion are intentionally
unsupported.

The Speech tab configures the command used by the processor to speak one
message. The default is `/usr/bin/say <message>`. `/usr/bin/say` ships with
macOS, so no extra install is required.

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

`voicemail status` includes a text-free `overview` with priority counts,
producer counts, and stale high-priority blockers. The overview is safe for
menu and automation use because it omits voicemail message text and source
paths.

Source controls are available globally and per line:

```sh
voicemail source
voicemail source --line "Tri-State Relay Service"
voicemail reveal-source --line "Tri-State Relay Service"
voicemail copy-source --line "Tri-State Relay Service"
```

Line submenu source actions use the selected line's latest source context,
not the newest source from another line.

Global hotkeys:

- `Control` + `Option` + `Command` + `Space`: play the current line.
- `Control` + `Option` + `Command` + `V`: open the menu.

## Next slices

1. Add terminal-specific focus adapters where reliable.

# Tri-State Relay Service

Tri-State Relay Service is a local macOS agent relay inbox. Agents submit short status messages with the `relay` CLI, TSRS stores them as relays in a local SQLite queue, and a single playback path speaks one relay at a time.

The first useful contract is intentionally small:

```sh
relay --line "Brain" --message "The daily line note is ready."
relay --line "Brain" --type complete --priority normal --message "The plan is ready to review."
relay list
relay ready
relay mute
relay unmute
relay clear
relay clear-delivered
relay skip-next
relay acknowledge
relay replay-last
relay line
relay line "Tri-State Relay Service"
relay combiner
relay combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
relay settings
relay status
```

## Line shape

The invariant is more important than the surface: many producers can enqueue relays, but only the app-owned playback path may speak.

1. The CLI never calls `/usr/bin/say` directly.
2. The app owns relay playback with native AVFoundation speech.
3. The SQLite store owns message state and persistent mode.
4. Focus mode is the safe default.
5. Ready mode releases exactly one relay, then returns to focus.
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

Perry currently compiles the CLI and legacy processor entrypoints, but the
native runtime requires Perry-compatible dependencies. The SQLite store
uses `better-sqlite3`, which is covered by the Perry dependency check and
native runtime smoke test.

Build and run the direct-download macOS menu bar app:

```sh
npm run build:macos
open "dist/macos/Tri-State Relay Service.app"
```

The macOS app is built through
`src/macos/TriStateRelayService.xcodeproj`; the npm build wrapper still builds
and bundles the Perry-built `relay` CLI for agent integrations.

The primary distribution direction is a signed and notarized direct-download
Mac app with a standard bundled or installable `relay` CLI. Future Pro
licensing should use a direct-download license-key flow rather than StoreKit
unless the Mac App Store becomes a primary target again. See
`docs/distribution.md`.

Build the App Store-safe profile:

```sh
npm run build:macos:app-store
open "dist/macos-app-store/Tri-State Relay Service.app"
```

The App Store-safe profile passes the `APP_STORE` Swift compilation condition
through xcodebuild. The direct profile is the primary dogfooding and
distribution path. Signing/notarization should copy and sign the bundled
`relay` helper before sealing the app bundle.

The direct profile is an AppKit `NSStatusItem` host that owns menu state, queue
controls, speech claims, and playback in Swift. The app reads and mutates the
local SQLite queue directly without scraping or exposing message text. Right
click opens line controls; left click selects the next queued line for playback.
When unmuted, the app keeps playing incoming relays on the active line. Other
lines stay quiet and can be pulled from their line submenu.

Both macOS profiles are packaged from the CLI-only native build and do not
bundle or launch the legacy processor. The App Store-safe profile keeps terminal
enqueueing disabled and hides external inactive-line combiner command templates.
Playback is claimed and spoken by the app with AVFoundation speech using the
configured native voice.

Before claiming a relay for speech, the app checks whether the default input
device appears to be actively captured by another app. When microphone capture
is active, TSRS leaves relays queued and retries later instead of speaking over
the user. This is a best-effort CoreAudio device-state check; TSRS does not
record or inspect microphone audio.

The profile also exposes a capability seam through `relay settings`. The
App Store-safe profile reports native speech, line-scoped source actions, no
terminal enqueueing, disabled external command templates, and a one-line
free-tier limit. The direct profile reports the power-user command-template,
terminal enqueue, and line-scoped source action capabilities. No purchase flow
or StoreKit behavior is implemented yet. `relay status` also reports the active
profile and capabilities for automation and diagnostics.

Normal CLI usage remains the queue and automation interface for agents, while
the menu bar app owns interactive queue controls and speech state through native
SQLite access.

Each line submenu scopes lifecycle controls to that line: play next, skip
next, clear queue, replay last, acknowledge last, clear delivered, and source
actions for that line. Global controls cover mute, unmute, settings, refresh,
and quit. Source actions are app menu actions only; there is no global source
menu, no overview section, and no CLI source command surface.

To keep old lines from living in the menu forever, TSRS expires stale relays
from menu views after 30 minutes. Delivered and failed relays expire by
`updated_at`; queued normal or low-priority update/complete relays expire by
`created_at`. High-priority queued relays and blocked/needs-input relays stay
until handled explicitly.

By default, TSRS stores its database at `~/Library/Application Support/Tri-State Relay Service/relay.db`. For tests or local experiments, set `TSRS_DB_PATH` to another path.

## Dogfooding

When developing TSRS, use the built native CLI to enqueue real progress
messages:

```sh
./dist/native/relay --line "Tri-State Relay Service" --type update --priority normal --cwd "$PWD" --message "I am starting the next implementation slice."
```

Good dogfood relays are short, intentionally authored status updates:
start of a meaningful slice, phase changes, blockers, requests for human
input, and completion summaries. Do not enqueue raw terminal output,
code, logs, secrets, private data, or long explanations.

## LLM evaluation

Inactive-line relay combination has a manual evaluation suite:

```sh
npm run eval:inactive-line
```

The suite runs `apfel` and `llm` against fixtures in
`evals/inactive-line-fixtures.json`, validates the JSON contract, and uses
an LLM judge prompt to score whether each candidate sounds like one useful
relay instead of a log summary. Results are written to
`evals/results/inactive-line-results.json`.

## Inactive-line combiner setting

Inactive-line rollups are configured with a command template in the direct
profile. The direct Settings window has an Inactive Combiner tab with
commented examples for `llm` and `apfel`, including their GitHub project URLs.
Leave the template commented, or clear it and save, to use latest-only
inactive-line behavior. External combiner command execution is unavailable in
the App Store-safe profile, which uses latest-only inactive-line behavior.

```sh
relay combiner
relay combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
relay combiner --command none
```

The command is parsed into argv without a shell. Placeholders such as
`<input>`, `<system>`, and `<message>` are inserted as single argv values.
Pipes, redirects, command substitution, and shell expansion are intentionally
unsupported.

The Settings window has a Voice tab for choosing the native AVFoundation voice
used by the menu bar app. Speech command templates are legacy
processor/terminal compatibility settings and are not exposed in the app.

## Lines

TSRS tracks an active line:

```sh
relay line
relay line "Tri-State Relay Service"
```

The menu bar app currently shows the active line and queued lines in the
right-click menu. Left click remains the fastest pointer path for Play Next.
When unmuted, the app keeps playing queued messages from the active line as they
arrive. Messages from other lines remain queued until you switch lines or pull
them manually. Pulling a message from another line makes that line active.

Line submenu source actions use the selected line's latest source context, not
the newest source from another line. The global menu does not show source
actions.

The next interaction direction is a Raycast-style command palette for
keyboard-first relay actions. See `docs/command-palette.md`.

Global hotkeys:

- `Control` + `Option` + `Command` + `Space`: currently plays the current line;
  planned to open the command palette with `play next` preselected.
- `Control` + `Option` + `Command` + `V`: open the menu.

## Next slices

1. Build the Raycast-style command palette in `docs/command-palette.md`.
2. Add signing and notarization packaging for the direct-download app.
3. Split the native app into smaller Swift files under the Xcode project.

## App Review note draft

Tri-State Relay Service is a local macOS menu bar status inbox for developer
tools. It stores short user-authored status relays locally and plays them
through the app-controlled speech path only when the user enables playback.
The App Store build does not execute arbitrary user-provided shell commands or
download executable code. External command integrations are reserved for the
separately distributed direct-download edition.

See `docs/distribution.md` for the signed direct-download direction and
`docs/app-store-profile.md` for the App Store-safe hardening profile.

# CLI parity inventory

This is the parity oracle for replacing the Perry/Node CLI with native Swift.
It records behavior from the shipped compiled binary, `dist/native/relay`, not
from the TypeScript source path.

## Native Swift cutover readiness

The current repository is not ready to delete `package.json`,
`package-lock.json`, TypeScript sources/tests, npm scripts, Perry, or generated
`dist` JavaScript in one safe step. The exact blockers from the current tree
are:

1. `dist/native/relay` is still the shipped CLI oracle and bundled helper. The
   macOS build wrapper copies it into `dist/macos/Tri-State Relay
   Service.app/Contents/MacOS/relay`, the direct app shells out to that helper
   for `cli-status` and `install-cli`, and dogfooding instructions use it to
   enqueue relays. Deleting it first would remove the agent integration surface.
2. A standalone Swift `relay-native` CLI target now exists with a shared
   `RelayCore.swift` dispatcher. It currently supports `--version`, help, and a
   validation-only `normalize` command, but it does not yet implement the full
   queue-writing `relay` command surface.
3. The current CLI behavior still lives in `src/cli.ts`, including enqueue,
   list, status, state, ready/focus/mute/unmute, line, combiner, settings,
   replay/skip/acknowledge/clear, app helper commands, `cli-status`,
   `install-cli`, `--version`, direct-vs-legacy-profile capability reporting,
   and external inactive-line combiner execution.
4. The current persistent queue contract still has TypeScript as its most
   complete implementation in `src/storage/store.ts`. Swift now owns fresh
   database creation, WAL/default settings, legacy combiner migration, message
   validation, and native enqueue primitives, but the cutover still needs
   explicit parity for CLI inactive-line latest-only/custom combination
   behavior, aggregate status JSON, install status JSON, stale expiry, and all
   command mutations.
5. `src/core/cli-install.ts` owns the install/update safety rules for copying
   `relay` to `~/.local/bin/relay`: source and target signatures, stale/current
   detection, foreign-binary refusal, executable mode preservation, version
   output, and PATH diagnostics. The Swift app currently delegates those checks
   to the bundled CLI.
6. `package.json` is still the single entry point for validation and several
   release/developer wrappers: `npm test`, `npm run typecheck`, `npm run build`,
   `npm run build:native:cli`, `npm run build:macos:direct`,
   `npm run package:macos:direct`, `npm run restart:macos`, and
   `npm run eval:inactive-line`. The macOS build/package wrappers now delegate
   to shell scripts, but npm remains the top-level command runner.
7. Perry remains in the active direct-build path because
   `scripts/build-macos.sh` compiles `src/cli.ts` before Xcode and then bundles
   `dist/native/relay`. `scripts/package-macos-direct.sh` signs and smoke-tests
   that bundled helper before signing and notarizing the app.
8. The tracked TypeScript test suite is the broadest regression harness for the
   CLI, storage, command-template parsing, direct-vs-legacy capabilities,
   processor compatibility, bundle validation, and app shell seams. Swift XCTest
   coverage exists for message validation, playback profile behavior, native
   relay store creation/migration, and the initial `relay-native` dispatcher,
   but not yet for the full CLI oracle in this inventory.
9. Shell scripts now own macOS app build and direct-download packaging, while
   `scripts/*.mjs` still provide restart, eval, and test-only bundle validation
   automation. Even after the CLI moves to Swift, replacing `package.json` also
   requires either SwiftPM, Xcode schemes, Makefile-style wrappers, or another
   non-Node automation path for restart, bundle inspection tests, inactive-line
   evaluation, and remaining validation wrappers.
10. `dist/src/**/*.js` and `dist/tests/**/*.js` are ignored TypeScript build
    outputs, not source of truth. They can be removed locally, but `npm run
    build` will recreate them until the TypeScript build and validation path is
    retired.
11. `dist/native/relay-processor` is already absent from the current ignored
    build output and the app bundle must not include `relay-processor`, but
    `src/processor.ts`, processor tests, and the `build:native` script still
    carry legacy compatibility coverage. Removing them is safe only after an
    explicit product decision that no terminal/legacy processor path remains.

Safe deletion order:

1. Expand the native Swift `relay-native` CLI target until it can write to the
   same SQLite store and cover the full direct-download command surface.
2. Build a Swift parity harness from this inventory against the current
   `dist/native/relay` oracle, prioritizing direct-download behavior and keeping
   legacy App Store-profile behavior as reference only.
3. Port CLI install/update safety from `src/core/cli-install.ts` so the app no
   longer shells out to the bundled Node/Perry helper for `cli-status` or
   `install-cli`.
4. Move release wrappers off Perry: Xcode or SwiftPM builds the app and CLI,
   packaging signs and smoke-tests the Swift `relay`, and bundle validation still
   proves `relay-processor` is absent.
5. Migrate or retire TypeScript tests by replacing their coverage with XCTest or
   another non-Node test runner for CLI output, SQLite side effects, command
   template safety, bundle inspection, and direct-download customization.
6. Flip docs and app packaging to the Swift `relay`; keep `dist/native/relay`
   only as a temporary oracle until the parity harness passes.
7. Remove Perry scripts and dependency entries, then delete `src/cli.ts`,
   `src/storage/**`, `src/core/**`, `src/app/**`, `src/processor.ts`, and
   `tests/**/*.ts` only after their Swift replacements or retirements are
   validated.
8. Delete `package.json`, `package-lock.json`, `tsconfig.json`, `node_modules`,
   `.perry-cache`, and ignored `dist/src`/`dist/tests` outputs last, once no
   documented build, validation, packaging, dogfooding, or app install path uses
   npm, TypeScript, Perry, or generated JavaScript.

The concrete next engineering slice is therefore: expand the Swift CLI target
from validation-only commands to queue-writing direct-profile commands, add a
direct-profile parity harness for this command matrix, then change
`scripts/build-macos.sh` to bundle the Swift-built `relay` instead of
`dist/native/relay`.

Probe environment:

- Oracle: `./dist/native/relay`
- Version: `relay 0.1.0`
- Database isolation: `TSRS_DB_PATH` pointed at throwaway repository-local
  SQLite files for each probe.
- Profile isolation: direct profile by default. App Store behavior was probed
  with `TSRS_DISTRIBUTION_PROFILE=app-store` as legacy/profile-reference only;
  it is no longer an active product target for this migration.
- App helper authorization: `TSRS_PROCESSOR_AUTH=app-owned-processor`.

## Global behavior

1. The binary opens and migrates the SQLite database before dispatching commands.
   Even no-op, help, and invalid commands can create the database and WAL files.
2. A fresh database creates:
   - `schema_migrations(version)` with version `1`
   - `settings(key, value)`
   - `relays(id, line, message, type, priority, session, app, cwd, url, status, created_at, updated_at)`
   - default settings: `mode=focus`, `muted=false`,
     `inactive_line_combiner=none`, `inactive_line_combiner_command=<commented template>`,
     and `speech_command=<default command template>`
3. `PRAGMA journal_mode = WAL` is applied during startup.
4. Most successful commands write human text to stdout and leave stderr empty.
   JSON commands emit compact one-line JSON.
5. The shipped `relay` CLI stores inactive-line combiner settings but does not
   execute the external combiner command when `process.argv[1]` ends in
   `/relay`. Enqueue behavior from this oracle is latest-only inactive-line
   collapse even when a custom combiner command is configured.
6. The compiled Perry binary currently exits `0` with empty stdout/stderr for
   thrown runtime errors such as validation failures, unauthorized app helper
   commands, App Store enqueue attempts, and missing required flags. The Swift
   parity harness should capture this as current oracle behavior before deciding
   whether to preserve or intentionally fix it.
7. `relay --help` is parsed as an enqueue command with a missing flag. In the
   compiled binary it exits `0` with empty stdout/stderr. `relay` and
   `relay help` print usage and exit `0`.
8. Unknown commands print usage. The compiled binary exits `0` even though the
   TypeScript source sets an error exit code.

## Command matrix

| Command | Inputs | Stdout shape | Stderr | Exit code | SQLite state change | Direct vs App Store | Comparison |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Enqueue | `relay --line <line> --message <message> [--type update\|complete\|blocked\|needs-input] [--priority low\|normal\|high] [--session <id>] [--app <name>] [--cwd <path>] [--url <url>]` or `relay enqueue ...` | `queued relay #<id> <line>: <normalized message>` or `dropped inactive line update` | Empty on success | `0` | Inserts `relays` row with `status=queued`, normalized line/message/metadata, default `type=update`, default `priority=normal`; seeds `active_line` only if absent. Inactive-line direct behavior deletes existing queued relays for that inactive line and keeps only the latest relay. The shipped `relay` binary does not execute the stored external combiner command. | Direct allows terminal enqueue. App Store profile currently throws before enqueue; compiled oracle exits `0` with no output and no relay row. | Exact stdout for human text; semantic DB comparison for inserted row. |
| `list` | `relay list` | First line `mode=<focus\|ready> muted=<true\|false>`, then up to 20 relays as `#<id> [<status>] [<priority>] <line>: <message>` ordered speaking, queued, heard, then other statuses by creation time. | Empty | `0` | No mutation beyond startup migration. | Same profile-independent format. | Exact text after normalizing dynamic ids when needed. |
| `ready` | `relay ready` | `ready to release one relay`; if muted, `release queued, but muted is on` | Empty | `0` | Sets `settings.mode=ready`. Does not claim by itself. | Same. | Exact text plus settings comparison. |
| `focus` | `relay focus` | `focus mode on` | Empty | `0` | Sets `settings.mode=focus`. | Same. | Exact text plus settings comparison. |
| `mute` | `relay mute` | `muted` | Empty | `0` | Sets `settings.muted=true`. | Same. | Exact text plus settings comparison. |
| `unmute` | `relay unmute` | `unmuted` | Empty | `0` | Sets `settings.muted=false`. | Same. | Exact text plus settings comparison. |
| `clear` | `relay clear` | `cleared <n> relays` | Empty | `0` | Deletes relays with status `queued`, `heard`, `handled`, `skipped`, `expired`, or `failed`; leaves `speaking` rows. | Same. | Exact text with numeric count plus DB comparison. |
| `clear-delivered` | `relay clear-delivered [--line <line>]`; alias `clear-heard` | `cleared <n> delivered relays` | Empty | `0` | Deletes `heard` rows globally or only for the requested line. | Same. User-facing term is delivered; storage state remains `heard`. | Exact text plus DB comparison. |
| `skip-next` | `relay skip-next [--line <line>]` | `skipped relay #<id>` or `no queued relay to skip` | Empty | `0` | Marks the highest-priority, oldest matching `queued` relay as `skipped`. | Same. | Exact text with dynamic id plus DB comparison. |
| `acknowledge` | `relay acknowledge [--line <line>]`; alias `mark-handled` | `handled relay #<id>` or `no delivered relay to mark handled` | Empty | `0` | Marks the latest matching `heard` relay as `handled`. | Same. User-facing term is handled/acknowledged; storage state is `handled`. | Exact text with dynamic id plus DB comparison. |
| `replay-last` | `relay replay-last [--line <line>]` | `queued relay #<id> for replay` or `no delivered relay to replay` | Empty | `0` | Marks the latest matching `heard` relay back to `queued`; it reuses the same id. | Same. | Exact text with dynamic id plus DB comparison. |
| `clear-line` | `relay clear-line --line <line>` | `cleared <n> queued relays from <line>` | Empty on success | `0` | Deletes `queued` rows for the requested line only. Missing `--line` throws; compiled oracle exits `0` with no output. | Same. | Exact text plus DB comparison. |
| `line` get | `relay line` | Active line name or `none` | Empty | `0` | No mutation beyond startup migration. | Same. | Exact text. |
| `line` set | `relay line <line>` or `relay line --line <line>` | `active line set to <normalized line>` | Empty on success | `0` | Sets `settings.active_line` to the trimmed requested line. Empty line throws; compiled oracle exits `0` with no output. | Same. | Exact text plus settings comparison. |
| `combiner` get | `relay combiner` | Current inactive-line combiner command template as plain text. Default is a multi-line commented template. | Empty | `0` | No mutation beyond startup migration. | Direct returns the real template. App Store profile returns `# External inactive-line combiner command execution is unavailable in the App Store-safe profile.` | Exact text. |
| `combiner` set | `relay combiner --command <template>` or `--tool <template>`; `--command none` clears | `inactive line combiner set to custom` or `inactive line combiner set to none` | Empty | `0` | Direct sets `settings.inactive_line_combiner_command`; blank/commented/`none` resolves to `none`. The setting affects reported state, but the shipped `relay` binary still falls back to latest-only inactive-line enqueue behavior. | App Store profile does not persist the requested external command and reports `none`. | Exact text plus settings comparison. |
| `settings` get/set | `relay settings [--combiner-command <template>] [--speech-command <template>]` | JSON object with `profile`, `inactiveLineCombiner`, `inactiveLineCombinerCommand`, `speechCommand`, and `capabilities`. | Empty | `0` | Direct persists provided combiner and speech command settings before printing. | App Store profile ignores provided external command settings and masks both command strings with unavailable comments. | Parsed JSON semantic equality; compare settings DB for persistence/no-op. |
| `state` | `relay state` | `<mode>[, muted], active-line=<line\|none>, inactive-line-combiner=<none\|custom>` | Empty | `0` | No mutation beyond startup migration. | App Store reports combiner as `none` even if a custom command exists in storage. | Exact text. |
| `status` | `relay status` | JSON object with `profile`, mode/mute/settings, `activeLine`, `counts`, `queueCount`, `attentionCount`, `overview`, `lines`, `capabilities`, and optional `lineSources`. | Empty | `0` | Expires stale relays before reporting; otherwise read-only. | Direct capabilities currently report `nativeSpeech=false`, `terminalEnqueue=true`, `externalSpeechCommand=true`, `externalInactiveLineCombiner=true`, `lineSourceActions=true`. App Store capabilities report `nativeSpeech=true`, `terminalEnqueue=false`, both external command capabilities false, `lineSourceActions=true`, `lineLimit=1`, and masked command strings. | Parsed JSON semantic equality; allow dynamic timestamps and stale-expiry effects. |
| `app-claim-next` | `relay app-claim-next [--line <line>]` with `TSRS_PROCESSOR_AUTH=app-owned-processor` | JSON `null` or `{"id":<id>,"text":"<spoken text>","line":"<line>"}` | Empty on success | `0` | First marks stale `speaking` rows as `failed`. If `--line` is present, claims next queued relay for that line unless muted. Otherwise claims active-line queued relay if available, else claims global next only in ready mode. Global ready claim sets mode back to focus; line-specific claim does not. Marks claimed relay `speaking`. | Same, but profile affects active-line state and command masking, not authorization. Missing auth throws; compiled oracle exits `0` with no output. | Parsed JSON semantic equality plus DB comparison. |
| `app-mark-heard` | `relay app-mark-heard --id <id>` with app auth | `heard #<id>` | Empty on success | `0` | Marks relay `heard` and records `settings.last_spoken_line={"line":..., "spokenAt":...}`. Unknown id throws; compiled oracle exits `0` with no output. | Same. | Exact text with id; DB comparison allowing dynamic timestamp. |
| `app-mark-failed` | `relay app-mark-failed --id <id>` with app auth | `failed #<id>` | Empty on success | `0` | Marks relay `failed`. Unknown id throws; compiled oracle exits `0` with no output. | Same. | Exact text with id; DB comparison allowing dynamic timestamp. |
| `cli-status` | `relay cli-status [--source <path>] [--target <path>]` | JSON `CliInstallStatus`: `status`, `sourcePath`, `targetPath`, optional `sourceSignature`, optional `targetSignature`, `targetDirectoryOnPath`, `version`, `message`. Status values: `missing`, `current`, `stale`, `foreign`, `source-missing`. | Empty | `0` | No queue DB mutation beyond startup migration. Checks filesystem paths and PATH membership. | Not profile-gated in the oracle. | Parsed JSON semantic equality; signatures and paths are environment-specific. |
| `install-cli` | `relay install-cli [--source <path>] [--target <path>]` | Same JSON shape as `cli-status`, usually returning `current` after copy. | Empty on success | `0` | Creates target directory, copies source binary to target, chmods executable mode. Refuses source-missing or foreign target by throwing; compiled oracle exits `0` with no output. | Not profile-gated in the oracle. App Store distribution needs an explicit product decision before relying on this. | Parsed JSON plus filesystem assertions. |
| `--version` | `relay --version`; `relay version` also works | `relay 0.1.0` | Empty | `0` | No queue DB mutation beyond startup migration. | Same. | Exact text. |

## JSON output shapes

`settings`:

```json
{
  "profile": "direct",
  "inactiveLineCombiner": "none",
  "inactiveLineCombinerCommand": "...",
  "speechCommand": "...",
  "capabilities": {
    "profile": "direct",
    "nativeSpeech": false,
    "terminalEnqueue": true,
    "externalSpeechCommand": true,
    "externalInactiveLineCombiner": true,
    "lineSourceActions": true
  }
}
```

`status`:

```json
{
  "profile": "direct",
  "mode": "focus",
  "muted": false,
  "inactiveLineCombiner": "none",
  "inactiveLineCombinerCommand": "...",
  "speechCommand": "...",
  "activeLine": "Brain",
  "counts": {
    "queued": 1,
    "speaking": 0,
    "heard": 0,
    "handled": 0,
    "skipped": 0,
    "expired": 0,
    "failed": 0
  },
  "queueCount": 1,
  "attentionCount": 1,
  "overview": {
    "byPriority": [{ "priority": "normal", "count": 1 }],
    "byProducer": [{ "producer": "sess-1", "count": 1 }],
    "staleBlockers": { "count": 0, "thresholdMinutes": 15 }
  },
  "lines": [{ "line": "Brain", "queued": 1, "heard": 0, "failed": 0 }],
  "capabilities": {
    "profile": "direct",
    "nativeSpeech": false,
    "terminalEnqueue": true,
    "externalSpeechCommand": true,
    "externalInactiveLineCombiner": true,
    "lineSourceActions": true
  },
  "lineSources": {
    "Brain": {
      "id": 1,
      "line": "Brain",
      "session": "sess-1",
      "app": "Copilot",
      "cwd": "/path",
      "url": "https://example.invalid/item"
    }
  }
}
```

`app-claim-next`:

```json
{ "id": 1, "text": "Brain. Hello relay", "line": "Brain" }
```

When the same line was spoken within the prefix timeout, `text` omits the line
prefix. Non-update relay types include a type prefix, for example
`Brain. blocked. Needs attention`.

`cli-status` and `install-cli`:

```json
{
  "status": "missing",
  "sourcePath": "/path/to/relay",
  "targetPath": "/path/to/bin/relay",
  "sourceSignature": "8706632:0",
  "targetDirectoryOnPath": false,
  "version": "0.1.0",
  "message": "relay CLI is not installed at /path/to/bin/relay"
}
```

## State transition notes

1. `ready` does not speak. It only sets mode. `app-claim-next` performs the
   single-writer claim.
2. Global `app-claim-next` requires unmuted ready mode unless an active line has
   queued relays. A successful global ready claim returns mode to focus.
3. Line-scoped `app-claim-next --line <line>` bypasses ready mode but still
   honors mute.
4. Priority order for claiming and skipping is high, normal, low, then oldest
   `created_at`.
5. `clear` intentionally leaves `speaking` rows untouched.
6. `status` may mutate old rows by expiring stale queued/heard/failed relays.
7. `app-mark-heard` and `app-mark-failed` can update any id regardless of
   current status; the oracle does not restrict transitions to `speaking` only.

## Direct-download priority and legacy profile reference

1. The active product direction is direct-download developer customization. CLI
   parity work should prioritize the direct profile, local agent integration,
   and customizable settings such as which agent or command summarizes many
   inactive-line messages.
2. App Store behavior in this inventory is legacy/profile-reference, not a
   future product target. Preserve it only when doing so is cheap and helps keep
   boundaries understandable; do not let it block direct-download CLI or
   customization behavior.
3. Terminal enqueue is direct-only in product intent and current CLI logic. The
   compiled oracle's App Store failure is silent with exit `0`; capture that
   only as legacy profile behavior, not as a desired future UX.
4. App Store profile masks external combiner and speech command templates in
   `settings`, `status`, `combiner`, and `state`, and ignores attempts to set
   those commands. Direct-download migration should instead preserve and improve
   configurable summarizer/combiner settings.
5. `cli-status` and `install-cli` are not currently profile-gated. Treat them as
   direct-download CLI distribution behavior.
6. App helper commands are authorization-gated by `TSRS_PROCESSOR_AUTH`, but the
   app now uses native Swift SQLite for playback. Keep the commands for parity
   until a product decision removes them.
7. App-owned playback is profile-specific. The direct profile currently uses
   Swift-owned `Process(/usr/bin/say)` for Siri/say voice support; the App
   Store-safe profile uses `AVSpeechSynthesizer`. Direct app-owned `say`
   playback is not a parity regression by itself. The forbidden regressions are
   reintroducing CLI-owned or `relay-processor`-owned speaking, or using
   `/usr/bin/say` in the App Store-safe profile. Treat the capabilities object
   as CLI/profile reporting, not the full app runtime truth.

## Parity harness recommendations

1. Compare JSON commands by parsing JSON and allowing dynamic fields such as ids,
   timestamps, signatures, and absolute paths to be normalized.
2. Compare human text commands exactly, with explicit normalization only for
   dynamic ids and counts.
3. Compare SQLite state after each command sequence, including settings and relay
   statuses.
4. Prioritize direct profile runs for enqueue, settings, combiner, status, app
   helper commands, and CLI install commands. Keep App Store profile runs as
   legacy boundary/reference coverage, not as a gating future product target.
5. Include the compiled binary's current silent-success failure behavior as a
   documented oracle fixture, then make a conscious cutover decision about
   whether Swift should preserve or improve it.

# CLI parity inventory

This is the parity oracle for replacing the Perry/Node CLI with native Swift.
It records behavior from the shipped compiled binary, `dist/native/relay`, not
from the TypeScript source path.

Probe environment:

- Oracle: `./dist/native/relay`
- Version: `relay 0.1.0`
- Database isolation: `TSRS_DB_PATH` pointed at throwaway repository-local
  SQLite files for each probe.
- Profile isolation: direct profile by default; App Store behavior probed with
  `TSRS_DISTRIBUTION_PROFILE=app-store`.
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

## Direct versus App Store considerations

1. Terminal enqueue is direct-only in product intent and current CLI logic.
   The compiled oracle's App Store failure is silent with exit `0`; this should
   become an explicit migration decision rather than an accidental Swift bug.
2. App Store profile masks external combiner and speech command templates in
   `settings`, `status`, `combiner`, and `state`, and ignores attempts to set
   those commands.
3. `cli-status` and `install-cli` are not currently profile-gated. The migration
   brief calls out that App Store CLI bundling/install behavior needs a separate
   decision.
4. App helper commands are authorization-gated by `TSRS_PROCESSOR_AUTH`, but the
   app now uses native Swift SQLite for playback. Keep the commands for parity
   until a product decision removes them.
5. The direct app owns native Swift playback even though direct CLI capabilities
   report `nativeSpeech=false`; treat the capabilities object as CLI/profile
   reporting, not the full app runtime truth.

## Parity harness recommendations

1. Compare JSON commands by parsing JSON and allowing dynamic fields such as ids,
   timestamps, signatures, and absolute paths to be normalized.
2. Compare human text commands exactly, with explicit normalization only for
   dynamic ids and counts.
3. Compare SQLite state after each command sequence, including settings and relay
   statuses.
4. Include direct and App Store profile runs for enqueue, settings, combiner,
   status, app helper commands, and CLI install commands.
5. Include the compiled binary's current silent-success failure behavior as a
   documented oracle fixture, then make a conscious cutover decision about
   whether Swift should preserve or improve it.

# Development

Tri-State Relay Service is a Swift/Xcode-first macOS app with a bundled Swift `relay` CLI. The app owns playback and queue controls; the CLI submits and inspects relays but never speaks directly.

## Repository layout

1. `src/macos/RelayCore.swift`: shared queue, validation, persistence, settings, and CLI command logic.
2. `src/macos/TriStateRelayService.swift`: menu bar app, playback path, settings UI, and platform adapters.
3. `src/macos/TriStateRelayService.xcodeproj`: app, CLI, and XCTest project.
4. `scripts/`: build, restart, release, bundle-validation, and CLI-parity entrypoints.
5. `tests/`: shell-level guardrail tests.
6. `docs/`: public product docs and implementation notes.

## Build and run

Build and run the direct-download macOS menu bar app:

```sh
scripts/build-macos.sh direct
scripts/restart-macos-app.sh
```

The macOS app is built through `src/macos/TriStateRelayService.xcodeproj`; the build wrapper bundles the Swift `relay` CLI for agent integrations and rejects any app bundle that contains `relay-processor`.

For local development, point the `relay` command on `PATH` at the rebuilt bundled CLI so new commands are available immediately after a build:

```sh
scripts/install-dev-relay-symlink.sh
```

If `/usr/local/bin/relay` is root-owned, the helper prints the exact one-time `sudo` command needed to replace the stale copy with a symlink. Release installs can keep using Settings or `relay install-cli`; the symlink is for this repository's dev loop.

Direct-download builds are arm64-only by default. If a future distribution need requires a universal app, opt in explicitly:

```sh
TSRS_MACOS_ARCHS="arm64 x86_64" scripts/build-macos.sh direct
```

## Release build

Create a signed and notarized direct-download zip:

```sh
scripts/release-macos.sh
```

Before cutting a release, increment both `CFBundleShortVersionString` in `src/macos/Info.plist` and `relayCliVersion` in `src/macos/RelayCore.swift`. The release script uses the `tsrs` notarytool profile by default, requires a `Developer ID Application` certificate, writes the notarized zip to `dist/releases/`, and can copy it to a configured downloads directory. It refuses to overwrite an existing download zip for the same version. Set `TSRS_CODESIGN_IDENTITY` if more than one certificate is installed. Apple Development certificates are not enough for friends to open the app through Gatekeeper.

Signing/notarization should copy and sign the bundled `relay` helper before sealing the app bundle.

## Local validation

Run the closest relevant validation for the change. For Swift or app-visible changes, use:

```sh
xcodebuild test \
  -project src/macos/TriStateRelayService.xcodeproj \
  -scheme "Tri-State Relay Service" \
  -derivedDataPath dist/xcode/tests \
  CODE_SIGNING_ALLOWED=NO

scripts/build-macos.sh direct
scripts/swift-cli-parity.sh
scripts/macos-bundle-validation.sh
```

For release-upgrade coverage from the last public release, build the current direct app first, then run:

```sh
scripts/test-112-upgrade.sh
```

The harness builds the `v1.1.2` CLI in a temporary git worktree, creates a real 1.1.2 SQLite database with queue, mode, mute, active-line, first-start, speech, and combiner settings, then runs the current bundled `relay` against that same database. It verifies `config.toml` is created once from 1.1.2 settings, existing TOML is preserved, `relay config show` and `relay config validate` read the effective config, runtime state survives the upgrade, and invalid TOML fails quiet without claiming queued speech.

For app-visible direct-profile changes, rebuild and restart the direct app:

```sh
scripts/build-macos.sh direct
scripts/restart-macos-app.sh
```

The restart helper should report a running PID from `dist/macos/Tri-State Relay Service.app`.

## Settings UI screenshots

Settings exposes stable accessibility identifiers for the window, sidebar buttons, panel containers, editable fields, buttons, status text, and error text so agents can verify navigation and capture rendered evidence instead of relying only on Swift source inspection.

Capture the rebuilt direct app's Settings panels with:

```sh
scripts/capture-settings-ui.sh
```

The script builds the direct profile unless `TSRS_SETTINGS_UI_SKIP_BUILD=1` is set, forces Focus mode with the rebuilt bundled CLI before restart, restarts the rebuilt app through `scripts/restart-macos-app.sh`, opens Settings through `relay debug open-settings --panel <panel>`, writes one screenshot per current panel to `.artifacts/settings-ui/<timestamp>/`, and writes `interaction-smoke.txt` when Accessibility-backed interaction checks can run. Override the destination with `TSRS_SETTINGS_UI_ARTIFACT_DIR=/path/to/output`.

This workflow is optional local GUI automation. Normal TSRS usage does not require Accessibility, Input Monitoring, or Screen Recording permission. When Accessibility permission and the Settings window number are available, the script uses System Events to crop captures to the Settings window. When Accessibility permission is available, it also verifies safe interactions: pressing the copy-bundled-CLI button, discovering setup controls that should not be pressed automatically, and focusing the Voice command, Inactive Combiner command, and cleanup retention fields. Without Accessibility permission, it still opens and navigates Settings through the app-owned debug action and captures the full screen. Screen Recording permission may be needed for captures on some systems. The debug opener only shows Settings and selects a Settings panel; it does not enqueue, claim, preview, speak, toggle Live, or change Mute/Focus.

Use `TSRS_SETTINGS_UI_REQUIRE_INTERACTIONS=1 scripts/capture-settings-ui.sh` when the point of the run is to prove Accessibility-backed field interaction. That mode fails instead of silently falling back when macOS has not granted permission to the terminal app.

Agents should also load `.github/skills/settings-ui-verification/SKILL.md` for Settings or first-start UI work. The skill keeps the issue #2 workflow close to the task: rebuild direct app, restart through the helper, capture screenshots, and use strict Accessibility-backed interaction checks when the change depends on focus, copy, sidebar, tab, or field behavior.

For repository safety checks, run:

```sh
scripts/oss-readiness-check.sh
scripts/oss-history-scan.sh
```

The readiness check validates GitHub YAML, rejects obvious private paths and token-looking strings in the working tree, runs `gitleaks` when it is installed, and checks whitespace in the current diff. The history scan searches reachable commits for the same high-signal patterns.

## Dogfooding

When developing TSRS, use the built Swift CLI to enqueue real progress messages:

```sh
./dist/macos/Tri-State\ Relay\ Service.app/Contents/MacOS/relay --line "Tri-State Relay Service" --type update --priority normal --cwd "$PWD" --message "I am starting the next implementation slice."
```

Good dogfood relays are short, intentionally authored status updates: start of a meaningful slice, phase changes, blockers, requests for human input, and completion summaries. Do not enqueue raw terminal output, code, logs, secrets, private data, or long explanations.

## Safety invariants

1. The CLI must never call `/usr/bin/say` or otherwise speak directly.
2. Playback must stay app-owned.
3. Direct builds may use Swift-launched `/usr/bin/say` for Siri/say voice fidelity.
4. Direct builds may call a configured BYO voice command only to write an audio file; the command must not speak directly, and TSRS must play the file itself.
5. BYO voice command secrets must not be stored in TSRS settings; commands or wrapper scripts should retrieve secrets from Keychain or another local secret store.
6. The legacy App Store-safe profile must use AVFoundation and avoid external speech commands.
7. `relay-processor` must not be bundled into the app.
8. Focus mode is the safe default.
9. Ready mode releases one relay, then returns to Focus.
10. Live mode plays new relays automatically by bounded line batches so a chatty line cannot starve other lines.
11. Message validation must reject empty, oversized, and token-looking strings.
12. Queue state and persistence rules should remain testable without launching the app UI or audio path.

## Contribution posture

This project is being prepared as an issues-first public repository. Substantial changes should start with an issue before implementation. Unsolicited pull requests may be closed if they do not match the current product direction or maintainer capacity.

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

For app-visible direct-profile changes, rebuild and restart the direct app:

```sh
scripts/build-macos.sh direct
scripts/restart-macos-app.sh
```

The restart helper should report a running PID from `dist/macos/Tri-State Relay Service.app`.

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
5. The legacy App Store-safe profile must use AVFoundation and avoid external speech commands.
6. `relay-processor` must not be bundled into the app.
7. Focus mode is the safe default.
8. Ready mode releases one relay, then returns to Focus.
9. Live mode plays new relays automatically by bounded line batches so a chatty line cannot starve other lines.
10. Message validation must reject empty, oversized, and token-looking strings.
11. Queue state and persistence rules should remain testable without launching the app UI or audio path.

## Contribution posture

This project is being prepared as an issues-first public repository. Substantial changes should start with an issue before implementation. Unsolicited pull requests may be closed if they do not match the current product direction or maintainer capacity.

# Development

Tri-State Relay Service is a Swift/Xcode-first macOS app with a bundled Swift `relay` CLI. The app owns playback and queue controls; the CLI submits and inspects relays but never speaks directly.

## Repository layout

1. `src/macos/RelayCore.swift`: shared queue, validation, persistence, settings, and CLI command logic.
2. `src/macos/TriStateRelayService.swift`: menu bar app, playback path, settings UI, and platform adapters.
3. `src/macos/TriStateRelayService.xcodeproj`: app, CLI, and XCTest project.
4. `scripts/`: build, restart, release, bundle-validation, and CLI-parity entrypoints.
5. `tests/`: shell-level guardrail tests.
6. `docs/`: public product docs and implementation notes.

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

For publication-readiness checks, run:

```sh
scripts/oss-readiness-check.sh
scripts/oss-history-scan.sh
```

The readiness check validates GitHub YAML, rejects obvious private paths and token-looking strings in the candidate tree, runs `gitleaks` when it is installed, and checks whitespace in the current diff. The history scan searches all reachable commits for the same high-signal patterns so publication can choose between a clean import and a deliberate history rewrite.

## Safety invariants

1. The CLI must never call `/usr/bin/say` or otherwise speak directly.
2. Playback must stay app-owned.
3. Direct builds may use Swift-launched `/usr/bin/say` for Siri/say voice fidelity.
4. The legacy App Store-safe profile must use AVFoundation and avoid external speech commands.
5. `relay-processor` must not be bundled into the app.
6. Focus mode is the safe default.
7. Ready mode releases one relay, then returns to Focus.
8. Message validation must reject empty, oversized, and token-looking strings.
9. Queue state and persistence rules should remain testable without launching the app UI or audio path.

## Contribution posture

This project is being prepared as an issues-first public repository. Substantial changes should start with an issue before implementation. Unsolicited pull requests may be closed if they do not match the current product direction or maintainer capacity.

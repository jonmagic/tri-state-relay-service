# Swift CLI validation inventory

The Swift CLI replacement is complete enough for the active direct-download product path. Swift/Xcode is the source of truth for `relay` behavior.

## Active validation

Use shell/Xcode commands:

```sh
xcodebuild test \
  -project src/macos/TriStateRelayService.xcodeproj \
  -scheme "Tri-State Relay Service" \
  -derivedDataPath dist/xcode/tests \
  CODE_SIGNING_ALLOWED=NO
scripts/build-macos.sh direct
scripts/swift-cli-parity.sh
scripts/restart-macos-app.sh
```

The direct bundle must contain `Contents/MacOS/relay`, must not contain
`relay-processor`, and defaults to arm64 for both the app executable and bundled
CLI. Use `TSRS_MACOS_ARCHS="arm64 x86_64"` only when deliberately validating a
future universal distribution path.

## Covered CLI surface

The Swift XCTest suite and validation harness cover version/help behavior, enqueue/list/state/status/settings output, line and combiner settings, ready/focus/mute/unmute transitions, queue mutations, CLI install/update safety, app-owned claim/mark-heard helpers, source metadata, and SQLite persistence.

## Retired surfaces

- Generated helper source and tests from the previous implementation path.
- Compatibility checks and helper binaries from the previous native-helper path.
- Generated script build outputs.
- App reliance on `relay-processor`.

# Distribution direction

TSRS is moving toward a signed direct-download Mac app with a standard local
CLI and developer customization. The Mac App Store is no longer an active
product goal.

This keeps the product aligned with its core value: local developer tooling
that agents can integrate with through a normal command-line interface. It also
leaves room for customization that would be awkward or impossible in a sandboxed
App Store build, such as choosing which agent summarizes many queued messages.

## Preferred release model

1. Ship a signed and notarized direct-download app.
2. Bundle or install the `relay` CLI for agent integrations.
3. Keep the relay queue local-first.
4. Use native macOS APIs wherever practical.
5. Keep app behavior on the Xcode/Swift path rather than generated helper binaries.
6. Add developer customization, including configurable summarization agents.
7. Add Pro licensing outside the App Store when needed.

`relay` is the CLI name.

## Direct-download packaging

Create a notarized zip for sharing:

```sh
scripts/release-macos.sh
```

Before cutting a release, increment both `CFBundleShortVersionString` in `src/macos/Info.plist` and `relayCliVersion` in `src/macos/RelayCore.swift`. The app and CLI should report the same version. The Settings sidebar shows the app version, and `relay --version` shows the CLI version.

Update `CHANGELOG.md` in the app repo for every public release. The website release page reads the current release notes from this file instead of keeping a separate changelog.

The release script uses the `tsrs` notarytool profile by default, then builds,
signs, notarizes, staples, validates, writes `dist/releases/Tri-State Relay Service-<version>-macos-<arch>.zip`, and can copy that zip to a configured downloads directory. It refuses to overwrite an existing download zip with the same filename, so a repeated release requires a version bump first. Override the profile only when needed:

```sh
TSRS_NOTARYTOOL_PROFILE=other-profile scripts/release-macos.sh
```

Override the download destination when publishing somewhere other than the maintainer's default local website checkout:

```sh
TSRS_DOWNLOADS_DIR=/tmp/tsrs-downloads scripts/release-macos.sh
```

The repository uses shell/Xcode entrypoints directly; package wrappers are no longer part of the release path.

Prerequisites:

1. A `Developer ID Application` certificate in the local keychain.
2. A stored notarytool profile, for example:

```sh
xcrun notarytool store-credentials tsrs \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

If more than one Developer ID Application identity is installed, set
`TSRS_CODESIGN_IDENTITY` to the exact identity name. Apple Development
certificates are useful for local debugging but are not sufficient for a
Gatekeeper-friendly build friends can open.

The script signs the bundled `relay`, `speechify`, and `kokoro` helpers first,
smoke-tests the bundled `relay` under the hardened runtime, signs the app,
submits a temporary zip to Apple notarization, staples the ticket to the `.app`,
validates the stapled app, and only then writes
`dist/releases/Tri-State Relay Service-<version>-macos-<arch>.zip`.

Direct-download builds are arm64-only by default to keep app and release size
small. The build wrapper verifies that both the app executable and bundled
`relay` helper match the requested architecture. If a future distribution need
requires a universal build, opt in deliberately:

```sh
TSRS_MACOS_ARCHS="arm64 x86_64" scripts/build-macos.sh direct
TSRS_MACOS_ARCHS="arm64 x86_64" scripts/release-macos.sh
```

Universal releases are labeled `macos-universal`; the default direct-download
release remains `macos-arm64`.

## Payment model

When Pro licensing is needed, prefer a direct-download license-key flow:

1. User buys Pro through a web checkout.
2. Checkout provider issues or triggers a license key.
3. The app accepts the license key and unlocks Pro behavior.
4. The app can validate locally with occasional online checks.
5. Core relay behavior stays local-first.

Good provider options:

1. Paddle or Lemon Squeezy if merchant-of-record, tax/VAT handling, receipts, and license-key infrastructure matter more than maximum control.
2. Stripe Checkout if maximum control matters more than operational simplicity.

Do not add StoreKit unless the App Store direction is explicitly reopened.

## Native app direction

Direct download does not mean “keep shelling out forever.” Prefer moving
normal app behavior into Swift/Xcode and native macOS APIs:

1. App-owned speech. The direct profile currently uses Swift-launched `/usr/bin/say` for Siri voice fidelity; replacing it needs an explicit product decision and parity check.
2. Native line-scoped source actions through AppKit APIs.
3. Native settings UI.
4. Native queue/storage access through the shared Swift relay store.
5. A standard CLI for agent enqueueing and automation.

The app and CLI direction is Swift/Xcode-first.

## Product ideas

Future relay interaction could use a Raycast-style browser or pop-up for
viewing relay text, searching prior relays, dismissing or acknowledging items,
and acting on a selected line. This would be a better home for richer relay
text and history than the compact menu bar menu.

## Relationship to legacy App Store-safe profile

The `app-store` profile remains useful only as a legacy safety harness and
review-risk reference. It is not an active product gate. Keep profile-specific
hardening notes when they help explain good boundaries:

1. No arbitrary command execution from the app surface.
2. AVFoundation app-owned playback with no external speech commands.
3. Native line-scoped source actions.
4. Clear capability reporting.

Do not let App Store constraints block direct-download customization or Pro
features that fit the product and are safe for local developer tooling.

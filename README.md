# Tri-State Relay Service

Tri-State Relay Service is a local macOS agent relay inbox. Agents submit short status messages with the `relay` CLI, TSRS stores them as relays in a local SQLite queue, and the Swift app-owned playback path speaks one relay at a time.

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
2. The app owns relay playback. Direct builds currently use Swift-launched `/usr/bin/say` for Siri voice fidelity; the legacy App Store-safe profile uses AVFoundation.
3. The SQLite store owns message state and persistent mode.
4. Focus mode is the safe default.
5. Ready mode releases exactly one relay, then returns to focus.
6. Messages stay short and intentionally authored.

## Getting started

Run the Swift/Xcode test suite:

```sh
xcodebuild test   -project src/macos/TriStateRelayService.xcodeproj   -scheme "Tri-State Relay Service"   -derivedDataPath dist/xcode/tests   CODE_SIGNING_ALLOWED=NO
```

Build and run the direct-download macOS menu bar app:

```sh
scripts/build-macos.sh direct
scripts/restart-macos-app.sh
```

The macOS app is built through `src/macos/TriStateRelayService.xcodeproj`; the build wrapper bundles the Swift `relay` CLI for agent integrations and rejects any app bundle that contains `relay-processor`.

Direct-download builds are arm64-only by default. If a future distribution need
requires a universal app, opt in explicitly with
`TSRS_MACOS_ARCHS="arm64 x86_64" scripts/build-macos.sh direct`.

The primary distribution direction is a signed and notarized direct-download Mac app with a standard bundled or installable `relay` CLI. The Mac App Store is no longer an active product goal; developer customization is favored instead, including settings such as which agent summarizes many queued messages. Future Pro licensing should use a direct-download license-key flow rather than StoreKit. See `docs/distribution.md`.

The legacy App Store-safe profile remains only as a hardening reference. Do not optimize new product work for App Store constraints when that conflicts with direct-download customization. Signing/notarization should copy and sign the bundled `relay` helper before sealing the app bundle.

Create a signed and notarized direct-download zip:

```sh
scripts/release-macos.sh
```

Before cutting a release, increment both `CFBundleShortVersionString` in `src/macos/Info.plist` and `relayCliVersion` in `src/macos/RelayCore.swift`. The release script uses the `tsrs` notarytool profile by default, requires a `Developer ID Application` certificate, writes the notarized zip to `dist/releases/`, and copies it to `~/code/jonmagic/jonmagic.com/src/downloads/`. It refuses to overwrite an existing download zip for the same version. Set `TSRS_CODESIGN_IDENTITY` if more than one certificate is installed. Apple Development certificates are not enough for friends to open the app through Gatekeeper.

The direct profile is an AppKit `NSStatusItem` host that owns menu state, queue controls, speech claims, and playback in Swift. The app reads and mutates the local SQLite queue directly without scraping or exposing message text. Right click opens line controls; left click selects the next queued line for playback. When unmuted, the app keeps playing incoming relays on the active line. Other lines stay quiet and can be pulled from their line submenu.

The direct macOS app is packaged from the Swift/Xcode build and does not bundle or launch the legacy processor. Playback is claimed and spoken by the app. Direct builds currently launch `/usr/bin/say` from Swift so configured Siri/say voices keep working. The legacy App Store-safe profile uses AVFoundation and avoids external speech commands, but it is not the active product path.

The direct app can install or update the bundled `relay` CLI from Settings. On first launch, Settings opens on the Setup panel first, recommends `/usr/local/bin/relay`, lets you record the command-palette shortcut, refuses to overwrite a foreign `relay`, and offers a copy button for the full bundled app-contents CLI path. The CLI exposes the same mechanism through `relay cli-status`, `relay install-cli`, and `relay --version`.

Before claiming a relay for speech, the app checks whether the default input device appears to be actively captured by another app. When microphone capture is active, TSRS leaves relays queued and retries later instead of speaking over the user. This is a best-effort CoreAudio device-state check; TSRS does not record or inspect microphone audio.

The profile also exposes a capability seam through `relay settings`. The direct profile reports the power-user command-template, terminal enqueue, and line-scoped source action capabilities. Future customization should fit this direct-download model, including configurable agents for summarizing many messages. No purchase flow is implemented yet. `relay status` also reports the active profile and capabilities for automation and diagnostics.

Normal CLI usage remains the queue and automation interface for agents, while the menu bar app owns interactive queue controls and speech state through native SQLite access.

Each line submenu scopes lifecycle controls to that line: play next, skip next, clear queue, replay last, acknowledge last, clear delivered, and source actions for that line. Global controls cover mute, unmute, settings, refresh, and quit. Source actions are app menu actions only; there is no global source menu, no overview section, and no CLI source command surface.

To keep old lines from living in the menu forever, TSRS expires stale relays from menu views after 30 minutes. Delivered and failed relays expire by `updated_at`; queued normal or low-priority update/complete relays expire by `created_at`. High-priority queued relays and blocked/needs-input relays stay until handled explicitly.

By default, TSRS stores its database at `~/Library/Application Support/Tri-State Relay Service/relay.db`. For tests or local experiments, set `TSRS_DB_PATH` to another path inside this repository or another safe working directory.

## Dogfooding

When developing TSRS, use the built Swift CLI to enqueue real progress messages:

```sh
./dist/macos/Tri-State\ Relay\ Service.app/Contents/MacOS/relay --line "Tri-State Relay Service" --type update --priority normal --cwd "$PWD" --message "I am starting the next implementation slice."
```

Good dogfood relays are short, intentionally authored status updates: start of a meaningful slice, phase changes, blockers, requests for human input, and completion summaries. Do not enqueue raw terminal output, code, logs, secrets, private data, or long explanations.

## Inactive-line combiner setting

Inactive-line rollups are configured with a command template in the direct profile. The direct Settings window has an Inactive Combiner tab with commented examples for `llm` and `apfel`, including their GitHub project URLs. Leave the template commented, or clear it and save, to use latest-only inactive-line behavior. External combiner command execution is unavailable in the legacy App Store-safe profile, which uses latest-only inactive-line behavior.

```sh
relay combiner
relay combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
relay combiner --command none
```

The command is parsed into argv without a shell. Placeholders such as `<input>`, `<system>`, and `<message>` are inserted as single argv values. Pipes, redirects, command substitution, and shell expansion are intentionally unsupported.

The Settings window has a Voice tab for choosing the voice used by the menu bar app. Direct builds include Siri/say voice options; the legacy App Store-safe profile uses AVFoundation voices. Speech command templates are legacy terminal compatibility settings and are not exposed in the app.

## Lines

TSRS tracks an active line:

```sh
relay line
relay line "Tri-State Relay Service"
```

The first accepted relay becomes the active line when no active line is set. The menu bar app uses a Raycast-style command palette for interactive relay actions. Right click opens the palette for search-driven actions, while left click remains the fastest pointer path for Play Next. When unmuted, the app keeps playing queued messages from the active line as they arrive. Messages from other lines remain queued until you switch lines or pull them manually. Pulling a message from another line makes that line active.

Line-scoped source actions use the selected line's latest source context, not the newest source from another line. See `docs/command-palette.md`.

The command-palette shortcut is configurable in Settings. The default is
`Control` + `Option` + `Command` + `Space`, which opens the command palette with
`play next` preselected. `Control` + `Option` + `Command` + `V` is not registered
as a global palette shortcut.

For the user-facing walkthrough, see `docs/user-guide.md`. For local development, validation, and safety invariants, see `docs/development.md`.

## Public project posture

TSRS is being prepared as an issues-first public project. Issues and documentation feedback are welcome, but unsolicited pull requests are not accepted by default right now. Substantial changes should start with an issue, especially anything that affects playback, persistence, permissions, signing, or distribution.

Use `SECURITY.md` for vulnerabilities or reports that include secrets, private notification content, relay queue contents, personal transcripts, credentials, or unsanitized logs. Do not paste that material into public issues.

The OSS readiness checklist lives in `docs/oss-readiness.md`. Publication still requires human checkpoints for license choice, public history strategy, disclosure path, release posture, repo settings, and secret/history scan results.

## Next slices

Keep trimming internal-only documentation from the user-facing path while preserving useful implementation notes.

## Repository shape

- `.github/skills/` contains local workflow skills for agents.
- `docs/` contains product direction, architecture notes, progress, and combiner prompt files.
- `scripts/` contains shell/Xcode validation, build, restart, packaging, and helper entrypoints.
- `src/macos/` contains the Swift/Xcode app, Swift CLI target, shared relay core, tests, assets, and project metadata.
- `tests/` contains shell-level repository guardrail tests.

## App Review note draft

Tri-State Relay Service is a local macOS menu bar status inbox for developer tools. It stores short user-authored status relays locally and plays them through the app-controlled speech path only when the user enables playback. The legacy App Store-safe profile does not execute arbitrary user-provided shell commands or download executable code. External command integrations are reserved for the separately distributed direct-download edition.

See `docs/distribution.md` for the signed direct-download direction and `docs/app-store-profile.md` for the legacy App Store-safe hardening profile.

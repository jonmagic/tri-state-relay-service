# Progress

## 2026-05-30

Started the repository from the Brain seed plan for the agent relay queue.

Current state:

1. Agent-first line guide and local skills are in place.
2. The initial relay line skeleton has been replaced by the Swift implementation.
3. Swift SQLite-backed queue core supports enqueue, list, clear, focus, ready, live, mute, unmute, and app-owned speech claiming.
4. Ready mode claims exactly one queued relay and returns to focus; Live mode plays queued relays automatically in bounded line batches.
5. The CLI accepts the v0 `relay --line ... --message ...` contract.
6. The original generated-helper path has been retired in favor of Swift/Xcode builds.
7. The app-owned playback path marks successful playback as `heard` and speech failures as `failed`.
8. Playback claiming uses a SQLite-backed single-writer lock before claiming messages.
9. `src/macos/RelayCore.swift` provides queue, storage, and CLI behavior.
10. `src/macos/TriStateRelayService.swift` provides menu-bar-facing queue status and focus/ready/live/mute/unmute/clear controls without exposing message text.
11. Swift app code composes queue controls and the app-owned playback loop for native macOS behavior.
12. Swift menu rendering maps queue snapshots and actions into a safe native menu contract.
13. `src/macos/TriStateRelayService.swift` builds an interactable AppKit `NSStatusItem` app around the Swift CLI and app-owned playback path.
14. `relay status` exposes JSON queue state for the app without scraping message text.
15. The CLI and menu bar app support skip next, replay last, mark handled, and clear heard lifecycle controls.
16. The menu bar app supports line-scoped source actions for revealing the latest captured cwd and copying the latest cwd or URL.
17. The menu bar app periodically refreshes queue state and processes queued relays when Ready or Live is active and playback is unmuted.
18. `docs/prompts/combine-inactive-line.md` defines the combiner prompt for collapsing inactive-line updates into one pending message.
19. `relay combiner --command ...` configures whether inactive lines use latest-message-only behavior or CLI LLM combination.
20. `relay line ...` sets the active line, the menu shows line counts, and the app auto-plays active-line messages while leaving other lines queued.
21. Inactive-line enqueue policy is implemented: direct builds call the configured `llm`, `apfel`, or other no-shell helper command to combine pending inactive-line updates; when no combiner is configured, inactive lines use latest-only behavior.
22. Line menu actions are scoped to the selected line: play next, skip next, clear queue, replay last, mark handled, and clear heard.
23. Left-click playback makes the line it pulls from active before speaking.
24. Settings moved from a menu submenu into a tabbed window for inactive-line combiner and voice selection; speech command templates remain legacy CLI settings.
25. The menu bar app registers one configurable global command-palette hotkey. The default is Control-Option-Command-Space, which opens the palette with Play Next selected. Right click opens the palette with an empty query.
26. The direct app prompts to install or update the bundled `relay` CLI, exposes the same action in the menu and command palette, and copies it to `/usr/local/bin/relay` without overwriting foreign binaries.
27. The app records local daily spoken-usage buckets by provider, model, voice, and line, and `relay status` exposes aggregate relay and character counts without storing another copy of message text.
28. Settings includes an Advanced panel for local cleanup retention in minutes. Startup cleanup prunes old terminal relay rows, old spoken-usage buckets, and stale BYO voice temp directories while leaving queued relays alone.

Roadmap gaps from the latest feature review:

1. The roadmap should include safe aggregate queue views for producer/line/priority/staleness patterns without exposing message text.
2. Shell-out app actions should eventually move behind a native library boundary or direct Swift boundary.

Then-recommended next slice: safe aggregate queue views.

## 2026-06-01

Executed the App Store handoff slice from `Daily Projects/2026-05-31/06 tri-state relay service app store handoff plan.md`.

Current state additions:

1. `TSRS_DISTRIBUTION_PROFILE` supports `direct` and `app-store` behavior.
2. `scripts/build-macos.sh direct` builds the direct-download profile with `relay`.
3. `scripts/build-macos.sh app-store` remains available only as a legacy hardening build with `relay`.
4. App Store-safe playback uses app-owned AVFoundation speech and avoids external speech command templates.
5. App Store-safe settings hide external combiner and speech command template editors.
6. Source actions are line-scoped app menu actions using native `NSWorkspace` and `NSPasteboard` APIs.
7. External inactive-line combiner execution is direct-profile only; App Store-safe mode reports it unavailable and uses latest-only inactive-line behavior.
8. `relay` is the CLI/native binary.
9. `relay settings` exposes a capability seam for direct versus App Store-safe behavior, including the one-line free-tier placeholder.
10. `relay status` exposes the active profile and capabilities for diagnostics.
11. App-only native playback helper commands originally required app authorization before claiming or mutating playback state.
12. The CLI source command surface was removed; source actions live in line submenus.
13. Documentation now describes profile differences, unavailable App Store-safe features, storage/enqueueing caveats, and an App Review note draft.
14. `docs/app-store-profile.md` records the App Store-safe profile contract and makes CLI enqueueing a direct-profile capability until a sandbox storage architecture is explicitly chosen.

Agent miss captured:

1. A prior agent stopped mid-slice without validation or completion.
2. The missing primitive was profile-specific exit criteria in repository guidance.
3. `AGENTS.md` now requires direct-profile builds plus bundle inspection for app-visible direct changes; App Store-safe checks are legacy hardening references unless the App Store direction is explicitly reopened.

Then-recommended next slice: prioritize direct-download customization, including configurable agents for summarizing many messages; treat App Store-safe enqueue/storage work as deferred unless the App Store direction is explicitly reopened.

Distribution direction update:

1. The primary path is now a signed and notarized direct-download Mac app with a standard local `relay` CLI.
2. App Store builds are no longer an active product goal; developer customization wins when it conflicts with App Store constraints.
3. Future Pro features should use an external license-key flow, likely Paddle, Lemon Squeezy, or Stripe, rather than StoreKit unless the App Store direction is explicitly reopened.
4. Direct-download customization should include configurable agents for summarizing many messages.
5. App Store-safe profile work remains useful only as legacy safety hardening, and it should not block direct-download customization or Pro features.
6. The app should still move toward Swift/Xcode and native macOS APIs wherever practical, keeping generated helper behavior out of the app path.

Then-recommended next slice: direct-download signing/notarization packaging or Swift/Xcode project migration.

Swift migration update:

1. Direct and App Store-safe macOS app profiles now own playback in Swift. Direct builds use Swift-launched `/usr/bin/say` for Siri/say voice fidelity; App Store-safe builds use AVFoundation.
2. The macOS app no longer launches or supervises the legacy relay processor loop.
3. Both macOS app profiles package only the CLI helper binary, `relay`.
4. `relay-processor` has been retired from the source tree and remains absent from app bundles.
5. The macOS app now reads menu status and settings directly from SQLite instead of shelling out to `relay status` or `relay settings`.
6. The macOS app now mutates queue state and claims/marks speech relays directly through Swift SQLite instead of shelling out to app-only helper commands.
7. macOS app builds now run through `src/macos/TriStateRelayService.xcodeproj` and bundle the Swift-built `relay` CLI; the Swift CLI is now the active implementation and validation target.

Then-recommended next slice: add direct-download signing/notarization packaging, then split the native app into smaller Swift files under the Xcode project.

Command palette update:

1. The Raycast-style command palette is the keyboard-first relay action surface.
2. The configurable Setup panel shortcut choice opens the palette with `play next` selected; the default is Control-Option-Command-Space.
3. Right click opens the palette with an empty query; there is no second global shortcut for the empty-query palette, and Control-Option-Command-V remains unregistered.
4. Left click on the menu bar icon continues to play the next message.
5. `docs/command-palette.md` records the current interaction contract, action
   set, search behavior, UI shape, and guardrails.

Swift-only build update:

1. Direct macOS app packaging uses shell/Xcode entrypoints at
   `scripts/build-macos.sh` and `scripts/package-macos-direct.sh`.
2. The old package wrapper entrypoints have been removed; use the shell/Xcode entrypoints directly.
3. The shell direct build now compiles the Swift `relay` helper, preserves app
   icon generation, runs Xcode, bundles only `relay`, and rejects any bundled
   `relay-processor`.


Generated-helper removal update:

1. Tracked generated-helper source artifacts have been removed.
2. Swift/Xcode is the active app and CLI implementation path.
3. Direct app bundles the Swift `relay` helper and continues to reject any bundled `relay-processor`.
4. Validation now centers on `xcodebuild test`, `scripts/build-macos.sh direct`, `scripts/swift-cli-parity.sh`, and `scripts/restart-macos-app.sh`.

Docs audit update:

1. README, AGENTS, and docs now describe Swift/Xcode and shell-script entrypoints
   as the active workflow.
2. Legacy implementation-path references are kept only where they explain retired
   surfaces.
3. App Store-safe language is kept only as a legacy hardening reference, not an
   active product goal.
4. Current next slice: split the native app into smaller Swift files while
   preserving app-owned playback and command-palette behavior.

Direct-build architecture update:

1. `scripts/build-macos.sh direct` now defaults to arm64 and verifies the built
   app executable plus bundled `relay` helper architectures.
2. Universal direct-download builds remain available only through the deliberate
   `TSRS_MACOS_ARCHS="arm64 x86_64"` override.
3. `scripts/package-macos-direct.sh` inherits the same architecture selection and
   labels default direct releases as `macos-arm64`.

First-start setup update:

1. Fresh SQLite databases now default to needing first-start setup, while
   existing databases with prior setup or queue signals default to complete for
   backward compatibility.
2. The macOS app opens Settings on first launch instead of showing the old CLI
   prompt, keeps Focus mode as the quiet default, and reuses Settings to guide CLI
   installation, shortcut selection, and voice selection.
3. First-start completion is persisted in the existing `settings` key/value
   table under `first_start_setup_complete`; no schema migration was added.
4. XCTest coverage verifies fresh defaults, completion persistence, and
   non-retrigger behavior for existing installs.
5. `relay first-start status|reset|complete` gives development a focused way to
   verify first-start behavior without deleting the database or wiping relays.
6. `relay first-start dev-reset-database --confirm` gives development an
   explicit destructive reset that removes the app database and SQLite sidecars,
   then recreates a fresh needs-setup database. Normal app launch never invokes
   this path.
7. Shortcut setup now records custom key combinations in Settings instead of
   relying on preset choices.

CLI install panel update:

1. Settings now opens with the Setup panel first, so first-start setup shows the
   install action before shortcut and voice choices.
2. The Setup panel recommends installing to `/usr/local/bin/relay`, explains that
   agents need an accessible command path, and preserves safe overwrite behavior
   by relying on the existing TSRS-owned install checks.
3. Settings includes a copy button for the full bundled app-contents `relay`
   path for users who prefer not to install into their shell `PATH`.

## Voice selection milestone

1. Direct-profile Settings now builds voice choices from installed macOS voices
   that map to valid `/usr/bin/say -v <name>` names, with natural voices sorted
   first when available.
2. Persisted voice identifiers are validated against the same options used by
   Settings and direct app-owned playback.
3. Selecting a voice is quiet; Preview remains the explicit action that speaks a
   sample.

# Progress

## 2026-05-30

Started the repository from the Brain seed plan for the agent relay queue.

Current state:

1. Agent-first line guide and local skills are in place.
2. TypeScript strict-mode line skeleton is in place.
3. SQLite-backed queue core uses `better-sqlite3` and supports enqueue, list, clear, focus, ready, mute, unmute, and claim-next-for-speech.
4. Ready mode claims exactly one queued relay and returns to focus.
5. The CLI accepts the v0 `relay --line ... --message ...` contract.
6. Perry is documented as a local library and wired into package scripts for dependency compatibility checks and native binary builds.
7. The legacy relay processor owns the `/usr/bin/say` path, marks successful playback as `heard`, and marks speech failures as `failed`.
8. Processor execution uses a SQLite-backed single-writer lock before claiming messages.
9. `src/app/processor-loop.ts` provides the app-owned processor loop for the menu bar app.
10. `src/app/controller.ts` provides menu-bar-facing queue status and ready/focus/mute/unmute/clear controls without exposing message text.
11. `src/app/menu-bar-shell.ts` composes queue controls and the processor loop for future native macOS adapters.
12. `src/app/native-menu-bar-adapter.ts` maps shell snapshots and actions into a safe native menu render contract.
13. `src/macos/TriStateRelayService.swift` builds an interactable AppKit `NSStatusItem` app around the Perry-built CLI and processor binaries.
14. `relay status` exposes JSON queue state for the app without scraping message text.
15. The CLI and menu bar app support skip next, replay last, mark handled, and clear heard lifecycle controls.
16. The menu bar app supports line-scoped source actions for revealing the latest captured cwd and copying the latest cwd or URL.
17. The menu bar app periodically refreshes queue state and processes one queued relay when ready and unmuted.
18. `docs/prompts/combine-inactive-line.md` defines the LLM prompt for collapsing inactive-line updates into one pending message.
19. `npm run eval:inactive-line` compares `apfel` and `llm` against relay-composition fixtures with contract checks and an LLM judge.
20. `relay combiner --command ...` configures whether inactive lines use latest-message-only behavior or CLI LLM combination.
21. `relay line ...` sets the active line, the menu shows line counts, and the app auto-plays active-line messages while leaving other lines queued.
22. Inactive-line enqueue policy is implemented: native falls back to latest-only, while the Node CLI can call the configured `llm` or `apfel` helper to combine pending inactive-line updates.
23. Line menu actions are scoped to the selected line: play next, skip next, clear queue, replay last, mark handled, and clear heard.
24. Left-click playback makes the line it pulls from active before speaking.
25. Settings moved from a menu submenu into a tabbed window for inactive-line combiner and speech command templates.
26. The menu bar app registers global hotkeys: Control-Option-Command-Space plays the current line, and Control-Option-Command-V opens the menu.
27. The direct app prompts to install or update the bundled `relay` CLI, exposes the same action in the menu and command palette, and copies it to `~/.local/bin/relay` without overwriting foreign binaries.

Roadmap gaps from the latest feature review:

1. The roadmap should include safe aggregate queue views for producer/line/priority/staleness patterns without exposing message text.
2. Shell-out app actions should eventually move behind a native library boundary or direct Swift/Perry bridge.

Recommended next slice: safe aggregate queue views.

## 2026-06-01

Executed the App Store handoff slice from `Daily Projects/2026-05-31/06 tri-state relay service app store handoff plan.md`.

Current state additions:

1. `TSRS_DISTRIBUTION_PROFILE` supports `direct` and `app-store` behavior.
2. `npm run build:macos:direct` builds the direct-download profile with `relay`.
3. `npm run build:macos:app-store` builds the App Store-safe profile with `relay`.
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

Recommended next slice: prioritize direct-download customization, including configurable agents for summarizing many messages; treat App Store-safe enqueue/storage work as deferred unless the App Store direction is explicitly reopened.

Distribution direction update:

1. The primary path is now a signed and notarized direct-download Mac app with a standard local `relay` CLI.
2. App Store builds are no longer an active product goal; developer customization wins when it conflicts with App Store constraints.
3. Future Pro features should use an external license-key flow, likely Paddle, Lemon Squeezy, or Stripe, rather than StoreKit unless the App Store direction is explicitly reopened.
4. Direct-download customization should include configurable agents for summarizing many messages.
5. App Store-safe profile work remains useful only as legacy safety hardening, and it should not block direct-download customization or Pro features.
6. The app should still move toward Swift/Xcode and native macOS APIs wherever practical, reducing dependence on Perry-built app helper behavior over time.

Recommended next slice: direct-download signing/notarization packaging or Swift/Xcode project migration.

Swift migration update:

1. Direct and App Store-safe macOS app profiles now own playback in Swift. Direct builds use Swift-launched `/usr/bin/say` for Siri/say voice fidelity; App Store-safe builds use AVFoundation.
2. The macOS app no longer launches or supervises the legacy relay processor loop.
3. Both macOS app profiles package only the CLI helper binary, `relay`.
4. `relay-processor` remains as legacy processor coverage, but it is no longer an app-bundled playback dependency.
5. The macOS app now reads menu status and settings directly from SQLite instead of shelling out to `relay status` or `relay settings`.
6. The macOS app now mutates queue state and claims/marks speech relays directly through Swift SQLite instead of shelling out to app-only helper commands.
7. macOS app builds now run through `src/macos/TriStateRelayService.xcodeproj`, with npm scripts still bundling the Perry-built `relay` CLI.

Recommended next slice: add direct-download signing/notarization packaging, then split the native app into smaller Swift files under the Xcode project.

Command palette direction:

1. The next major product direction is a Raycast-style command palette for
   keyboard-first relay actions.
2. Control-Option-Command-Space should open the palette instead of immediately
   playing the next message.
3. The palette should open with `play next` prefilled and selected, so Return
   keeps the fast Play Next path while typing replaces the query and filters to
   other actions.
4. Left click on the menu bar icon should continue to play the next message.
5. `docs/command-palette.md` records the interaction contract, initial action
   set, search behavior, UI shape, and implementation slices.

Recommended next slice: extract a command model from existing menu actions, then
build the first native command palette window.

Node build replacement update:

1. Direct and legacy App Store-safe macOS app packaging now have shell
   entrypoints at `scripts/build-macos.sh` and `scripts/package-macos-direct.sh`.
2. The npm macOS build and package scripts are compatibility wrappers around
   those shell entrypoints instead of invoking Node build scripts.
3. The shell direct build still compiles the Perry `relay` helper, preserves app
   icon generation, runs Xcode, bundles only `relay`, and rejects any bundled
   `relay-processor`.

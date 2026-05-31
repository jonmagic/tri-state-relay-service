# Progress

## 2026-05-30

Started the repository from the Brain plan in `Daily Lines/2026-05-30/01 agent voicemail speech queue.md`.

Current state:

1. Agent-first line guide and local skills are in place.
2. TypeScript strict-mode line skeleton is in place.
3. SQLite-backed queue core uses `better-sqlite3` and supports enqueue, list, clear, focus, ready, mute, unmute, and claim-next-for-speech.
4. Ready mode claims exactly one queued voicemail and returns to focus.
5. The CLI accepts the v0 `voicemail --line ... --message ...` contract.
6. Perry is documented as a local library and wired into package scripts for dependency compatibility checks and native binary builds.
7. `voicemail-processor` owns the `/usr/bin/say` path, marks successful playback as `heard`, and marks speech failures as `failed`.
8. Processor execution uses a SQLite-backed single-writer lock before claiming messages.
9. `src/app/processor-loop.ts` provides the app-owned processor loop for the menu bar app.
10. `src/app/controller.ts` provides menu-bar-facing queue status and ready/focus/mute/unmute/clear controls without exposing message text.
11. `src/app/menu-bar-shell.ts` composes queue controls and the processor loop for future native macOS adapters.
12. `src/app/native-menu-bar-adapter.ts` maps shell snapshots and actions into a safe native menu render contract.
13. `src/macos/TriStateRelayService.swift` builds an interactable AppKit `NSStatusItem` app around the Perry-built CLI and processor binaries.
14. `voicemail status` exposes JSON queue state for the app without scraping message text.
15. The CLI and menu bar app support skip next, replay last, mark handled, and clear heard lifecycle controls.
16. The CLI and menu bar app support source actions for revealing the latest captured cwd and copying the latest cwd or URL.
17. The menu bar app periodically refreshes queue state and processes one queued voicemail when ready and unmuted.
18. `docs/prompts/combine-inactive-line.md` defines the LLM prompt for collapsing inactive-line updates into one pending message.
19. `npm run eval:inactive-line` compares `apfel` and `llm` against voicemail-composition fixtures with contract checks and an LLM judge.
20. `voicemail combiner --tool none|llm|apfel` configures whether inactive lines use latest-message-only behavior or CLI LLM combination.
21. `voicemail line ...` sets the active line, the menu shows line counts, and the app auto-plays active-line messages while leaving other lines queued.
22. Inactive-line enqueue policy is implemented: native falls back to latest-only, while the Node CLI can call the configured `llm` or `apfel` helper to combine pending inactive-line updates.
23. Line menu actions are scoped to the selected line: play next, skip next, clear queue, replay last, mark handled, and clear heard.
24. Left-click playback makes the line it pulls from active before speaking.

Roadmap gaps from the latest feature review:

1. The roadmap should include safe aggregate queue views for producer/line/priority/staleness patterns without exposing message text.
2. Source controls are still global latest-source actions; line-specific source controls should be added when needed.
3. Shell-out app actions should eventually move behind a native library boundary or direct Swift/Perry bridge.

Recommended next slice: safe aggregate queue views.

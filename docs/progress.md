# Progress

## 2026-05-30

Started the repository from the Brain plan in `Daily Projects/2026-05-30/01 agent voicemail speech queue.md`.

Current slice:

1. Agent-first project guide and local skills are in place.
2. TypeScript strict-mode project skeleton is in place.
3. SQLite-backed queue core uses `better-sqlite3` and supports enqueue, list, clear, focus, ready, mute, unmute, and claim-next-for-speech.
4. Ready mode claims exactly one queued voicemail and returns to focus.
5. The CLI accepts the v0 `voicemail --project ... --message ...` contract.
6. Perry is documented as a local library and wired into package scripts for dependency compatibility checks and native binary builds.
7. `voicemail-processor` owns the `/usr/bin/say` path, marks successful playback as `heard`, and marks speech failures as `failed`.
8. Processor execution uses a SQLite-backed single-writer lock before claiming messages.
9. `src/app/processor-loop.ts` provides the app-owned processor loop for the future menu bar app.
10. `src/app/controller.ts` provides menu-bar-facing queue status and ready/focus/mute/unmute/clear controls without exposing message text.
11. `src/app/menu-bar-shell.ts` composes queue controls and the processor loop for future native macOS adapters.
12. `src/app/native-menu-bar-adapter.ts` maps shell snapshots and actions into a safe native menu render contract.
13. `src/macos/TriStateRelayService.swift` builds an interactable SwiftUI `MenuBarExtra` app around the Perry-built CLI and processor binaries.
14. `voicemail status` exposes JSON queue state for the app without scraping message text.
15. The CLI and menu bar app support skip next, replay last, mark handled, and clear heard lifecycle controls.
16. The CLI and menu bar app support source actions for revealing the latest captured cwd and copying the latest cwd or URL.
17. The menu bar app periodically refreshes queue state and processes one queued voicemail when ready and unmuted.
18. `docs/prompts/combine-inactive-lane.md` defines the LLM prompt for collapsing inactive-lane updates into one pending message.
19. `npm run eval:inactive-lane` compares `apfel` and `llm` against voicemail-composition fixtures with contract checks and an LLM judge.

Roadmap gaps from the latest feature review:

1. The roadmap should include safe aggregate queue views for producer/project/priority/staleness patterns without exposing message text.
2. Perry guidance should live in a library skill with references, scripts, and templates rather than identity or voice notes.

Recommended next slice: replace shell-out app actions with a native library boundary or direct Swift/Perry bridge.

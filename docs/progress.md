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

Roadmap gaps from the latest feature review:

1. The roadmap should include safe aggregate queue views for producer/project/priority/staleness patterns without exposing message text.
2. Perry guidance should live in a library skill with references, scripts, and templates rather than identity or voice notes.

Recommended next slice: add a launchd-friendly daemon loop.

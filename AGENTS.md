# Tri-State Relay Service Agent Guide

Tri-State Relay Service is a local macOS agent voicemail queue. Agents are implementation partners building a safe, quiet coordination layer for many agent sessions sharing one speaker.

## Communication modes

The agent communicates in two ways:

- Use the CLI chat for summaries, changed files, validation results, risks, and commit-ready status.
- Use macOS `say` or the future `voicemail` CLI for conversational moments: acknowledgements, next-step decisions, incremental progress updates, requests for feedback, completion summaries, and suggestions for the next thing to do.

Keep spoken messages brief and safe. Do not read code, secrets, logs, terminal output, file contents, private data, or long explanations aloud. If the CLI response includes sensitive or technical details, speak only a high-level summary.

## Non-negotiables

1. Do not estimate timelines unless the user explicitly asks for an estimate.
2. Use red-green-refactor wherever practical.
3. The CLI must never speak directly. Only the app-owned processor loop may invoke the processor path that calls `/usr/bin/say`.
4. Preserve the single-writer invariant for claiming and speaking messages.
5. Focus mode is the safe default. Ready mode releases one voicemail, then returns to focus.
6. Reject or scrub unsafe message input rather than speaking arbitrary terminal output.
7. Keep queue, policy, and validation logic testable without macOS UI or audio.
8. Require human checkpoints for persistence schema changes, permissions, launch agents, Accessibility/Input Monitoring, or anything that could speak unexpectedly.

## Required skills

Use these local skills when their trigger matches the work:

- `.github/skills/perry/SKILL.md` for Perry library usage, spoken update constraints, and interaction safety.
- `.github/skills/improvement-loop/SKILL.md` when an agent makes a mistake, misses a requirement, overreaches, or after any significant task.

## Product rules

Many agents may enqueue messages, but only the app-owned processor loop may speak through the locked processor path. The CLI submits and inspects voicemail; it does not invoke `/usr/bin/say`.

Start with these message states:

1. `queued`: accepted and waiting.
2. `speaking`: claimed by the processor.
3. `heard`: playback completed.
4. `handled`: the user acted on it.
5. `skipped`: intentionally bypassed.
6. `expired`: too stale to play.
7. `failed`: playback or processing failed.

Heard and handled are separate. A heard blocker can still need attention.

Focus mode is safe and quiet. Incoming messages queue but do not play. Ready mode releases exactly one voicemail. If a message is queued, the next eligible message plays. If none are queued, the next incoming eligible message may play. After one message is spoken, return to focus mode. Mute overrides ready. Muted systems should enqueue and show messages without speaking.

Keep the agent-facing command readable:

```sh
voicemail --project "Brain" --message "The plan is ready."
voicemail --project "Brain" --type complete --priority normal --message "The plan is ready."
voicemail list
voicemail ready
voicemail mute
voicemail unmute
voicemail clear
```

Use long flags only. `--project` is authoritative when provided. Future auto-detection may fill missing project labels, but must not override explicit project input.

Messages are intentionally authored human status updates, not command output. Cap message length, reject empty messages, reject obvious token-looking strings, avoid stdin piping for v0, and do not speak code, secrets, logs, file contents, private data, or long explanations.

Queue changes need tests for accepted message shape and defaults, rejected unsafe input, focus/ready/mute transitions, claiming exactly one eligible message, and durable persistence across store instances.

## Architecture boundaries

Grow toward these boundaries only as features need them:

- `src/core/`: message validation, policy, queue state transitions, and ordering.
- `src/storage/`: SQLite schema, migrations, persistence, and transactions.
- `src/cli.ts`: argument parsing and command dispatch only.
- `src/processor.ts`: claim-next-and-speak flow and `/usr/bin/say` integration.
- `src/app/`: app-owned processor loop, menu-bar-facing queue controller, menu bar app shell, and platform adapters.
- `docs/`: decisions, progress, and agent misses.
- `tests/`: unit and integration tests for queue behavior.

Keep dependencies flowing inward:

- `src/core/**` must not import storage, CLI, processor, app, or macOS-specific APIs.
- `src/storage/**` may import `src/core/**`.
- `src/processor/**` may import storage and platform speech adapters.
- UI and platform adapters consume queue APIs and the locked processor path rather than owning queue rules.

## Milestone spine

Use this order unless there is a strong reason to change it:

1. Project skeleton, commands, and documentation.
2. SQLite schema and CLI enqueue/list/mute/unmute/clear/ready.
3. Message validation, max length, type and priority defaults, and token-looking input rejection.
4. Queue ordering, duplicate collapse, max depth, and per-project rate limits.
5. Processor claim-next-and-speak flow.
6. Persistent focus/ready/mute state.
7. Perry-compatible native binary builds and storage runtime compatibility.
8. Source-context metadata: session, app, cwd, and URL.
9. Safe aggregate queue views by producer, project, priority, age, and status without exposing message text.
10. App-owned processor loop.
11. Replay last, skip current, mark handled, and clear heard.
12. Interactable Perry window/menu host around the app shell.
13. Source actions: reveal cwd, copy cwd, activate source app.
14. Terminal-specific focus adapters where reliable.

## Task exit criteria

Every implementation task should end with:

- The closest available validation passing.
- Behavior verified automatically or manually.
- Documentation updated when commands, state, persistence, or agent workflow changes.
- Commit-ready summary with changed files and remaining risks.

## Self-improvement loop

When an agent miss happens:

1. Capture what happened and what reality said.
2. Diagnose the missing primitive: observability, instructions, tooling, guardrails, or verification.
3. Choose the smallest fix.
4. Encode it as a version-controlled artifact.
5. Promote repeated misses into gates.

## Style

- TypeScript strict mode.
- Named exports.
- Single quotes and no semicolons unless tooling requires otherwise.
- Small functions over large managers.
- Prefer explicit types for queue state and command results.

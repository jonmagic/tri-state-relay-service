# Tri-State Relay Service Agent Guide

Tri-State Relay Service is a local macOS agent relay queue. Agents are implementation partners building a safe, quiet coordination layer for many agent sessions sharing one speaker.

## Non-negotiables

1. Do not estimate timelines unless the user explicitly asks for an estimate.
2. Use red-green-refactor wherever practical.
3. The CLI must never speak directly. App playback is owned by Swift native speech; `relay-processor` is legacy compatibility and must not be bundled into the macOS app.
4. Preserve the single-writer invariant for claiming and speaking messages.
5. Focus mode is the safe default. Ready mode releases one relay, then returns to focus.
6. Reject or scrub unsafe message input rather than speaking arbitrary terminal output.
7. Keep queue, policy, and validation logic testable without macOS UI or audio.
8. Require human checkpoints for persistence schema changes, permissions, launch agents, Accessibility/Input Monitoring, or anything that could speak unexpectedly.

## Required skills

Use these local skills when their trigger matches the work:

- `.github/skills/perry/SKILL.md` for Perry library usage, spoken update constraints, and interaction safety.
- `.github/skills/improvement-loop/SKILL.md` when an agent makes a mistake, misses a requirement, overreaches, or after any significant task.

## Milestone commits

When an implementation milestone is complete, validated, and not blocked, commit
it without waiting for another prompt. Keep unrelated changes in separate
commits, and call out any remaining uncommitted work or risks in the handoff.

## Product rules

Many agents may enqueue relays, but only the app-owned playback path may speak. The CLI submits and inspects relays; it does not invoke `/usr/bin/say`.

The primary distribution direction is signed direct download with a standard
local `relay` CLI and future license-key Pro unlocks. The App Store-safe
profile is a hardening profile, not the default release target. Prefer moving
normal app behavior toward Swift/Xcode and native macOS APIs while keeping the
CLI as the agent integration surface.

Start with these message states:

1. `queued`: accepted and waiting.
2. `speaking`: claimed by the processor.
3. `heard`: playback completed.
4. `handled`: the user acted on it.
5. `skipped`: intentionally bypassed.
6. `expired`: too stale to play.
7. `failed`: playback or processing failed.

Heard and handled are separate storage states. In user-facing copy, prefer delivered and acknowledged.

Focus mode is safe and quiet. Incoming relays queue but do not play. Ready mode releases exactly one relay. If a relay is queued, the next eligible relay plays. If none are queued, the next incoming eligible relay may play. After one relay is spoken, return to focus mode. Mute overrides ready. Muted systems should enqueue and show relays without speaking.

Keep the agent-facing command readable:

```sh
relay --line "Brain" --message "The plan is ready."
relay --line "Brain" --type complete --priority normal --message "The plan is ready."
relay list
relay ready
relay mute
relay unmute
relay clear
relay acknowledge
relay clear-delivered
```

Use long flags only. `--line` is authoritative when provided. Future auto-detection may fill missing line labels, but must not override explicit line input.

Messages are intentionally authored human status updates, not command output. Cap message length, reject empty messages, reject obvious token-looking strings, avoid stdin piping for v0, and do not speak code, secrets, logs, file contents, private data, or long explanations.

Queue changes need tests for accepted message shape and defaults, rejected unsafe input, focus/ready/mute transitions, claiming exactly one eligible message, and durable persistence across store instances.

## Architecture boundaries

Grow toward these boundaries only as features need them:

- `src/core/`: message validation, policy, queue state transitions, and ordering.
- `src/storage/`: SQLite schema, migrations, persistence, and transactions.
- `src/cli.ts`: argument parsing and command dispatch only.
- `src/processor.ts`: legacy claim-next-and-speak flow and `/usr/bin/say` integration kept out of the app bundle.
- `src/app/`: app-owned processor loop, menu-bar-facing queue controller, menu bar app shell, and platform adapters.
- Native Swift/Xcode code should replace helper shell-outs and Perry-built app
  bridge behavior as seams become clear.
- `docs/`: decisions, progress, and agent misses.
- `tests/`: unit and integration tests for queue behavior.

Keep dependencies flowing inward:

- `src/core/**` must not import storage, CLI, processor, app, or macOS-specific APIs.
- `src/storage/**` may import `src/core/**`.
- `src/processor/**` may import storage and platform speech adapters.
- UI and platform adapters consume queue APIs and the locked processor path rather than owning queue rules.

## Milestone spine

Use this order unless there is a strong reason to change it:

1. Line skeleton, commands, and documentation.
2. SQLite schema and CLI enqueue/list/mute/unmute/clear/ready.
3. Message validation, max length, type and priority defaults, and token-looking input rejection.
4. Queue ordering, duplicate collapse, max depth, and per-line rate limits.
5. Processor claim-next-and-speak flow.
6. Persistent focus/ready/mute state.
7. Perry-compatible native binary builds and storage runtime compatibility.
8. Source-context metadata: session, app, cwd, and URL.
9. Safe aggregate queue views by producer, line, priority, age, and status without exposing message text.
10. App-owned processor loop.
11. Interactable AppKit menu bar host around the Perry-built CLI and processor binaries.
12. Replay last, skip current, mark handled, and clear heard.
13. Line-scoped menu actions and active-line switching from playback.
14. Relay terminology aliases for acknowledge and clear-delivered.
15. Terminal-specific focus adapters where reliable.
16. Signed direct-download packaging: signing, notarization, and standard CLI installation.
17. Swift/Xcode migration for app-owned queue, settings, source actions, and playback behavior.
18. App Store-safe profile hardening: native speech, no external command templates, and bundle inspection.
19. Remove app dependence on `relay-processor`; playback is now Swift-native in both profiles.

## Task exit criteria

Every implementation task should end with:

- The closest available validation passing.
- Behavior verified automatically or manually.
- Documentation updated when commands, state, persistence, or agent workflow changes.
- For App Store/direct profile changes, both `npm run build:macos:direct` and `npm run build:macos:app-store` should pass and their bundles should be inspected. Neither macOS app profile should bundle `relay-processor`.
- Distribution and licensing changes must preserve `docs/distribution.md`, and App Store-safe profile changes must preserve `docs/app-store-profile.md`.
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

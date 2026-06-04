# Tri-State Relay Service Agent Guide

Tri-State Relay Service is a local macOS agent relay queue. Agents are implementation partners building a safe, quiet coordination layer for many agent sessions sharing one speaker.

## Non-negotiables

1. Do not estimate timelines unless the user explicitly asks for an estimate.
2. Use red-green-refactor wherever practical.
3. The CLI must never speak directly. App playback is owned by the Swift app; direct builds currently use Swift-launched `/usr/bin/say` for Siri voice fidelity, App Store-safe builds use AVFoundation, and `relay-processor` is legacy compatibility that must not be bundled into the macOS app.
4. Preserve the single-writer invariant for claiming and speaking messages.
5. Focus mode is the safe default. Ready mode releases one relay, then returns to focus.
6. Reject or scrub unsafe message input rather than speaking arbitrary terminal output.
7. Keep queue, policy, and validation logic testable without macOS UI or audio.
8. Require human checkpoints for persistence schema changes, permissions, launch agents, Accessibility/Input Monitoring, or anything that could speak unexpectedly.

## Required skills

Use these local skills when their trigger matches the work:

- `.github/skills/improvement-loop/SKILL.md` when an agent makes a mistake, misses a requirement, overreaches, or after any significant task.

## Milestone commits

When an implementation milestone is complete, validated, and not blocked, commit
it without waiting for another prompt. Keep unrelated changes in separate
commits, and call out any remaining uncommitted work or risks in the handoff.
Before committing, inspect `git diff --cached --name-only` and confirm the staged
file list matches the intended milestone.

For app-visible macOS changes, run `scripts/build-macos.sh direct` and then
`scripts/restart-macos-app.sh`. Do not use ad hoc `open` commands without first
stopping the old process. The restart helper must report a running PID from the
rebuilt `dist/macos/Tri-State Relay Service.app` bundle; say that explicitly in
the handoff. Before any handoff or docs-only commit, check for pending app-visible
Swift changes; if any exist, either run the restart gate and commit them first or
explicitly say they remain uncommitted for review.

## Product rules

Many agents may enqueue relays, but only the app-owned playback path may speak. The CLI submits and inspects relays; it does not invoke `/usr/bin/say`. In the direct profile, the Swift app may launch `/usr/bin/say` itself to preserve Siri/say voice behavior. In the App Store-safe profile, playback uses AVFoundation and must not launch external speech commands.

The primary distribution direction is signed direct download with a standard
local `relay` CLI, developer customization, and future license-key Pro unlocks.
App Store builds are no longer an active product goal. Keep App Store-safe notes
as legacy hardening references only, and do not let App Store constraints block
direct-download customization such as choosing the agent used to summarize many
messages.

Start with these message states:

1. `queued`: accepted and waiting.
2. `speaking`: claimed by the app-owned playback path.
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

- `src/macos/RelayCore.swift`: message validation, queue state transitions, SQLite storage, and CLI command dispatch.
- `src/macos/RelayCli/main.swift`: CLI entrypoint only.
- `src/macos/TriStateRelayService.swift`: app-owned playback, menu-bar UI, queue controls, and platform adapters.
- `docs/`: decisions, progress, and agent misses.
- `src/macos/TriStateRelayServiceTests/`: XCTest coverage for queue behavior, CLI behavior, storage, and app playback policy.

Keep queue, policy, and validation logic in Swift types that can be tested without launching the app UI or audio path. UI and platform adapters consume queue APIs and the app-owned claim/playback path rather than owning queue rules.

## Milestone spine

Use this order unless there is a strong reason to change it. After each item is
completed and committed, update this section and any directly related docs so
the next agent sees the current state instead of stale guidance:

1. Make the command-palette shortcut configurable in Settings. Default to the current Play Next shortcut, but persist the user's choice and keep shortcut registration testable without AppKit UI.
2. Require first-start configuration before normal app use. Open Settings on first launch and guide the user through CLI installation, shortcut selection, and voice selection without using a heavy "wizard" pattern.
3. Improve the CLI install panel: encourage installing `relay` into an accessible path, keep safe overwrite behavior, and add a copy button for the full bundled app-contents CLI path.
4. Improve voice selection during first-start setup and normal Settings. Favor natural voices when available and keep direct-profile `/usr/bin/say` behavior until an explicit product decision replaces it.
5. Keep trimming docs and repository cruft from the user-facing path. Remove stale LLM evaluation references and any docs that no longer describe the active direct-download product direction.
6. Make direct-download builds arm64-only by default to reduce binary and release size. Preserve a deliberate path for universal builds only if a future distribution need appears.
7. Maintain `docs/user-guide.md` as the primary user-facing guide. Update it whenever setup, shortcuts, CLI installation, voice behavior, line behavior, or queue commands change.

## Task exit criteria

Every implementation task should end with:

- The closest available validation passing.
- Behavior verified automatically or manually.
- Documentation updated when commands, state, persistence, or agent workflow changes.
- For app-visible direct-profile changes, `scripts/build-macos.sh direct` should pass and the bundle should be inspected. The app must not bundle `relay-processor`.
- Distribution, licensing, and customization changes must preserve `docs/distribution.md`. Treat `docs/app-store-profile.md` as legacy hardening reference unless the App Store direction is explicitly reopened.
- Commit-ready summary with changed files and remaining risks.

## Self-improvement loop

When an agent miss happens:

1. Capture what happened and what reality said.
2. Diagnose the missing primitive: observability, instructions, tooling, guardrails, or verification.
3. Choose the smallest fix.
4. Encode it as a version-controlled artifact.
5. Promote repeated misses into gates.

## Style

- Swift code should keep queue state and command results explicit and testable.
- Small functions over large managers.
- Shell scripts use long flags where practical and must not speak directly.

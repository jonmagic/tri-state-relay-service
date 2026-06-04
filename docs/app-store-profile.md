# Legacy App Store-safe profile

TSRS has given up on App Store builds as an active product goal in favor of
signed direct-download distribution, developer customization, and a standard
CLI. See `docs/distribution.md` for the primary distribution direction.

The App Store-safe profile remains as a legacy hardening reference only. It can
help explain safer boundaries, but new product work should not optimize for App
Store constraints when that conflicts with direct-download customization such as
choosing the agent used to summarize many messages.

TSRS currently still has two distribution profile code paths:

1. `direct`: direct-download, power-user, CLI-first behavior.
2. `app-store`: review-palatable behavior that avoids arbitrary command execution from the app surface.

The App Store-safe profile is not a Mac App Store release checklist and is not a
required product gate. It is a code and packaging seam kept for reference while
the direct profile remains the product and dogfooding path.

## Current profile contract

The App Store-safe profile:

1. Uses app-owned AVFoundation speech for relay playback.
2. Uses the same CLI-only native app packaging as the direct build and does not build, bundle, or launch `relay-processor`.
3. Uses native Swift SQLite access for app-owned queue controls and speech state.
4. Masks external inactive-line combiner command templates.
5. Has no CLI source command surface.
6. Performs line-scoped app source actions with `NSWorkspace` and `NSPasteboard`.
7. Exposes capabilities through `relay settings` and `relay status`.
8. Rejects terminal `relay --line ... --message ...` enqueueing until an App Store-safe storage model is chosen.

The direct profile keeps:

1. Swift-owned app playback that may launch `/usr/bin/say` to preserve Siri/say voice behavior.
2. Configurable inactive-line combiner command templates.
3. Line-scoped app source actions for direct terminal use context.
4. Native voice selection in the app settings window.

## Storage and enqueueing decision

For signed direct-download distribution, CLI-based agent enqueueing is a normal
product capability.

For legacy App Store-safe profile builds, CLI-based terminal enqueueing remains
disabled. When `TSRS_DISTRIBUTION_PROFILE=app-store`, terminal
`relay --line ... --message ...` enqueueing is rejected. The App Store-safe app
can still use native Swift SQLite access to claim and update relays during local
builds, but this is not a sandboxing commitment.

A sandboxed App Store app should not assume it can use the direct profile's
default database path:

```text
~/Library/Application Support/Tri-State Relay Service/relay.db
```

If the Mac App Store becomes a target again, choose one of these models before
sandboxing:

1. App Store profile has no terminal CLI integration initially.
2. App Group container shared with a signed helper.
3. App-owned constrained local IPC endpoint for enqueue-only relays.
4. Direct profile remains the CLI integration path, while App Store profile is a constrained local/free introduction.

The current direction is signed direct download with standard CLI integration
and developer customization. Do not add IPC, App Groups, launch agents, or
sandbox entitlements without a separate architecture decision and human
checkpoint.

## Review note

Tri-State Relay Service is a local macOS menu bar status inbox for developer
tools. It stores short user-authored status relays locally and plays them
through the app-controlled speech path only when the user enables playback. The
app checks default input-device activity before claiming speech so it can defer
playback while another app is capturing microphone input, without recording or
inspecting microphone audio. The App Store build does not execute arbitrary
user-provided shell commands or download executable code. External command
integrations are reserved for the separately distributed direct-download
edition.

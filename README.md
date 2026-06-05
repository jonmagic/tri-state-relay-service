# Tri-State Relay Service

Tri-State Relay Service is a local macOS agent relay inbox. Agents submit short status messages with the `relay` CLI, TSRS stores them as relays in a local SQLite queue, and the Swift app-owned playback path speaks one relay at a time.

Product page: https://jonmagic.com/tsrs/

Background: https://jonmagic.com/posts/the-feedback-loop-i-was-missing/

The core CLI contract is intentionally small:

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

For installation and everyday use, start with `docs/user-guide.md`. For local development, validation, build, and release commands, see `docs/development.md`.

For future direction, see `ROADMAP.md`.

The direct profile is an AppKit `NSStatusItem` host that owns menu state, queue controls, speech claims, and playback in Swift. The app reads and mutates the local SQLite queue directly without scraping or exposing message text. Right click opens line controls; left click selects the next queued line for playback. When unmuted, the app keeps playing incoming relays on the active line. Other lines stay quiet and can be pulled from their line submenu.

The direct app can install or update the bundled `relay` CLI from Settings. On first launch, Settings opens on the Setup panel first, recommends `/usr/local/bin/relay`, lets you record the command-palette shortcut, refuses to overwrite a foreign `relay`, and offers a copy button for the full bundled app-contents CLI path. The CLI exposes the same mechanism through `relay cli-status`, `relay install-cli`, and `relay --version`.

Before claiming a relay for speech, the app checks whether the default input device appears to be actively captured by another app. When microphone capture is active, TSRS leaves relays queued and retries later instead of speaking over the user. This is a best-effort CoreAudio device-state check; TSRS does not record or inspect microphone audio.

Normal CLI usage remains the queue and automation interface for agents, while the menu bar app owns interactive queue controls and speech state through native SQLite access.

Each line submenu scopes lifecycle controls to that line: play next, skip next, clear queue, replay last, acknowledge last, clear delivered, and source actions for that line. Global controls cover mute, unmute, settings, refresh, and quit. Source actions are app menu actions only; there is no global source menu, no overview section, and no CLI source command surface.

To keep old lines from living in the menu forever, TSRS expires stale relays from menu views after 30 minutes. Delivered and failed relays expire by `updated_at`; queued normal or low-priority update/complete relays expire by `created_at`. High-priority queued relays and blocked/needs-input relays stay until handled explicitly.

By default, TSRS stores its database at `~/Library/Application Support/Tri-State Relay Service/relay.db`. For tests or local experiments, set `TSRS_DB_PATH` to another path inside this repository or another safe working directory.

## Lines

TSRS tracks an active line:

```sh
relay line
relay line "Tri-State Relay Service"
```

The first accepted relay becomes the active line when no active line is set. The menu bar app uses a Raycast-style command palette for interactive relay actions. Right click opens the palette for search-driven actions, while left click remains the fastest pointer path for Play Next. When unmuted, the app keeps playing queued messages from the active line as they arrive. Messages from other lines remain queued until you switch lines or pull them manually. Pulling a message from another line makes that line active.

Line-scoped source actions use the selected line's latest source context, not the newest source from another line. See `docs/command-palette.md`.

The command-palette shortcut is configurable in Settings. The default is `Control` + `Option` + `Command` + `Space`, which opens the command palette with `play next` preselected. For command-palette details, see `docs/command-palette.md`.

TSRS is licensed under the ISC License. See `LICENSE`.

Use `SECURITY.md` for vulnerabilities or reports that include secrets, private notification content, relay queue contents, personal transcripts, credentials, or unsanitized logs. See `docs/distribution.md` for the signed direct-download direction.

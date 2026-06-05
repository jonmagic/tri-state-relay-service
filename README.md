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

Install or run the macOS app, then install the bundled `relay` CLI from Settings. Point agents at one short instruction: send brief, human-authored relays for meaningful progress changes, blockers, and completion.

A line is a named work stream. TSRS uses the active line when deciding what to play next:

```sh
relay line
relay line "Tri-State Relay Service"
```

Relays queue quietly in Focus mode. When you are ready, play exactly one relay:

```sh
relay ready
```

The app then returns to Focus mode. Left click the menu bar item for the fastest Play Next path, or use the command palette for search-driven relay actions. The default command-palette shortcut is `Control` + `Option` + `Command` + `Space`.

The first accepted relay becomes the active line when no active line is set. Messages from other lines remain queued until you switch lines or pull from them manually. Line-scoped source actions use the selected line's latest source context, not the newest source from another line.

For the full walkthrough, see [the user guide](docs/user-guide.md).

## More

- [Development guide](docs/development.md)
- [Command-palette guide](docs/command-palette.md)
- [Distribution notes](docs/distribution.md)
- [Roadmap](ROADMAP.md)
- [Security policy](SECURITY.md)

TSRS is licensed under the ISC License. See `LICENSE`.

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
relay live
relay focus
relay mute
relay unmute
relay clear
relay clear-delivered
relay skip-next
relay acknowledge
relay replay-last
relay line
relay line "Tri-State Relay Service"
relay combiner
relay config show
relay config validate
relay config set --voice-command '/usr/bin/say -f <text-file> -o <output-file>'
relay status
```

## Line shape

The invariant is more important than the surface: many producers can enqueue relays, but only the app-owned playback path may speak.

1. The CLI never calls `/usr/bin/say` directly.
2. The app owns relay playback. Direct builds currently use Swift-launched `/usr/bin/say` for Siri voice fidelity; the legacy App Store-safe profile uses AVFoundation.
3. The SQLite store owns message state and persistent mode.
4. Focus, Ready, and Live are the three playback states.
5. Focus mode is the safe default. Ready releases exactly one relay, then returns to Focus. Live keeps playing relays automatically, grouped by line.
6. Mute is a separate safety override that blocks playback in any state.
7. Messages stay short and intentionally authored.

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

When you want TSRS to keep playing new relays automatically, use Live mode:

```sh
relay live
```

Live drains the relays that were available for one line, switches to the next queued line, and then returns to earlier lines if more relays arrived there. Use Stop Live in the menu bar app or `relay focus` to go quiet again.

The first accepted relay becomes the active line when no active line is set. Messages from other lines remain queued until you switch lines or pull from them manually. Line-scoped source actions use the selected line's latest source context, not the newest source from another line.

For the full walkthrough, see [the user guide](docs/user-guide.md).

## More

- [Development guide](docs/development.md)
- [Command-palette guide](docs/command-palette.md)
- [Distribution notes](docs/distribution.md)
- [Roadmap](ROADMAP.md)
- [Security policy](SECURITY.md)

TSRS is licensed under the ISC License. See [LICENSE](LICENSE).

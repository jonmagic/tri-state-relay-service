# Tri-State Relay Service user guide

Tri-State Relay Service is a quiet local inbox for agent status updates. Agents
send short relays with the `relay` CLI, and the macOS menu bar app lets you hear
or manage those relays when you are ready.

## Install the app and CLI

1. Build or install the direct-download macOS app.
2. Launch Tri-State Relay Service from the app bundle.
3. On first launch, Settings opens automatically on the CLI panel.
4. Install the bundled `relay` CLI up front, then choose a command-palette
   shortcut and voice.

The recommended CLI install path is `~/.local/bin/relay` because agents can use
it from any project once `~/.local/bin` is on `PATH`. TSRS updates TSRS-owned
copies at that path but refuses to overwrite a different binary. If you prefer
not to install it, use the Settings > CLI copy button to copy the full bundled
app-contents CLI path and put that full path in your agent instructions.

## First setup

The first-run Settings screen opens with the CLI install action visible first,
then helps you make three choices before normal use:

1. Install or locate the `relay` CLI so agents can enqueue updates.
2. Record the command-palette shortcut by pressing the combination you want.
   The default is `Control` + `Option` + `Command` + `Space`.
3. Choose the voice used by app-owned playback.

This setup is part of the normal Settings window, not a heavyweight onboarding
wizard. TSRS remains in Focus mode during setup, so relays queue quietly until
you explicitly play one. You can return to Settings later to change the shortcut, reinstall or locate the
CLI, copy the bundled CLI path, or change the voice.

## Send a relay

Use intentionally authored messages, not raw command output:

```sh
relay --line "Brain" --type update --priority normal --cwd "$PWD" --message "I am drafting the project summary."
relay --line "Brain" --type complete --priority normal --cwd "$PWD" --message "The summary is ready."
```

Good relays are short progress updates, phase changes, blockers, requests for
human input, and completion notes. Do not send code, logs, secrets, private data,
or long explanations.

## Listen safely

TSRS starts quiet. Focus mode queues relays without speaking. Ready mode releases
one eligible relay and then returns to focus. Mute prevents playback even when
relays are queued.

Useful commands:

```sh
relay list
relay ready
relay mute
relay unmute
relay acknowledge
relay clear-delivered
```

The app owns playback. The CLI never speaks directly.

## Lines

Lines separate different work contexts. For example, use one line for `Brain`
work and another for `Tri-State Relay Service` development:

```sh
relay line
relay line "Tri-State Relay Service"
```

The active line is the line TSRS plays automatically when unmuted. Other lines
stay queued until you switch lines or explicitly pull a relay from that line.

## Menu bar controls

Left click the menu bar icon for the fastest Play Next path. Right click opens
the command palette with an empty search. The configurable keyboard shortcut
opens the command palette with Play Next selected, so pressing Return immediately
plays the next eligible relay. The default shortcut is `Control` + `Option` +
`Command` + `Space`; change it in Settings > Shortcut by clicking Record
Shortcut and pressing a valid combination. TSRS rejects invalid or reserved
combinations, including `Control` + `Option` + `Command` + `V`, instead of
silently falling back.

The command palette shows safe action context such as line names and counts. It
should not show relay message bodies by default.

## Voice

Choose a voice in Settings during first setup or later normal use. Direct-download
builds currently preserve Siri/say voice behavior through app-owned playback: the
voice menu is built from installed macOS voices that can be passed to
`/usr/bin/say -v <name>`. Natural installed voices are favored when available,
while System Default remains available.

Changing the voice selection is quiet. Use Preview only when you explicitly want
to hear a sample. Install additional macOS voices in System Settings >
Accessibility > Spoken Content.

## Troubleshooting

If agents cannot find `relay`, open Settings > CLI and install it to
`~/.local/bin/relay`, then make sure `~/.local/bin` is on `PATH`. If you do not
want to install it, copy the bundled app-contents CLI path from Settings > CLI
and use that full path directly. If relays queue but do not speak, check whether
TSRS is focused, muted, or waiting because the microphone appears active.

The queue is stored locally at:

```text
~/Library/Application Support/Tri-State Relay Service/relay.db
```

### Development first-start verification

Existing local installs may not show first setup because they already have
configuration.

To re-test the first-start prompt without wiping relays, reset only the
setup-completion key:

```sh
relay first-start reset
```

Then restart the app with `scripts/restart-macos-app.sh`; Settings should open
again. Restore the normal configured state with:

```sh
relay first-start complete
```

If you are testing before that CLI command is installed, run the equivalent
SQLite update against the local queue database:

```sh
sqlite3 "$HOME/Library/Application Support/Tri-State Relay Service/relay.db" \
  "INSERT INTO settings (key, value) VALUES ('first_start_setup_complete', 'false')
   ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
```

This targeted reset does not clear queued or delivered relays. Avoid deleting
`relay.db` unless you explicitly want to wipe all local queue data.

For a true fresh first-start run, use the explicit development-only destructive
reset:

```sh
relay first-start dev-reset-database --confirm
```

This removes the configured app database and its SQLite sidecar files
(`relay.db`, `relay.db-wal`, and `relay.db-shm`), which clears queued,
delivered, handled, skipped, expired, and failed relays plus local settings such
as active line, voice, shortcut, and setup completion. The command then
recreates an empty database that defaults to first-start needs-setup. It is not
called by normal app launch paths.

Shortcut setup records a custom key combination in Settings. Use a combination
with `Command` plus at least one of `Control`, `Option`, or `Shift`.

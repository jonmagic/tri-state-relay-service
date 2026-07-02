# Tri-State Relay Service user guide

Tri-State Relay Service is a quiet local inbox for updates from your coding agents. Instead of leaving every agent to interrupt you in its own way, agents send short relays to the macOS menu bar app. You stay in control of when one is played.

The basic idea is simple:

1. Install the app and the `relay` command.
2. Tell your agents when to send short status updates.
3. Let relays queue quietly while you work.
4. Press Play Next when you are ready to hear one, or Start Live when you want new relays to play automatically.

## Start with the app

Launch Tri-State Relay Service from the macOS app bundle. On first launch, Settings opens automatically and walks you through the essentials.

The first thing to set up is the command-line tool. The app can install `relay` for you at:

```text
/usr/local/bin/relay
```

That location works well for normal macOS users because `/usr/local/bin` is commonly already on the shell path. If you would rather not install a copy, Settings can also show the full bundled app path so you can paste that into agent instructions instead.

After the CLI step, choose a keyboard shortcut and decide whether TSRS should open at login. The default shortcut is `Control` + `Option` + `Command` + `Space`. You can change it by clicking the shortcut button and pressing the combination you want. Open at Login is optional and starts TSRS in Focus mode, so relays still queue quietly until you ask to hear one.

TSRS stays quiet during setup. Anything that arrives is queued until you choose to hear it.

## Your first relay

A relay is a short, human-readable update from an agent. It should sound like a teammate briefly saying what changed, not like a log dump.

For example:

```sh
relay --line "My Project" --message "I’m starting the next implementation slice."
```

When that command runs, the update appears in TSRS. If you are in Focus mode, it waits silently. When you are ready, use Play Next from the menu bar app or run:

```sh
relay ready
```

TSRS plays one eligible relay, then returns to quiet mode.

If you want TSRS to keep playing new relays automatically, choose Start Live from the menu bar app or run:

```sh
relay live
```

Live mode plays queued relays by line. TSRS drains the relays that were available for one line, switches to the next queued line, and then returns to a previous line if more relays arrived there in the meantime. A high-priority relay on another line waits until the current line batch finishes. Use Stop Live, Focus, or `relay focus` to go quiet again.

## What makes a good relay

Good relays are short and intentional. Use them for:

1. Starting a meaningful work slice.
2. Switching phases, such as from investigation to implementation.
3. Getting blocked or needing human input.
4. Finishing something useful.

Avoid sending raw command output, logs, code, secrets, private data, or long explanations. If the message would be annoying to hear out loud, it is probably too much for a relay.

Good examples:

```sh
relay --line "My Project" --type update --message "The tests are running now."
relay --line "My Project" --type complete --message "The draft is ready to review."
relay --line "My Project" --priority high --message "I’m blocked and need your choice before continuing."
```

## Lines keep work streams separate

A line is a named work stream. If you only have one agent working on one project, one line may be enough. If you have several agents working at once, lines make it much easier to understand which update belongs where.

For example, you might use:

```sh
relay --line "Website" --message "I found the broken image path."
relay --line "API" --message "The auth test failure is isolated."
```

You can also use more specific line names when several agents are working inside the same project:

```sh
relay --line "TSRS icon" --message "The app icon was rebuilt."
relay --line "TSRS docs" --message "The user guide rewrite is in progress."
```

The active line is the line TSRS plays from automatically when you ask for the next relay. Other lines stay queued until you switch to them or pull from them directly.

Useful line commands:

```sh
relay line
relay line "Website"
relay list
```

## Add TSRS to your agent instructions

The easiest way to make TSRS useful is to add a small instruction to your highest-level agent instructions. Put it wherever your coding agent reads its global or project instructions.

Start simple:

```text
When using tools or doing multi-step work, send short Tri-State Relay Service updates with:

relay --line "My Project" --type update --priority normal --cwd "$PWD" --message "I’m starting the next work slice."

Use --type complete when a meaningful task is done. Keep messages brief and human-authored. Do not send code, logs, secrets, private data, or raw terminal output.
```

If you often run more than one agent in the same project, ask the agent to choose or confirm a line name at the start of the session. That gives each work stream a separate lane without changing projects.

Example:

```text
At the start of each session, ask me what the Tri-State Relay Service line should be called. An empty answer is fine and means to use the current project or folder name. Use that line for all TSRS updates during the session.
```

You can combine that with a default line rule:

```text
Choose the default line from the current working directory. Prefer the git repository or project name. Mention cross-project research in the message text instead of changing the line.
```

The goal is not to make agents chatty. The goal is to make their important state changes easy to notice without watching every terminal.

## Everyday controls

TSRS is designed to be quiet by default.

The three playback states are Focus, Ready, and Live. Focus queues relays without speaking. Ready releases one relay, then returns to Focus. Live keeps playing new relays automatically, grouped by line.

Mute is a separate safety override. It prevents playback even if relays are queued or Live is on.

Primary playback commands:

```sh
relay list
relay ready
relay live
relay focus
```

Other queue controls:

```sh
relay mute
relay unmute
relay acknowledge
relay clear-delivered
```

In the menu bar app, left click for the fastest Play Next path. Use Start Live when you want automatic playback and Stop Live when you want to return to Focus. Right click opens the command palette. Your keyboard shortcut opens the command palette with Play Next selected, so pressing Return immediately plays the next eligible relay.

The app owns playback. The CLI submits and manages relays, but it does not speak directly.

## Voice and shortcut settings

Open Settings whenever you want to change the CLI install, keyboard shortcut, Open at Login, or voice.

Changing the voice is quiet. Use Preview only when you explicitly want to hear a sample. To add more macOS voices, open System Settings > Accessibility > Spoken Content.

Direct-download builds use app-owned playback and can use installed macOS voices that work with the system speech engine. Natural voices are favored when available, and System Default remains available.

## When many updates pile up

When you are focused on one line, other lines may collect several updates. TSRS can keep this manageable by showing or playing the latest useful update for an inactive line instead of making you hear every stale intermediate message.

For many people, the default behavior is enough. You can work on one line, then switch lines when you are ready to catch up.

## Advanced: the inactive-line Combiner

The Combiner is for people who want an external agent or command to summarize many queued inactive-line updates into one short relay. It is useful when you run several agents at once and want a catch-up that sounds like a concise teammate summary.

You can inspect or change the Combiner from the CLI:

```sh
relay combiner
relay combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
relay combiner --command none
```

The command template receives the inactive-line updates as input and should return one safe, short message. Leave the Combiner unset if you prefer the simpler latest-update behavior.

Combiner output should follow the same rules as any other relay: no secrets, no raw logs, no code dumps, and no long explanations.

## If something does not work

If agents cannot find `relay`, open Settings and install the CLI to `/usr/local/bin/relay`, then make sure `/usr/local/bin` is on your `PATH`. If you did not install it, copy the bundled CLI path from Settings and use that full path in your agent instructions.

If relays queue but do not speak, check whether TSRS is focused, muted, not in Live mode, or waiting because the microphone appears active. You can always use `relay list` to see what is waiting.

The local queue lives on your Mac at:

```text
~/Library/Application Support/Tri-State Relay Service/relay.db
```

TSRS also keeps a local aggregate spoken-usage counter in that database. It records daily buckets by provider, model, voice, and line with relay counts and character counts, but it does not store another copy of message text. `relay status` includes a `spokenUsage` summary so you can estimate future text-to-speech costs without reading relay contents.

You usually do not need to touch that file. It is listed here only so you know where your local queue data lives.

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

The direct-download app uses app-owned playback and can use installed macOS voices that work with the system speech engine. Natural voices are favored when available, and System Default remains available.

## When many updates pile up

When you are focused on one line, other lines may collect several updates. TSRS can keep this manageable by showing or playing the latest useful update for an inactive line instead of making you hear every stale intermediate message.

For many people, the default behavior is enough. You can work on one line, then switch lines when you are ready to catch up.

## Advanced: the inactive-line Combiner

The Combiner is for people who want an external agent or command to summarize many queued inactive-line updates into one short relay. It is useful when you run several agents at once and want a catch-up that sounds like a concise teammate summary.

You can inspect the Combiner from the CLI and change it through the advanced config command:

```sh
relay combiner
relay config set --combiner-command 'llm prompt <input> --system <system> --no-stream --no-log'
relay config set --combiner-command none
```

The command template receives the inactive-line updates as input and should return one safe, short message. Leave the Combiner unset if you prefer the simpler latest-update behavior.

Combiner output should follow the same rules as any other relay: no secrets, no raw logs, no code dumps, and no long explanations.

## Advanced: BYO voice command

The direct-download app can use a configured voice command to generate an audio file for TSRS to play. This is modeled after `say -o`: the command must write audio to an output path and must not speak directly. TSRS still owns playback, mute/focus/live safety checks, and delivered-state marking.

Advanced voice, inactive-line combiner, and cleanup retention settings live in `~/Library/Application Support/Tri-State Relay Service/config.toml`. On upgrade, TSRS creates this file once from existing 1.1.2 SQLite settings. If the file already exists, TSRS preserves it and treats it as the source of truth for those advanced settings.

```sh
relay config path
relay config show
relay config validate
relay config set --voice-command '/usr/bin/say -f <text-file> -o <output-file>'
```

If `config.toml` is malformed or uses unsupported placeholders, `relay config validate` reports the error. Playback fails quiet while the config is invalid: relays stay queued, Settings/status surface the config error, and TSRS does not claim messages for speech until the config is fixed.

You can also edit the command in Settings > Voice. The default template uses `/usr/bin/say`; the Speechify example stays commented until you choose to enable it.

Supported placeholders are inserted as single arguments, not shell-expanded:

| Placeholder | Meaning |
| --- | --- |
| `<text-file>` | UTF-8 file containing the relay text to synthesize |
| `<output-file>` | Audio file path TSRS will play after the command exits |
| `<voice-id>` | The provider voice id for the relay line when a provider is active; otherwise the selected TSRS voice name |
| `<app-bin>` | The app bundle's `Contents/MacOS` directory |

This makes cloud or local model wrappers possible later, including an ElevenLabs-backed CLI, without putting provider-specific API code into the app. The wrapper should read the text file, write an audio file, and exit nonzero if synthesis fails.

The default `/usr/bin/say` path does not use provider line voices. It keeps using System Default unless you deliberately replace the voice command with a provider wrapper.

The direct-download app includes two optional provider helpers. The Speechify helper talks to the Speechify API when you provide an API key. The Kokoro helper talks to a user-installed local Kokoro environment and keeps a same-user local helper server warm for faster follow-up relays. Neither helper is required for normal TSRS usage.

### Speechify example

The direct-download app includes a Speechify-compatible wrapper at `<app-bin>/speechify`. Start with the [Speechify API docs](https://docs.speechify.ai/) to understand the API, and use the [Speechify dashboard](https://platform.speechify.ai/) to sign up and manage API keys. Store your API key in Keychain yourself:

```sh
security add-generic-password -a "$USER" -s TSRS_SPEECHIFY_API_KEY -w "paste-api-key-here" -U
```

Edit `config.toml` to opt into Speechify line voices:

```toml
[voice]
provider = "speechify"
command = "<app-bin>/speechify --text-file <text-file> --output-file <output-file> --voice-id <voice-id> --keychain-service TSRS_SPEECHIFY_API_KEY"

[speechify]
default_voice_id = "george"
auto_assign_line_voices = true
catalog_command = "<app-bin>/speechify voices --keychain-service TSRS_SPEECHIFY_API_KEY"
assignment_strategy = "stable-hash"

[speechify.line_voices]
Brain = "george"
"Tri-State Relay Service" = "henry"
```

When a line has an explicit mapping, TSRS substitutes that id into `<voice-id>`. When a new line has no mapping and `auto_assign_line_voices` is true, TSRS runs `catalog_command`, picks a stable id from the returned catalog, writes it once to `[speechify.line_voices]`, and reuses that sticky mapping after restart. The write reloads the current TOML first and saves normalized TOML, so comments in the file are not preserved. If the catalog command fails or returns no ids, TSRS falls back to `default_voice_id` and still lets the wrapper synthesize audio.

The wrapper calls `POST https://api.speechify.ai/v1/audio/speech`, decodes the returned audio, and writes it to `<output-file>`. It serializes synthesis requests for the configured account, retries 429 responses with Speechify's `Retry-After` guidance when present, and reports safe rate-limit diagnostics such as request ids and rate-limit headers. Its `voices` subcommand calls `GET https://api.speechify.ai/v1/voices`, caches voice ids locally for a short TTL, and prints voice ids only. It never speaks directly, stores API keys in TOML, or caches generated relay audio.

### Kokoro example

The direct-download app includes a Kokoro-compatible wrapper at `<app-bin>/kokoro`, but it does not bundle Kokoro, Python packages, model weights, or voices. Kokoro is a local open-weight TTS stack with a large ML dependency tree, so TSRS only provides the wrapper and leaves installation as an explicit local choice.

One tested macOS setup uses `uv`, Python 3.11, Homebrew `espeak-ng`, and Kokoro 0.9.4:

```sh
brew install uv espeak-ng
uv venv --python 3.11 ~/.local/share/tsrs-kokoro/venv
uv pip install --python ~/.local/share/tsrs-kokoro/venv/bin/python kokoro==0.9.4
```

If you want to test synthesis before changing TSRS config:

```sh
echo "Tri-State Relay Service can use Kokoro as an optional local voice." >/tmp/tsrs-kokoro-test.txt
~/.local/share/tsrs-kokoro/venv/bin/python -m kokoro --input-file /tmp/tsrs-kokoro-test.txt --output-file /tmp/tsrs-kokoro-test.wav --voice af_heart
```

The first run may download Kokoro-82M model files from Hugging Face and the spaCy English model. If you use the TSRS wrapper with a venv, pass `--venv` so the wrapper sets `VIRTUAL_ENV` for first-run model setup:

```toml
[voice]
provider = "kokoro"
command = "<app-bin>/kokoro --venv ~/.local/share/tsrs-kokoro/venv --text-file <text-file> --output-file <output-file> --voice-id <voice-id>"

[kokoro]
default_voice_id = "af_heart"
auto_assign_line_voices = true
catalog_command = "<app-bin>/kokoro voices --language a"
assignment_strategy = "stable-hash"

[kokoro.line_voices]
Brain = "af_heart"
"Tri-State Relay Service" = "am_puck"
```

`<app-bin>/kokoro voices --language a` returns American English Kokoro voice ids as JSON, so TSRS can assign sticky per-line voices without importing Kokoro or downloading model files. The synthesis command reads `<text-file>`, invisibly starts a same-user local Kokoro server when needed, asks that server to keep `KPipeline` loaded across relays, and writes WAV bytes to the audio path TSRS asked for. If Kokoro is not installed, the command exits nonzero with the setup commands above instead of downloading packages itself.

The helper never speaks directly, installs Python packages, stores relay audio, or modifies TSRS queue state. It keeps only runtime files under `~/Library/Application Support/Tri-State Relay Service/kokoro/` for the local Unix socket, PID file, and helper log. When TSRS reloads a config whose active `[voice] provider` is no longer `kokoro`, the app asks the bundled helper to stop that local server. The server also exits after an idle timeout.

TSRS does not bundle Kokoro source, Kokoro Python packages, the Kokoro-82M model weights, voice files, spaCy models, or dependency caches. The Kokoro Python package is Apache-2.0, and the Kokoro-82M Hugging Face model card declares `license: apache-2.0` for the model weights. If you redistribute a prebuilt Kokoro environment, model cache, or voice assets yourself, carry the Kokoro Apache-2.0 license and the notices/licenses for its dependencies and model assets with that redistributed bundle. The stock TSRS direct app only ships the integration helper shown here.

Useful Kokoro diagnostics:

```sh
<app-bin>/kokoro server status
<app-bin>/kokoro server stop
<app-bin>/kokoro --self-test
```

The first Kokoro relay after starting the helper may take several seconds while Python imports Kokoro and loads the model. Follow-up relays should be much faster while the helper server is warm. If synthesis fails, check `relay status` for `voiceCommandLastError` and inspect `~/Library/Application Support/Tri-State Relay Service/kokoro/kokoro.log`.

## Advanced: local cleanup retention

Settings includes an Advanced panel for local cleanup retention. The value is stored in minutes and defaults to `525600`, which is 365 days.

On app startup, TSRS removes old terminal relay rows and spoken-usage buckets older than the configured retention. It also sweeps stale `tsrs-voice-*` temporary audio directories from interrupted BYO voice command runs after a short fixed grace period. Current queued relays are not pruned by this retention cleanup.

## If something does not work

If agents cannot find `relay`, open Settings and install the CLI to `/usr/local/bin/relay`, then make sure `/usr/local/bin` is on your `PATH`. If you did not install it, copy the bundled CLI path from Settings and use that full path in your agent instructions.

If relays queue but do not speak, check whether TSRS is focused, muted, not in Live mode, or waiting because the microphone appears active. You can always use `relay list` to see what is waiting.

If Kokoro is configured but nothing speaks, run `relay status` and look at `voiceCommandLastError`. If Kokoro is not installed, the helper reports the local setup commands instead of trying to install packages. If the helper server looks stale, run `<app-bin>/kokoro server stop`; the next Kokoro relay starts it again.

The local queue lives on your Mac at:

```text
~/Library/Application Support/Tri-State Relay Service/relay.db
```

TSRS also keeps a local aggregate spoken-usage counter in that database. It records daily buckets by provider, model, voice, and line with relay counts and character counts, but it does not store another copy of message text. `relay status` includes a `spokenUsage` summary so you can estimate future text-to-speech costs without reading relay contents.

You usually do not need to touch that file. It is listed here only so you know where your local queue data lives.

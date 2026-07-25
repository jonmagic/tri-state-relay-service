# Changelog

## 2.1.1 - Stuck playback recovery and fast-forward

- Fixed playback hanging indefinitely when a speech subprocess never exits, which left the menu bar showing playing with no audio until the app was restarted.
- Added a playback watchdog that force-recovers stalled playback, terminating the stalled process, resetting voice-command resolution, the audio player, and the synthesizer, and marking the stalled relay failed.
- The stall deadline scales with message length, and each playback phase gets its own deadline, so a long relay is never cut off mid-sentence and a slow voice synthesis never eats the budget for the audio that follows.
- Playback callbacks now verify that they still own the process, audio player, or utterance that produced them, so a late callback from recovered playback can no longer mark or interrupt the relay that replaced it.
- Stall recovery waits for the cancelled speech process to exit before starting the next relay, so recovery cannot briefly overlap two voices.
- Fixed the inactive-line combiner requeueing a relay that was skipped or cleared while the combiner was still running.
- Fixed `relay clear` so it also removes relays stuck in `speaking` and stops audio that is currently playing, instead of leaving the app speaking a relay that was already cleared.
- Added `relay ff [--line <line>]` to fast-forward past every queued relay by marking it `skipped` instead of deleting it, so skipping the backlog no longer destroys relay history.
- Updated the app and CLI version to 2.1.1.

## 2.1.0 - Optional local Kokoro voices

- Added a Kokoro-compatible voice helper for direct-download builds that can use a user-installed local Kokoro venv without bundling Kokoro packages, model weights, voices, spaCy models, or caches.
- Added an invisible same-user Kokoro helper server that keeps `KPipeline` warm across relays and automatically shuts down when the active voice provider is no longer `kokoro`.
- Kept the Kokoro helper server alive when a client disconnects before reading its response.
- Changed BYO voice output to a Core Audio-friendly `relay.audio` path so Kokoro can return WAV bytes without conversion.
- Documented the optional Kokoro install path, missing-install failure mode, provider TOML example, local helper lifecycle, and Apache-2.0 Kokoro package/model license boundary.
- Updated the app and CLI version to 2.1.0.

## 2.0.0 - Advanced config and custom voices

- Made `relay config` the single CLI surface for TOML-backed advanced configuration.
- Added `relay config set --voice-command`, `--combiner-command`, and `--cleanup-retention-minutes`.
- Removed the duplicate `relay settings` command and made `relay combiner` read-only; use `relay config set --combiner-command` to change the combiner.
- Preserved 1.1.2 upgrade migration from SQLite settings into `config.toml`.
- Added BYO voice command playback while keeping app-owned speech, mute, Focus, Ready, and Live safeguards.
- Added Speechify-compatible voice synthesis support for the direct-download app, including Keychain-based API-key lookup and rate-limit handling.
- Added provider voice configuration with sticky per-line voice IDs and optional stable assignment for new lines.
- Added local spoken-usage counters by provider, model, voice, and line so custom voice cost can be estimated without storing another copy of relay text.
- Added cleanup controls for old relay rows, spoken-usage buckets, and temporary voice audio files.
- Added Settings UI capture and roundtrip verification for release-quality Settings changes.

## 1.1.2 - App wake and status refresh

- Added Darwin notifications so the app wakes promptly when the CLI changes the relay queue or playback state.
- Optimized relay status refresh queries to reduce work while keeping Settings and menu state current.
- Added Live mode to the overview docs.
- Updated the app and CLI version to 1.1.2.

## 1.1.1 - Inactive-line combiner fix

- Fixed configured inactive-line combiners so the direct-download app executes the configured command instead of always using latest-only replacement.
- Kept combiner execution shell-free, bounded by timeout, and validated through JSON output before queuing the combined relay.
- Preserved latest-only fallback when no combiner is configured, when native combiner execution fails, or in the App Store-safe profile.
- Added regression coverage for CLI and native app enqueue paths, placeholder handling, and active-line changes while combining.

## 1.1.0 - Live playback mode

- Added Live mode for automatic playback of new relays.
- Plays queued relays in bounded batches by line so chatty lines do not starve other lines.
- Added Start Live and Stop Live menu controls.
- Added a green-dot menu bar status for Live mode.
- Updated the app and CLI version to 1.1.0.

## 1.0.0 - Initial public release

- Shipped a signed direct-download macOS app.
- Bundled the `relay` CLI with matching app and CLI versioning.
- Added first-start setup for CLI installation, shortcut selection, voice selection, and Open at Login.
- Added Focus, Ready, and Mute queue controls with app-owned playback.

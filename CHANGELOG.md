# Changelog

## 1.1.1 - Inactive-line combiner fix

- Fixed configured inactive-line combiners so direct builds execute the configured command instead of always using latest-only replacement.
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

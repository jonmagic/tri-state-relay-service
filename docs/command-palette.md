# Command palette

TSRS uses a Raycast-style command palette for fast keyboard-first relay actions.

## Product intent

The palette is the primary interactive UI for relay actions:

1. A single global hotkey opens the palette.
2. The palette opens with `play next` prefilled.
3. The prefilled text is selected, so pressing Return immediately runs Play
   Next, while typing anything else replaces the text and starts a new search.
4. Search filters available actions and lines.
5. Return executes the selected action.
6. Return on a line opens recent messages for that line.
7. Escape returns from a line to the root list, or closes the palette at the root.
8. Arrow keys move selection.
9. Opening the palette never claims or speaks a relay by itself.

This replaced the old "hotkey immediately plays next" behavior and the nested
right-click menu. Right click opens the command palette with an empty query;
the configured keyboard shortcut opens it with `play next` selected. The default
shortcut is Control-Option-Command-Space.

Left click on the menu bar icon should remain the fastest pointer path for Play
Next. The command palette changes the keyboard-first path, not the left-click
behavior.

## Initial action set

Global actions:

1. Play Next
2. Focus
3. Mute
4. Unmute
5. Open Settings

Line rows show the line name and queued count only. Return on a line opens its Messages list with up to 20 recent messages: queued messages first in playback order, then delivered messages newest first.

Message rows expose the message body intentionally inside the selected line. Compact rows show status, time, and a preview. The selected row expands inline with the full message and action hints. Return replays the selected message through the app-owned playback path; Command-C copies the raw message text.

## Search behavior

Filtering should be forgiving and predictable:

1. Case-insensitive substring matching is enough for the first slice.
2. Match action labels, aliases, and line names.
3. Keep Play Next first when the query is exactly or initially `play next`.
4. Root search should not match hidden message bodies inside a line.

Future slices can add fuzzy scoring, recency, and aliases once the basic command
model is stable.

## UI shape

Use an AppKit floating panel or borderless window with:

1. Search field at top.
2. Results list below.
3. Optional subtitle text for line and state context.
4. Relay message bodies only inside a selected line's Messages list.

The first implementation can be a compact native AppKit window rather than a
pixel-perfect Raycast clone. The important behavior is keyboard-first search and
execution.

The palette must be careful about focus. TSRS is a menu bar accessory app, so
the palette should either use a non-activating panel or capture and restore the
previous frontmost app after execution/cancel. It should feel like a quick
overlay, not like switching into a separate app.

Keyboard handling must be explicit. The search field should intercept Return,
Escape, Up, and Down for execution, cancel, and selection movement instead of
letting the text field consume those keys as normal editing commands.

Root result subtitles should only include safe context such as queued count or active-line state. Do not show relay message bodies at the root.

## Current implementation

1. Commands are modeled in Swift and rendered by the command palette.
2. The native AppKit palette supports search, selection, Return, Escape, Command-C for selected messages, mouse hover/click selection, scroll selection, and line message drill-in.
3. The Setup panel shortcut recorder opens the palette with `play next` selected;
   the default is Control-Option-Command-Space.
4. Right click opens the palette with an empty query.
5. Left click remains Play Next.
6. Control-Option-Command-V is intentionally rejected and not registered as a global palette shortcut.
7. The compact menu remains focused on essential status/settings actions.

Shortcut mapping and validation are modeled separately from AppKit so tests can
verify the default, custom recorded shortcuts, reserved-combo rejection, and
persisted shortcuts without registering a real global hotkey.

## Guardrails

1. Preserve app-owned playback and single-writer queue state.
2. Do not expose relay message text in palette results by default.
3. Keep source actions line-scoped.
4. Use `scripts/build-macos.sh direct` and `scripts/restart-macos-app.sh` for every
   app-visible iteration.
5. Keep command availability testable without AppKit UI. Prefer pure functions
   over status snapshots for command labels, aliases, enabled state, and
   ordering.
6. Execute palette actions through the same model/native playback paths used by
   the existing menu and left-click handlers.
7. Explicit replay from a delivered message must respect mute and current playback guards. Replaying a queued message must claim that exact queued message instead of speaking raw text and leaving it queued.

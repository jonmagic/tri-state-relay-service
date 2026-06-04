# Command palette

TSRS uses a Raycast-style command palette for fast keyboard-first relay actions.

## Product intent

The palette is the primary interactive UI for relay actions:

1. A single global hotkey opens the palette.
2. The palette opens with `play next` prefilled.
3. The prefilled text is selected, so pressing Return immediately runs Play
   Next, while typing anything else replaces the text and starts a new search.
4. Search filters available actions and line-scoped actions.
5. Return executes the selected action.
6. Escape closes the palette without changing queue state.
7. Arrow keys move selection.
8. Opening the palette never claims or speaks a relay by itself.

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

Line-scoped actions:

1. Make Current Line: `<line>`
2. Play Next: `<line>`
3. Clear Queue: `<line>`
4. Skip Next: `<line>`
5. Replay Last: `<line>`
6. Acknowledge Last: `<line>`
7. Clear Delivered: `<line>`
8. Reveal Source: `<line>`
9. Copy Source: `<line>`

Only show actions that are currently meaningful. For example, do not show
line-scoped `Clear Queue` when a line has no queued relays, and do not show
`Replay Last` when there is no delivered relay for that line.

## Search behavior

Filtering should be forgiving and predictable:

1. Case-insensitive substring matching is enough for the first slice.
2. Match action labels, aliases, and line names.
3. Keep Play Next first when the query is exactly or initially `play next`.
4. Prefer active-line actions over inactive-line actions when scores tie.

Future slices can add fuzzy scoring, recency, and aliases once the basic command
model is stable.

## UI shape

Use an AppKit floating panel or borderless window with:

1. Search field at top.
2. Results list below.
3. Optional subtitle text for line and state context.
4. No relay message body in the list unless a later privacy decision allows it.

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

Result subtitles should only include safe context such as line name, queued
count, delivered count, failed count, or active-line state. Do not show relay
message bodies in palette results by default.

## Current implementation

1. Commands are modeled in Swift and rendered by the command palette.
2. The native AppKit palette supports search, selection, Return, Escape, and
   line-scoped command groups.
3. The Settings > Shortcut recorder opens the palette with `play next` selected;
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

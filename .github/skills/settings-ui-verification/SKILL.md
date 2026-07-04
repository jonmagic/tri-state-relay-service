---
name: settings-ui-verification
description: Verify Tri-State Relay Service Settings and first-start UI changes with the safe debug opener, screenshots, Accessibility-backed interaction smoke checks, and no playback side effects.
---

# Settings UI Verification

Use this skill when changing TSRS Settings, first-start setup, Settings accessibility identifiers, Settings screenshots, UI automation, or any feature whose correctness depends on rendered AppKit behavior.

## Rules

1. Keep normal TSRS usage free of Accessibility, Input Monitoring, and Screen Recording requirements.
2. Use the app-owned debug opener only: `relay debug open-settings --panel <panel>`. It may show Settings and select a panel, but must not enqueue, claim, preview, speak, toggle Live, or alter Mute/Focus.
3. For app-visible Swift changes, run `scripts/build-macos.sh direct` and `scripts/restart-macos-app.sh` before screenshot verification.
4. Prefer `scripts/capture-settings-ui.sh` over ad hoc AppleScript. It writes gitignored artifacts under `.artifacts/settings-ui/<timestamp>/`.
5. Use `TSRS_SETTINGS_UI_REQUIRE_INTERACTIONS=1 scripts/capture-settings-ui.sh` when the change depends on Accessibility-backed field focus, sidebar selection, copy buttons, or first-start controls.
6. Do not press controls that could speak, enable Live, change Mute/Focus unexpectedly, install login items, or make destructive persistence changes without explicit human approval.

## Workflow

1. Rebuild and restart the direct app when Swift UI code changed.
2. Run the screenshot capture workflow.
3. Inspect the artifact directory, including `interaction-smoke.txt` when interaction checks run.
4. Include the artifact path and whether Accessibility-backed checks ran in the handoff.

## Commands

```sh
scripts/build-macos.sh direct
scripts/restart-macos-app.sh
scripts/capture-settings-ui.sh
TSRS_SETTINGS_UI_REQUIRE_INTERACTIONS=1 scripts/capture-settings-ui.sh
```

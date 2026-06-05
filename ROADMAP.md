# Roadmap

Tri-State Relay Service is useful today as a local macOS relay inbox for coding-agent status updates. This roadmap captures likely directions without promising timelines.

## Better agent integrations

The current integration model is intentionally simple: put one short TSRS instruction near the top of global or project agent instructions, and have agents call the local `relay` CLI at meaningful work transitions.

That has been working well for personal use, but there is room for smoother integrations:

1. Agent hook examples for common CLI agents.
2. Project templates that set line naming and update etiquette.
3. MCP tools that let compatible agents enqueue relays without hand-writing shell commands.
4. Safer defaults for when agents should send `update`, `complete`, `blocked`, or `needs-input` relays.

The goal is not to make agents chatty. The goal is to make important state changes easy to notice without watching every terminal.

## Per-line voices

Different voices per line would make TSRS easier to understand at a glance: your ear could learn which work stream is speaking before the message even finishes.

The local-first version should wait for better local voice technology or improved Apple system voices. TSRS should not require a cloud voice provider for the core product.

A future paid or Pro version could optionally integrate a provider such as ElevenLabs for people who want richer per-line voices and are comfortable with the privacy and cost tradeoff.

## Backlog recovery

When many lines have queued updates, TSRS should help summarize what matters instead of making you hear every stale message.

Possible directions:

1. Better inactive-line rollups.
2. A catch-up view for lines that accumulated several relays.
3. Explicit blocked/needs-input prioritization.
4. Local-first summaries where possible, with opt-in external summarizers for power users.

## More source-context actions

TSRS already tracks line-scoped source context. Future versions could make it easier to jump back to the right terminal, editor, browser tab, or project folder.

Any source action should stay user-initiated and line-scoped so TSRS does not act on the wrong agent context.

## Distribution polish

The active distribution direction is signed direct download with a standard installable `relay` CLI.

Future polish could include clearer update checks, better first-run diagnostics, and release notes that explain compatibility, voice behavior, and any Pro/customization features.


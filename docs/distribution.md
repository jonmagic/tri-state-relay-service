# Distribution direction

TSRS is moving toward a signed direct-download Mac app with a standard local
CLI. The Mac App Store is no longer the primary release path.

This keeps the product aligned with its core value: local developer tooling
that agents can integrate with through a normal command-line interface. It
also leaves room for Pro features that would be awkward or impossible in a
sandboxed App Store build.

## Preferred release model

1. Ship a signed and notarized direct-download app.
2. Bundle or install the `relay` CLI for agent integrations.
3. Keep the relay queue local-first.
4. Use native macOS APIs wherever practical.
5. Move app behavior toward Xcode/Swift over time instead of relying on Perry-built helpers long term.
6. Add Pro licensing outside the App Store when needed.

`relay` is the CLI name.

## Payment model

When Pro licensing is needed, prefer a direct-download license-key flow:

1. User buys Pro through a web checkout.
2. Checkout provider issues or triggers a license key.
3. The app accepts the license key and unlocks Pro behavior.
4. The app can validate locally with occasional online checks.
5. Core relay behavior stays local-first.

Good provider options:

1. Paddle or Lemon Squeezy if merchant-of-record, tax/VAT handling, receipts, and license-key infrastructure matter more than maximum control.
2. Stripe Checkout if maximum control matters more than operational simplicity.

Do not add StoreKit unless the App Store becomes a primary target again.

## Native app direction

Direct download does not mean “keep shelling out forever.” Prefer moving
normal app behavior into Swift/Xcode and native macOS APIs:

1. Native speech through AVFoundation or another current Apple API.
2. Native copy/open/source actions through AppKit APIs.
3. Native settings UI.
4. Native queue/storage access when the persistence boundary is ready.
5. A standard CLI for agent enqueueing and automation.

Perry remains useful for the current CLI bridge, but the long-term app
direction is Swift/Xcode-first.

## Relationship to App Store-safe profile

The `app-store` profile remains useful as a safety harness and review-risk
reduction exercise, but it is not the main release target. Keep the profile
when it helps enforce good boundaries:

1. No arbitrary command execution from the app surface.
2. Native app-owned playback.
3. Native source actions.
4. Clear capability reporting.

Do not let App Store constraints block direct-download Pro features that fit
the product and are safe for local developer tooling.

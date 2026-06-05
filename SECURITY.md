# Security policy

## Supported versions

Tri-State Relay Service is pre-1.0 and does not yet have a long-term supported release line. Use the latest public source or latest signed direct-download release when releases are available.

## Reporting vulnerabilities

Do not report vulnerabilities in public issues if the report includes secrets, private notification content, relay queue contents, logs with credentials, personal transcripts, signing material, or exploit details that would put users at risk.

Preferred private path: use GitHub private vulnerability reporting for this repository when it is enabled.

If private vulnerability reporting is not enabled yet, wait for a maintainer-provided disclosure address before sharing sensitive details publicly.

## Scope

Security-sensitive areas include:

1. Any path that could cause the CLI to speak directly.
2. App-owned playback claim and queue state transitions.
3. Ready, Focus, and Mute behavior.
4. Message validation and unsafe content rejection.
5. SQLite queue persistence and local data exposure.
6. App startup, Open at Login, permissions, signing, notarization, and release packaging.
7. External command configuration for inactive-line combination.

## Public issue hygiene

When reporting non-sensitive bugs publicly, sanitize logs and examples. Do not include real relay messages, private notification text, queue database files, tokens, customer content, or full terminal output.


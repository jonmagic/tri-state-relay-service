# Inactive line message combination

When messages arrive from a line that is not the active listening line,
TSRS should avoid building a noisy backlog. Normal incremental updates from
that line should collapse into one pending message. Important messages should
remain explicit.

Use an LLM only on short, intentionally-authored TSRS messages that have
already passed queue validation. Never send raw terminal output, code, logs,
secrets, private data, or file contents to the LLM.

## Command setting

The combiner is configured by the `inactive_line_combiner_command` setting.
Open Settings from the menu bar app, or use:

```sh
relay combiner
relay combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
relay combiner --command none
```

The default is a fully commented template that requires no LLM. When the
template has no non-comment command, inactive lines keep only the latest
relevant message for the line.

The command is parsed into argv without a shell. Placeholders are inserted
as single argv values:

- `<input>`: JSON input shape for the inactive-line update.
- `<system>`: the combiner system prompt.

Pipes, redirects, command substitution, and shell expansion are
intentionally unsupported.

`apfel` uses local Apple Intelligence:

```sh
apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>
```

`llm` uses the configured `llm` CLI default model:

```sh
llm prompt <input> --system <system> --no-stream --no-log
```

Run the manual eval suite to compare both tools:

```sh
npm run eval:inactive-line
```

Current baseline: `llm` passes the included fixtures more reliably than
`apfel`. Keep both in the eval suite because local Apple Intelligence may
improve, but prefer `llm` for inactive-line combination until `apfel` passes
the blocker, completion, and duplicate-update fixtures. Use `none` when no
CLI LLM tool is configured or desired.

## Input shape

Provide the line name, active line, existing pending digest if one exists,
and the incoming messages in oldest-to-newest order.

```json
{
  "activeLine": "Tri-State Relay Service",
  "inactiveLine": "Hamzo",
  "existingPendingMessage": "3 updates from Hamzo. Latest: Tests are running.",
  "incoming": [
    {
      "type": "update",
      "priority": "normal",
      "message": "I found the failing test and am narrowing the fixture."
    },
    {
      "type": "blocked",
      "priority": "high",
      "message": "I need a human decision on whether to keep legacy behavior."
    }
  ]
}
```

## Output shape

The model must return exactly one JSON object:

```json
{
  "action": "drop|replace|promote",
  "type": "update|complete|blocked",
  "priority": "low|normal|high",
  "message": "Short message safe to queue or speak."
}
```

- `drop`: discard the new inactive-line update.
- `replace`: replace that line's current pending digest with `message`.
- `promote`: replace the digest with an important message that should be easy
  for the user to pull from outside the active line.

The message must be 160 characters or fewer.

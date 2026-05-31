# Inactive line message combination

When messages arrive from a line that is not the active listening line,
TSRS should avoid building a noisy backlog. Normal incremental updates from
that line should collapse into one pending message. Important messages should
remain explicit.

Use an LLM only on short, intentionally-authored TSRS messages that have
already passed queue validation. Never send raw terminal output, code, logs,
secrets, private data, or file contents to the LLM.

## Tool preference

The combiner is configured by the `inactive_line_combiner` setting:

```sh
voicemail combiner --tool none
voicemail combiner --tool llm
voicemail combiner --tool apfel
```

`none` is the default and requires no LLM. When set to `none`, inactive
lines should not attempt a rollup; they should keep only the latest relevant
message for the line. Use an LLM only when the setting is `llm` or `apfel`.

`apfel` uses local Apple Intelligence:

```sh
apfel --system-file docs/prompts/combine-inactive-line.md --max-tokens 160 --temperature 0
```

`llm` uses the configured `llm` CLI default model:

```sh
llm --system "$(cat docs/prompts/combine-inactive-line.md)"
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
  "type": "update|complete|blocked|needs-input",
  "priority": "low|normal|high",
  "message": "Short message safe to queue or speak."
}
```

- `drop`: discard the new inactive-line update.
- `replace`: replace that line's current pending digest with `message`.
- `promote`: replace the digest with an important message that should be easy
  for the user to pull from outside the active line.

The message must be 160 characters or fewer.

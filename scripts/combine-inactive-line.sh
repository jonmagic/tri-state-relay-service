#!/usr/bin/env bash
set -e

TOOL="$1"
INPUT="$2"

if [ -z "$INPUT" ]; then
  # Read from stdin if available, otherwise empty string
  INPUT=$(cat || true)
fi

PROMPT_PATH="docs/prompts/combine-inactive-line.md"

if [ ! -f "$PROMPT_PATH" ]; then
  echo "Error: Prompt file not found at $PROMPT_PATH" >&2
  exit 1
fi

PROMPT=$(cat "$PROMPT_PATH")

if [[ "$TOOL" != "llm" && "$TOOL" != "apfel" ]]; then
  echo "tool must be llm or apfel" >&2
  exit 2
fi

if [[ "$TOOL" == "apfel" ]]; then
  # Use apfel
  OUTPUT=$(apfel --system "$PROMPT" --max-tokens 160 --temperature 0 --output plain "$INPUT" 2>&1) || {
    echo "$OUTPUT" >&2
    exit 1
  }
else
  # Use llm
  OUTPUT=$(llm prompt "$INPUT" --system "$PROMPT" --no-stream --no-log 2>&1) || {
    echo "$OUTPUT" >&2
    exit 1
  }
fi

# Extract JSON from output (everything from first { to last })
JSON=$(echo "$OUTPUT" | awk '/\{/{p=1} p; /\}/{p=0}' | sed -n '1h;1!H;${g;s/.*\(\{.*\}\).*/\1/s;p;}')

# Fallback basic extraction if awk/sed fails
if [ -z "$JSON" ]; then
  JSON=$(python3 -c "
import sys
output = sys.stdin.read()
start = output.find('{')
end = output.rfind('}')
if start >= 0 and end > start:
    print(output[start:end+1])
" <<< "$OUTPUT")
fi

if [[ -z "$JSON" || "$JSON" != *"{"* ]]; then
  echo "No JSON object in combiner output: $OUTPUT" >&2
  exit 1
fi

echo "$JSON"

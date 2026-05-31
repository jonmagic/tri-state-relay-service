export interface CommandInvocation {
  command: string
  args: string[]
}

export const defaultInactiveLineCombinerCommand = `# Inactive line combiner command.
# Leave this commented to use latest-only inactive-line behavior.
# The command must print a JSON object: {"action":"replace|promote|drop","type":"update|blocked|complete","priority":"low|normal|high","message":"short voicemail"}
# Placeholders are inserted as single argv values, not shell-expanded.
#
# llm CLI: https://github.com/simonw/llm
# llm prompt <input> --system <system> --no-stream --no-log
#
# apfel CLI: https://github.com/Arthur-Ficial/apfel
# apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>`

export const defaultSpeechCommand = `# Speech command.
# /usr/bin/say ships with macOS, so no extra install is required.
# Placeholders are inserted as single argv values, not shell-expanded.
/usr/bin/say <message>`

export function resetBlankCommand(value: string, fallback: string): string {
  return value.trim() === '' ? fallback : value
}

export function commandIsEnabled(template: string): boolean {
  return commandTokens(template).length > 0
}

export function buildCommandInvocation(template: string, placeholders: Record<string, string>): CommandInvocation | undefined {
  const tokens = commandTokens(template)

  if (tokens.length === 0) {
    return undefined
  }

  const [command, ...args] = tokens.map((token) => placeholders[token] ?? token)
  return { command, args }
}

function commandTokens(template: string): string[] {
  const commandText = template
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line !== '' && !line.startsWith('#'))
    .join(' ')

  return tokenize(commandText)
}

function tokenize(value: string): string[] {
  const tokens: string[] = []
  let current = ''
  let quote: '"' | "'" | undefined

  for (let index = 0; index < value.length; index += 1) {
    const char = value[index]

    if (quote !== undefined) {
      if (char === quote) {
        quote = undefined
      } else if (char === '\\' && quote === '"' && index + 1 < value.length) {
        index += 1
        current += value[index]
      } else {
        current += char
      }
      continue
    }

    if (char === '"' || char === "'") {
      quote = char
      continue
    }

    if (/\s/.test(char)) {
      if (current !== '') {
        tokens.push(current)
        current = ''
      }
      continue
    }

    if (char === '\\' && index + 1 < value.length) {
      index += 1
      current += value[index]
      continue
    }

    current += char
  }

  if (quote !== undefined) {
    throw new Error('unterminated quote in command template')
  }

  if (current !== '') {
    tokens.push(current)
  }

  return tokens
}

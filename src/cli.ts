#!/usr/bin/env node
import { spawnSync } from 'node:child_process'

import { buildCommandInvocation, commandIsEnabled } from './core/command-template.ts'
import { messageTypes, priorities } from './core/message.ts'
import { type InactiveLineCombineInput, type InactiveLineCombineResult, VoicemailStore } from './storage/store.ts'

interface ParsedCommand {
  command: string
  args: string[]
  flags: Record<string, string>
}

const store = new VoicemailStore()

try {
  const parsed = parseArgs(process.argv.slice(2))
  run(parsed)
} finally {
  store.close()
}

function run(parsed: ParsedCommand): void {
  if (parsed.command === 'enqueue') {
    const voicemail = store.enqueueWithLinePolicy({
      line: requiredFlag(parsed.flags, 'line'),
      message: requiredFlag(parsed.flags, 'message'),
      type: parsed.flags.type,
      priority: parsed.flags.priority,
      session: parsed.flags.session,
      app: parsed.flags.app,
      cwd: parsed.flags.cwd,
      url: parsed.flags.url,
    }, inactiveLineCombiner())

    console.log(voicemail === undefined ? 'dropped inactive line update' : `queued #${voicemail.id} ${voicemail.line}: ${voicemail.message}`)
    return
  }

  if (parsed.command === 'list') {
    const state = store.getState()
    console.log(`mode=${state.mode} muted=${state.muted}`)

    for (const voicemail of store.list()) {
      console.log(`#${voicemail.id} [${voicemail.status}] [${voicemail.priority}] ${voicemail.line}: ${voicemail.message}`)
    }
    return
  }

  if (parsed.command === 'status') {
    const state = store.getState()
    const counts = store.countByStatus()
    const source = store.latestSourceContext()
    const lineSources = Object.fromEntries(store.latestSourceContextsByLine().map((source) => [source.line, source]))
    const lines = store.lineSummaries()
    const overview = store.queueOverview()

    console.log(JSON.stringify({
      mode: state.mode,
      muted: state.muted,
      inactiveLineCombiner: state.inactiveLineCombiner,
      inactiveLineCombinerCommand: state.inactiveLineCombinerCommand,
      speechCommand: state.speechCommand,
      activeLine: state.activeLine,
      counts,
      queueCount: counts.queued,
      attentionCount: counts.queued + counts.heard + counts.failed,
      overview,
      source,
      lineSources,
      lines,
    }))
    return
  }

  if (parsed.command === 'ready') {
    const state = store.setMode('ready')
    console.log(state.muted ? 'ready queued, but muted is on' : 'ready for one voicemail')
    return
  }

  if (parsed.command === 'focus') {
    store.setMode('focus')
    console.log('focus mode on')
    return
  }

  if (parsed.command === 'mute') {
    store.setMuted(true)
    console.log('muted')
    return
  }

  if (parsed.command === 'unmute') {
    store.setMuted(false)
    console.log('unmuted')
    return
  }

  if (parsed.command === 'clear') {
    console.log(`cleared ${store.clear()} voicemails`)
    return
  }

  if (parsed.command === 'clear-heard') {
    console.log(`cleared ${store.clearHeard(parsed.flags.line)} heard voicemails`)
    return
  }

  if (parsed.command === 'skip-next') {
    const skipped = store.skipNextQueued(parsed.flags.line)
    console.log(skipped === undefined ? 'no queued voicemail to skip' : `skipped #${skipped.id}`)
    return
  }

  if (parsed.command === 'mark-handled') {
    const handled = store.markLatestHeardHandled(parsed.flags.line)
    console.log(handled === undefined ? 'no heard voicemail to mark handled' : `handled #${handled.id}`)
    return
  }

  if (parsed.command === 'replay-last') {
    const replayed = store.replayLatestHeard(parsed.flags.line)
    console.log(replayed === undefined ? 'no heard voicemail to replay' : `queued #${replayed.id} for replay`)
    return
  }

  if (parsed.command === 'clear-line') {
    const line = requiredFlag(parsed.flags, 'line')
    console.log(`cleared ${store.clearQueued(line)} queued voicemails from ${line}`)
    return
  }

  if (parsed.command === 'source') {
    const source = store.latestSourceContext(parsed.flags.line)
    console.log(JSON.stringify(source ?? null))
    return
  }

  if (parsed.command === 'reveal-source') {
    const source = store.latestSourceContext(parsed.flags.line)

    if (source?.cwd === undefined) {
      console.log('no source cwd to reveal')
      return
    }

    spawnSync('/usr/bin/open', [source.cwd], { stdio: 'ignore' })
    console.log(`revealed ${source.cwd}`)
    return
  }

  if (parsed.command === 'copy-source') {
    const source = store.latestSourceContext(parsed.flags.line)
    const value = source?.cwd ?? source?.url

    if (value === undefined) {
      console.log('no source path or URL to copy')
      return
    }

    spawnSync('/usr/bin/pbcopy', { input: value })
    console.log('copied source')
    return
  }

  if (parsed.command === 'state') {
    const state = store.getState()
    console.log(`${state.mode}${state.muted ? ', muted' : ''}, active-line=${state.activeLine ?? 'none'}, inactive-line-combiner=${state.inactiveLineCombiner}`)
    return
  }

  if (parsed.command === 'line') {
    const requested = parsed.args[0] ?? parsed.flags.line

    if (requested === undefined) {
      const state = store.getState()
      console.log(state.activeLine ?? 'none')
      return
    }

    const state = store.setActiveLine(requested)
    console.log(`active line set to ${state.activeLine}`)
    return
  }

  if (parsed.command === 'combiner') {
    const requested = parsed.flags.command ?? parsed.flags.tool

    if (requested === undefined) {
      console.log(store.getState().inactiveLineCombinerCommand)
      return
    }

    const state = store.setInactiveLineCombinerCommand(requested === 'none' ? '' : requested)
    console.log(`inactive line combiner set to ${state.inactiveLineCombiner}`)
    return
  }

  if (parsed.command === 'settings') {
    const state = store.getState()

    if (parsed.flags['combiner-command'] !== undefined) {
      store.setInactiveLineCombinerCommand(parsed.flags['combiner-command'])
    }

    if (parsed.flags['speech-command'] !== undefined) {
      store.setSpeechCommand(parsed.flags['speech-command'])
    }

    const updated = store.getState()
    console.log(JSON.stringify({
      inactiveLineCombiner: updated.inactiveLineCombiner,
      inactiveLineCombinerCommand: updated.inactiveLineCombinerCommand,
      speechCommand: updated.speechCommand,
    }))
    return
  }

  printHelp()
  process.exitCode = parsed.command === 'help' ? 0 : 1
}

function parseArgs(args: string[]): ParsedCommand {
  if (args.length === 0) {
    return { command: 'help', args: [], flags: {} }
  }

  if (!args[0].startsWith('--')) {
    const [command, ...rest] = args
    const parsed = parseCommandArgs(rest)
    return { command, args: parsed.args, flags: parsed.flags }
  }

  return { command: 'enqueue', args: [], flags: parseFlags(args) }
}

function parseCommandArgs(args: string[]): { args: string[], flags: Record<string, string> } {
  const positional: string[] = []
  const flagArgs: string[] = []

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]

    if (arg.startsWith('--')) {
      flagArgs.push(arg)
      const value = args[index + 1]

      if (value !== undefined && !value.startsWith('--')) {
        flagArgs.push(value)
        index += 1
      }
    } else {
      positional.push(arg)
    }
  }

  return { args: positional, flags: parseFlags(flagArgs) }
}

function parseFlags(args: string[]): Record<string, string> {
  const flags: Record<string, string> = {}

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]

    if (!arg.startsWith('--')) {
      throw new Error(`unexpected argument: ${arg}`)
    }

    const key = arg.slice(2)
    const value = args[index + 1]

    if (value === undefined || value.startsWith('--')) {
      throw new Error(`missing value for --${key}`)
    }

    flags[key] = value
    index += 1
  }

  return flags
}

function requiredFlag(flags: Record<string, string>, key: string): string {
  const value = flags[key]

  if (value === undefined || value.trim() === '') {
    throw new Error(`--${key} is required`)
  }

  return value
}

function printHelp(): void {
  console.log(`Usage:
  voicemail --line "Brain" --message "The plan is ready."
  voicemail list
  voicemail ready
  voicemail focus
  voicemail mute
  voicemail unmute
  voicemail clear
  voicemail clear-heard
  voicemail skip-next
  voicemail mark-handled
  voicemail replay-last
  voicemail clear-line --line "Brain"
  voicemail source [--line "Brain"]
  voicemail reveal-source [--line "Brain"]
  voicemail copy-source [--line "Brain"]
  voicemail line
  voicemail line "Tri-State Relay Service"
  voicemail combiner
  voicemail combiner --command "llm prompt <input> --system <system> --no-stream --no-log"
  voicemail settings
  voicemail state
  voicemail status`)
}

function inactiveLineCombiner(): ((input: InactiveLineCombineInput) => InactiveLineCombineResult | undefined) | undefined {
  const state = store.getState()

  if (!commandIsEnabled(state.inactiveLineCombinerCommand)) {
    return undefined
  }

  return (input) => combineInactiveLine(state.inactiveLineCombinerCommand, input)
}

function combineInactiveLine(commandTemplate: string, input: InactiveLineCombineInput): InactiveLineCombineResult | undefined {
  if (!canUseExternalCombiner()) {
    return latestOnlyFallback(input)
  }

  const inputJson = JSON.stringify(input)
  const helperResult = runCombinerCommand(commandTemplate, inputJson)

  if (helperResult !== undefined) {
    return parseCombineResult(helperResult) ?? latestOnlyFallback(input)
  }

  function canUseExternalCombiner(): boolean {
    return process.argv[1] !== undefined && !process.argv[1].endsWith('/voicemail')
  }

  return latestOnlyFallback(input)
}

function runCombinerCommand(commandTemplate: string, inputJson: string): string | undefined {
  const invocation = buildCommandInvocation(commandTemplate, {
    '<input>': inputJson,
    '<system>': combinerSystemPrompt,
  })

  if (invocation === undefined) {
    return undefined
  }

  const result = spawnSync(invocation.command, invocation.args, {
    encoding: 'utf8',
    input: inputJson,
    maxBuffer: 1024 * 1024,
  })

  if (result.status === 0 && result.stdout.trim() !== '') {
    return result.stdout
  }

  return undefined
}

const combinerSystemPrompt = `You combine pending inactive-line agent voicemail updates into one short spoken voicemail.

Return only JSON with this shape:
{"action":"replace|promote|drop","type":"update|blocked|complete","priority":"low|normal|high","message":"short voicemail"}

Prefer one useful update over a transcript. Drop duplicate progress-only updates. Promote blockers or completion when warranted. Keep message <= 160 characters.`

function parseCombineResult(output: string): InactiveLineCombineResult | undefined {
  const json = extractJson(output)

  if (json === undefined) {
    return undefined
  }

  let value: Partial<InactiveLineCombineResult>

  try {
    value = JSON.parse(json) as Partial<InactiveLineCombineResult>
  } catch {
    return undefined
  }

  if (
    (value.action === 'drop' || value.action === 'replace' || value.action === 'promote')
    && typeof value.message === 'string'
    && value.message.trim() !== ''
    && value.message.length <= 160
    && messageTypes.includes(value.type as never)
    && priorities.includes(value.priority as never)
  ) {
    return {
      action: value.action,
      type: value.type,
      priority: value.priority,
      message: value.message,
    } as InactiveLineCombineResult
  }

  return undefined
}

function latestOnlyFallback(input: InactiveLineCombineInput): InactiveLineCombineResult {
  const latest = lastItem(input.incoming)

  if (latest === undefined) {
    return {
      action: 'drop',
      type: 'update',
      priority: 'normal',
      message: `${input.inactiveLine} has no new updates.`,
    }
  }

  return {
    action: 'replace',
    type: latest.type,
    priority: latest.priority,
    message: latest.message,
  }
}

function lastItem<T>(items: T[]): T | undefined {
  return items.length === 0 ? undefined : items[items.length - 1]
}

function extractJson(output: string): string | undefined {
  const start = output.indexOf('{')
  const end = output.lastIndexOf('}')

  if (start >= 0 && end > start) {
    return output.slice(start, end + 1)
  }

  return undefined
}

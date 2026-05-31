#!/usr/bin/env node
import { spawnSync } from 'node:child_process'

import { VoicemailStore } from './storage/store.ts'

interface ParsedCommand {
  command: string
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
    const voicemail = store.enqueue({
      project: requiredFlag(parsed.flags, 'project'),
      message: requiredFlag(parsed.flags, 'message'),
      type: parsed.flags.type,
      priority: parsed.flags.priority,
      session: parsed.flags.session,
      app: parsed.flags.app,
      cwd: parsed.flags.cwd,
      url: parsed.flags.url,
    })

    console.log(`queued #${voicemail.id} ${voicemail.project}: ${voicemail.message}`)
    return
  }

  if (parsed.command === 'list') {
    const state = store.getState()
    console.log(`mode=${state.mode} muted=${state.muted}`)

    for (const voicemail of store.list()) {
      console.log(`#${voicemail.id} [${voicemail.status}] [${voicemail.priority}] ${voicemail.project}: ${voicemail.message}`)
    }
    return
  }

  if (parsed.command === 'status') {
    const state = store.getState()
    const counts = store.countByStatus()
    const source = store.latestSourceContext()

    console.log(JSON.stringify({
      mode: state.mode,
      muted: state.muted,
      inactiveLaneCombiner: state.inactiveLaneCombiner,
      counts,
      queueCount: counts.queued,
      attentionCount: counts.queued + counts.heard + counts.failed,
      source,
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
    console.log(`cleared ${store.clearHeard()} heard voicemails`)
    return
  }

  if (parsed.command === 'skip-next') {
    const skipped = store.skipNextQueued()
    console.log(skipped === undefined ? 'no queued voicemail to skip' : `skipped #${skipped.id}`)
    return
  }

  if (parsed.command === 'mark-handled') {
    const handled = store.markLatestHeardHandled()
    console.log(handled === undefined ? 'no heard voicemail to mark handled' : `handled #${handled.id}`)
    return
  }

  if (parsed.command === 'replay-last') {
    const replayed = store.replayLatestHeard()
    console.log(replayed === undefined ? 'no heard voicemail to replay' : `queued #${replayed.id} for replay`)
    return
  }

  if (parsed.command === 'source') {
    const source = store.latestSourceContext()
    console.log(JSON.stringify(source ?? null))
    return
  }

  if (parsed.command === 'reveal-source') {
    const source = store.latestSourceContext()

    if (source?.cwd === undefined) {
      console.log('no source cwd to reveal')
      return
    }

    spawnSync('/usr/bin/open', [source.cwd], { stdio: 'ignore' })
    console.log(`revealed ${source.cwd}`)
    return
  }

  if (parsed.command === 'copy-source') {
    const source = store.latestSourceContext()
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
    console.log(`${state.mode}${state.muted ? ', muted' : ''}, inactive-lane-combiner=${state.inactiveLaneCombiner}`)
    return
  }

  if (parsed.command === 'combiner') {
    const requested = parsed.flags.tool

    if (requested === undefined) {
      console.log(store.getState().inactiveLaneCombiner)
      return
    }

    if (requested !== 'none' && requested !== 'llm' && requested !== 'apfel') {
      throw new Error('--tool must be one of: none, llm, apfel')
    }

    const state = store.setInactiveLaneCombiner(requested)
    console.log(`inactive lane combiner set to ${state.inactiveLaneCombiner}`)
    return
  }

  printHelp()
  process.exitCode = parsed.command === 'help' ? 0 : 1
}

function parseArgs(args: string[]): ParsedCommand {
  if (args.length === 0) {
    return { command: 'help', flags: {} }
  }

  if (!args[0].startsWith('--')) {
    const [command, ...rest] = args
    return { command, flags: parseFlags(rest) }
  }

  return { command: 'enqueue', flags: parseFlags(args) }
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
  voicemail --project "Brain" --message "The plan is ready."
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
  voicemail source
  voicemail reveal-source
  voicemail copy-source
  voicemail combiner
  voicemail combiner --tool none|llm|apfel
  voicemail state
  voicemail status`)
}

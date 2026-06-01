#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { basename } from 'node:path'
import { fileURLToPath } from 'node:url'

import { appProcessorAuthorization, appProcessorAuthorizationEnv, processorIsAppAuthorized } from './core/app-authorization.ts'
import { buildCommandInvocation } from './core/command-template.ts'
import { isAppStoreProfile } from './core/distribution-profile.ts'
import { spokenText } from './core/message.ts'
import { RelayStore } from './storage/store.ts'

const speechTimeoutMs = 30_000

export interface SpeechResult {
  status: number | null
}

export interface ProcessOneResult {
  status: 'idle' | 'heard' | 'failed' | 'locked'
  exitCode: number
  relayId?: number
}

export type SpeakRelay = (text: string) => SpeechResult

export { appProcessorAuthorization, appProcessorAuthorizationEnv, processorIsAppAuthorized }

export function processOneRelayWithLock(store: RelayStore, speak?: SpeakRelay): ProcessOneResult {
  const owner = `processor:${process.pid}`

  if (!store.acquireProcessorLock(owner)) {
    return { status: 'locked', exitCode: 0 }
  }

  try {
    return processOneRelay(store, speak)
  } finally {
    store.releaseProcessorLock(owner)
  }
}

export function processOneAppLoopRelayWithLock(store: RelayStore, speak?: SpeakRelay): ProcessOneResult {
  store.failStaleSpeaking()
  const activeLine = store.getState().activeLine

  if (activeLine !== undefined && store.queuedCountForLine(activeLine) > 0) {
    return processOneLineRelayWithLock(store, activeLine, speak)
  }

  return processOneRelayWithLock(store, speak)
}

export function processOneRelay(store: RelayStore, speak?: SpeakRelay): ProcessOneResult {
  return processClaimedRelay(store, store.claimNextForSpeech(), speak ?? configuredSpeaker(store))
}

export function processOneLineRelayWithLock(store: RelayStore, line: string, speak?: SpeakRelay): ProcessOneResult {
  const owner = `processor:${process.pid}`

  if (!store.acquireProcessorLock(owner)) {
    return { status: 'locked', exitCode: 0 }
  }

  try {
    return processOneLineRelay(store, line, speak)
  } finally {
    store.releaseProcessorLock(owner)
  }
}

export function processOneLineRelay(store: RelayStore, line: string, speak?: SpeakRelay): ProcessOneResult {
  return processClaimedRelay(store, store.claimNextForLine(line), speak ?? configuredSpeaker(store))
}

function processClaimedRelay(store: RelayStore, relay: ReturnType<RelayStore['claimNextForSpeech']>, speak: SpeakRelay): ProcessOneResult {
  if (relay === undefined) {
    return { status: 'idle', exitCode: 0 }
  }

  const includeLine = store.shouldPrefixSpokenLine(relay.line)
  const result = speak(spokenText(relay, { includeLine }))

  if (result.status === 0) {
    store.recordSpokenLine(relay.line)
    store.markStatus(relay.id, 'heard')
    return { status: 'heard', exitCode: 0, relayId: relay.id }
  }

  store.markStatus(relay.id, 'failed')
  return { status: 'failed', exitCode: result.status ?? 1, relayId: relay.id }
}

export function speakWithSay(text: string): SpeechResult {
  return spawnSync('/usr/bin/say', [text], { stdio: 'ignore', timeout: speechTimeoutMs })
}

function configuredSpeaker(store: RelayStore): SpeakRelay {
  return (text) => {
    if (isAppStoreProfile()) {
      return { status: 1 }
    }

    const invocation = buildCommandInvocation(store.getState().speechCommand, { '<message>': text })

    if (invocation === undefined) {
      return { status: 1 }
    }

    return spawnSync(invocation.command, invocation.args, { stdio: 'ignore', timeout: speechTimeoutMs })
  }
}

function lineArg(args: string[]): string | undefined {
  const index = args.indexOf('--line')

  if (index === -1) {
    return undefined
  }

  return args[index + 1]
}

function hasArg(args: string[], arg: string): boolean {
  return args.includes(arg)
}

function appLoopParentIsAlive(): boolean {
  return process.ppid > 1
}

if (isMainModule()) {
  const store = new RelayStore()

  if (!processorIsAppAuthorized()) {
    console.error('relay-processor can only be launched by the TSRS app')
    store.close()
    process.exit(1)
  }

  try {
    const args = process.argv.slice(2)

    if (hasArg(args, '--app-loop')) {
      const interval = setInterval(() => {
        if (!appLoopParentIsAlive()) {
          clearInterval(interval)
          store.close()
          process.exit(0)
        }

        processOneAppLoopRelayWithLock(store)
      }, 1000)
      processOneAppLoopRelayWithLock(store)
    } else {
      const line = lineArg(args)
      const result = line === undefined
        ? processOneRelayWithLock(store)
        : processOneLineRelayWithLock(store, line)
      process.exitCode = result.exitCode
      store.close()
    }
  } catch (error) {
    store.close()
    throw error
  }
}

function isMainModule(): boolean {
  if (process.argv[1] === undefined) {
    return false
  }

  const executable = basename(process.argv[1])

  return fileURLToPath(import.meta.url) === process.argv[1]
    || executable === 'relay-processor'
}

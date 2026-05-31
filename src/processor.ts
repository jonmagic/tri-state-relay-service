#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { basename } from 'node:path'
import { fileURLToPath } from 'node:url'

import { buildCommandInvocation } from './core/command-template.ts'
import { spokenText } from './core/message.ts'
import { VoicemailStore } from './storage/store.ts'

export interface SpeechResult {
  status: number | null
}

export interface ProcessOneResult {
  status: 'idle' | 'heard' | 'failed' | 'locked'
  exitCode: number
  voicemailId?: number
}

export type SpeakVoicemail = (text: string) => SpeechResult

export function processOneVoicemailWithLock(store: VoicemailStore, speak?: SpeakVoicemail): ProcessOneResult {
  const owner = `processor:${process.pid}`

  if (!store.acquireProcessorLock(owner)) {
    return { status: 'locked', exitCode: 0 }
  }

  try {
    return processOneVoicemail(store, speak)
  } finally {
    store.releaseProcessorLock(owner)
  }
}

export function processOneVoicemail(store: VoicemailStore, speak?: SpeakVoicemail): ProcessOneResult {
  return processClaimedVoicemail(store, store.claimNextForSpeech(), speak ?? configuredSpeaker(store))
}

export function processOneLineVoicemailWithLock(store: VoicemailStore, line: string, speak?: SpeakVoicemail): ProcessOneResult {
  const owner = `processor:${process.pid}`

  if (!store.acquireProcessorLock(owner)) {
    return { status: 'locked', exitCode: 0 }
  }

  try {
    return processOneLineVoicemail(store, line, speak)
  } finally {
    store.releaseProcessorLock(owner)
  }
}

export function processOneLineVoicemail(store: VoicemailStore, line: string, speak?: SpeakVoicemail): ProcessOneResult {
  return processClaimedVoicemail(store, store.claimNextForLine(line), speak ?? configuredSpeaker(store))
}

function processClaimedVoicemail(store: VoicemailStore, voicemail: ReturnType<VoicemailStore['claimNextForSpeech']>, speak: SpeakVoicemail): ProcessOneResult {
  if (voicemail === undefined) {
    return { status: 'idle', exitCode: 0 }
  }

  const result = speak(spokenText(voicemail))

  if (result.status === 0) {
    store.markStatus(voicemail.id, 'heard')
    return { status: 'heard', exitCode: 0, voicemailId: voicemail.id }
  }

  store.markStatus(voicemail.id, 'failed')
  return { status: 'failed', exitCode: result.status ?? 1, voicemailId: voicemail.id }
}

export function speakWithSay(text: string): SpeechResult {
  return spawnSync('/usr/bin/say', [text], { stdio: 'ignore' })
}

function configuredSpeaker(store: VoicemailStore): SpeakVoicemail {
  return (text) => {
    const invocation = buildCommandInvocation(store.getState().speechCommand, { '<message>': text })

    if (invocation === undefined) {
      return { status: 1 }
    }

    return spawnSync(invocation.command, invocation.args, { stdio: 'ignore' })
  }
}

function lineArg(args: string[]): string | undefined {
  const index = args.indexOf('--line')

  if (index === -1) {
    return undefined
  }

  return args[index + 1]
}

if (isMainModule()) {
  const store = new VoicemailStore()

  try {
    const line = lineArg(process.argv.slice(2))
    const result = line === undefined
      ? processOneVoicemailWithLock(store)
      : processOneLineVoicemailWithLock(store, line)
    process.exitCode = result.exitCode
  } finally {
    store.close()
  }
}

function isMainModule(): boolean {
  if (process.argv[1] === undefined) {
    return false
  }

  const executable = basename(process.argv[1])

  return fileURLToPath(import.meta.url) === process.argv[1]
    || executable === 'voicemail-processor'
}

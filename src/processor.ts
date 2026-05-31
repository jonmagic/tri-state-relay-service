#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { basename } from 'node:path'
import { fileURLToPath } from 'node:url'

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

export function processOneVoicemailWithLock(store: VoicemailStore, speak: SpeakVoicemail = speakWithSay): ProcessOneResult {
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

export function processOneVoicemail(store: VoicemailStore, speak: SpeakVoicemail = speakWithSay): ProcessOneResult {
  return processClaimedVoicemail(store, store.claimNextForSpeech(), speak)
}

export function processOneProjectVoicemailWithLock(store: VoicemailStore, project: string, speak: SpeakVoicemail = speakWithSay): ProcessOneResult {
  const owner = `processor:${process.pid}`

  if (!store.acquireProcessorLock(owner)) {
    return { status: 'locked', exitCode: 0 }
  }

  try {
    return processOneProjectVoicemail(store, project, speak)
  } finally {
    store.releaseProcessorLock(owner)
  }
}

export function processOneProjectVoicemail(store: VoicemailStore, project: string, speak: SpeakVoicemail = speakWithSay): ProcessOneResult {
  return processClaimedVoicemail(store, store.claimNextForProject(project), speak)
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

function projectArg(args: string[]): string | undefined {
  const index = args.indexOf('--project')

  if (index === -1) {
    return undefined
  }

  return args[index + 1]
}

if (isMainModule()) {
  const store = new VoicemailStore()

  try {
    const project = projectArg(process.argv.slice(2))
    const result = project === undefined
      ? processOneVoicemailWithLock(store)
      : processOneProjectVoicemailWithLock(store, project)
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

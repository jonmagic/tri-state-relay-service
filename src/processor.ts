#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

import { spokenText } from './core/message.ts'
import { VoicemailStore } from './storage/store.ts'

export interface SpeechResult {
  status: number | null
}

export interface ProcessOneResult {
  status: 'idle' | 'heard' | 'failed'
  exitCode: number
  voicemailId?: number
}

export type SpeakVoicemail = (text: string) => SpeechResult

export function processOneVoicemail(store: VoicemailStore, speak: SpeakVoicemail = speakWithSay): ProcessOneResult {
  const voicemail = store.claimNextForSpeech()

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

if (isMainModule()) {
  const store = new VoicemailStore()

  try {
    const result = processOneVoicemail(store)
    process.exitCode = result.exitCode
  } finally {
    store.close()
  }
}

function isMainModule(): boolean {
  return process.argv[1] !== undefined && fileURLToPath(import.meta.url) === process.argv[1]
}

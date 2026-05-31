#!/usr/bin/env node
import { spawnSync } from 'node:child_process'

import { spokenText } from './core/message.ts'
import { VoicemailStore } from './storage/store.ts'

const store = new VoicemailStore()

try {
  const voicemail = store.claimNextForSpeech()

  if (voicemail === undefined) {
    process.exit(0)
  }

  const result = spawnSync('/usr/bin/say', [spokenText(voicemail)], { stdio: 'ignore' })

  if (result.status === 0) {
    store.markStatus(voicemail.id, 'heard')
  } else {
    store.markStatus(voicemail.id, 'failed')
    process.exitCode = result.status ?? 1
  }
} finally {
  store.close()
}

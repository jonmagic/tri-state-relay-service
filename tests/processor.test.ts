import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { processOneVoicemail, type SpeechResult } from '../src/processor.ts'
import { VoicemailStore } from '../src/storage/store.ts'

test('processor marks one ready voicemail heard after successful speech', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const queued = store.enqueue({ project: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')
  const spoken: string[] = []

  const result = processOneVoicemail(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(result, { status: 'heard', exitCode: 0, voicemailId: queued.id })
  assert.deepEqual(spoken, ['Brain. The plan is ready.'])
  assert.equal(store.list()[0].status, 'heard')
  assert.equal(store.getState().mode, 'focus')
  store.close()
})

test('processor marks one ready voicemail failed after speech failure', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const queued = store.enqueue({ project: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneVoicemail(store, () => ({ status: 42 }))

  assert.deepEqual(result, { status: 'failed', exitCode: 42, voicemailId: queued.id })
  assert.equal(store.list()[0].status, 'failed')
  assert.equal(store.getState().mode, 'focus')
  store.close()
})

test('processor does not speak when focus or mute prevents claiming', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  store.enqueue({ project: 'Brain', message: 'The plan is ready.' })
  const spoken: string[] = []

  const result = processOneVoicemail(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(result, { status: 'idle', exitCode: 0 })
  assert.deepEqual(spoken, [])
  assert.equal(store.list()[0].status, 'queued')
  store.close()
})

test('processor converts missing speech status to failure exit code', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const queued = store.enqueue({ project: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneVoicemail(store, (): SpeechResult => ({ status: null }))

  assert.deepEqual(result, { status: 'failed', exitCode: 1, voicemailId: queued.id })
  assert.equal(store.list()[0].status, 'failed')
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'voicemail.db')
}

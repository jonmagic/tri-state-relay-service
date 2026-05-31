import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { processOneLineVoicemail, processOneVoicemail, processOneVoicemailWithLock, type SpeechResult } from '../src/processor.ts'
import { VoicemailStore } from '../src/storage/store.ts'

test('processor marks one ready voicemail heard after successful speech', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
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
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneVoicemail(store, () => ({ status: 42 }))

  assert.deepEqual(result, { status: 'failed', exitCode: 42, voicemailId: queued.id })
  assert.equal(store.list()[0].status, 'failed')
  assert.equal(store.getState().mode, 'focus')
  store.close()
})

test('processor does not speak when focus or mute prevents claiming', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
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
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneVoicemail(store, (): SpeechResult => ({ status: null }))

  assert.deepEqual(result, { status: 'failed', exitCode: 1, voicemailId: queued.id })
  assert.equal(store.list()[0].status, 'failed')
  store.close()
})

test('processor uses configured speech command without shell expansion', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'hello; rm -rf ~' })
  store.setMode('ready')
  store.setSpeechCommand('/usr/bin/printf <message>')

  const result = processOneVoicemail(store)

  assert.deepEqual(result, { status: 'heard', exitCode: 0, voicemailId: queued.id })
  assert.equal(store.list()[0].status, 'heard')
  store.close()
})

test('processor lock prevents a second speaker from claiming voicemail', () => {
  const dbPath = temporaryDatabasePath()
  const store = new VoicemailStore(dbPath)
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')
  store.acquireProcessorLock('other-processor')
  const spoken: string[] = []

  const result = processOneVoicemailWithLock(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(result, { status: 'locked', exitCode: 0 })
  assert.deepEqual(spoken, [])
  assert.equal(store.list()[0].status, 'queued')
  store.releaseProcessorLock('other-processor')
  store.close()
})

test('processor lock is released after processing', () => {
  const dbPath = temporaryDatabasePath()
  const store = new VoicemailStore(dbPath)
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneVoicemailWithLock(store, () => ({ status: 0 }))

  assert.equal(result.status, 'heard')
  assert.equal(store.acquireProcessorLock('next-processor'), true)
  store.releaseProcessorLock('next-processor')
  store.close()
})

test('processor can claim one voicemail from a specific active line', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  store.enqueue({ line: 'Other', message: 'Other line update.' })
  const active = store.enqueue({ line: 'Brain', message: 'Active line update.' })
  const spoken: string[] = []

  const result = processOneLineVoicemail(store, 'Brain', (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(result, { status: 'heard', exitCode: 0, voicemailId: active.id })
  assert.deepEqual(spoken, ['Brain. Active line update.'])
  assert.equal(store.list().find((voicemail) => voicemail.line === 'Other')?.status, 'queued')
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'voicemail.db')
}

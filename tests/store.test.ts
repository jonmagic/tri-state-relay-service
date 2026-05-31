import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { VoicemailStore } from '../src/storage/store.ts'

test('persists queued voicemail in SQLite', () => {
  const dbPath = temporaryDatabasePath()
  const firstStore = new VoicemailStore(dbPath)
  const queued = firstStore.enqueue({
    project: 'Brain',
    message: 'The plan is ready.',
  })
  firstStore.close()

  const secondStore = new VoicemailStore(dbPath)
  assert.equal(secondStore.list()[0].id, queued.id)
  assert.equal(secondStore.list()[0].status, 'queued')
  secondStore.close()
})

test('focus mode prevents claiming a queued voicemail', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  store.enqueue({ project: 'Brain', message: 'The plan is ready.' })

  assert.equal(store.claimNextForSpeech(), undefined)
  assert.equal(store.list()[0].status, 'queued')
  store.close()
})

test('ready mode claims exactly one voicemail and returns to focus', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  store.enqueue({ project: 'Low', priority: 'low', message: 'Low priority update.' })
  store.enqueue({ project: 'High', priority: 'high', message: 'High priority update.' })
  store.setMode('ready')

  const claimed = store.claimNextForSpeech()

  assert.equal(claimed?.project, 'High')
  assert.equal(store.getState().mode, 'focus')
  assert.equal(store.claimNextForSpeech(), undefined)
  assert.equal(store.list().filter((voicemail) => voicemail.status === 'speaking').length, 1)
  store.close()
})

test('mute prevents ready mode from claiming voicemail', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  store.enqueue({ project: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')
  store.setMuted(true)

  assert.equal(store.claimNextForSpeech(), undefined)
  assert.equal(store.getState().mode, 'ready')
  store.close()
})

test('lifecycle controls skip replay handle and clear heard voicemails', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const queued = store.enqueue({ project: 'Brain', message: 'The plan is ready.' })

  assert.equal(store.skipNextQueued()?.id, queued.id)
  assert.equal(store.list()[0].status, 'skipped')

  const heard = store.markStatus(queued.id, 'heard')
  assert.equal(store.replayLatestHeard()?.id, heard.id)
  assert.equal(store.list()[0].status, 'queued')

  store.markStatus(queued.id, 'heard')
  assert.equal(store.markLatestHeardHandled()?.status, 'handled')
  assert.equal(store.list()[0].status, 'handled')

  store.markStatus(queued.id, 'heard')
  assert.equal(store.clearHeard(), 1)
  assert.equal(store.list().length, 0)
  store.close()
})

test('latest source context omits message text and prefers newest metadata', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  store.enqueue({ project: 'Brain', message: 'No source here.' })
  store.enqueue({
    project: 'TSRS',
    message: 'The app is ready.',
    session: 'agent session',
    app: 'Ghostty',
    cwd: '~/code/tri-state-relay-service',
    url: 'https://github.com/jonmagic/tri-state-relay-service',
  })

  assert.deepEqual(store.latestSourceContext(), {
    id: 2,
    project: 'TSRS',
    session: 'agent session',
    app: 'Ghostty',
    cwd: '~/code/tri-state-relay-service',
    url: 'https://github.com/jonmagic/tri-state-relay-service',
  })
  assert.equal(JSON.stringify(store.latestSourceContext()).includes('The app is ready.'), false)
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'voicemail.db')
}

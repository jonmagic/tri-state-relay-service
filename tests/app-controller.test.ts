import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { AppQueueController } from '../src/app/controller.ts'
import { VoicemailStore } from '../src/storage/store.ts'

test('app controller reports menu bar queue status without message text', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const controller = new AppQueueController(store)
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.enqueue({ line: 'Hamzo', message: 'The review is blocked.', priority: 'high' })

  const status = controller.status()

  assert.equal(status.mode, 'focus')
  assert.equal(status.muted, false)
  assert.equal(status.queueCount, 2)
  assert.equal(status.attentionCount, 2)
  assert.equal(status.canPlay, false)
  assert.equal(status.counts.queued, 2)
  assert.equal(JSON.stringify(status).includes('The plan is ready.'), false)
  store.close()
})

test('app controller toggles ready focus mute and unmute through store rules', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const controller = new AppQueueController(store)
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })

  assert.equal(controller.ready().canPlay, true)
  assert.equal(controller.mute().canPlay, false)
  assert.equal(controller.unmute().canPlay, true)
  assert.equal(controller.focus().canPlay, false)
  store.close()
})

test('app controller clear updates queue status for menu bar display', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const controller = new AppQueueController(store)
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })

  const status = controller.clear()

  assert.equal(status.queueCount, 0)
  assert.equal(status.attentionCount, 0)
  assert.equal(status.canPlay, false)
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'voicemail.db')
}

import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { appProcessorAuthorization, appProcessorAuthorizationEnv, processOneAppLoopRelayWithLock, processOneLineRelay, processOneRelay, processOneRelayWithLock, processorIsAppAuthorized, type SpeechResult } from '../src/processor.ts'
import { RelayStore } from '../src/storage/store.ts'

test('processor marks one ready relay heard after successful speech', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')
  const spoken: string[] = []

  const result = processOneRelay(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(result, { status: 'heard', exitCode: 0, relayId: queued.id })
  assert.deepEqual(spoken, ['Brain. The plan is ready.'])
  assert.equal(store.list()[0].status, 'heard')
  assert.equal(store.getState().mode, 'focus')
  store.close()
})

test('processor repeats line prefix only after line changes or timeout', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const spoken: string[] = []
  store.enqueue({ line: 'Brain', message: 'First update.' })
  store.enqueue({ line: 'Brain', message: 'Second update.' })
  store.enqueue({ line: 'TSRS', message: 'Line changed.' })
  store.setMode('ready')

  processOneRelay(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })
  store.setMode('ready')
  processOneRelay(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })
  store.setMode('ready')
  processOneRelay(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(spoken, [
    'Brain. First update.',
    'Second update.',
    'TSRS. Line changed.',
  ])

  store.recordSpokenLine('TSRS', new Date('2026-05-31T19:00:00.000Z'))
  assert.equal(store.shouldPrefixSpokenLine('TSRS', new Date('2026-05-31T19:00:59.000Z')), false)
  assert.equal(store.shouldPrefixSpokenLine('TSRS', new Date('2026-05-31T19:01:00.000Z')), true)
  store.close()
})

test('processor marks one ready relay failed after speech failure', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneRelay(store, () => ({ status: 42 }))

  assert.deepEqual(result, { status: 'failed', exitCode: 42, relayId: queued.id })
  assert.equal(store.list()[0].status, 'failed')
  assert.equal(store.getState().mode, 'focus')
  store.close()
})

test('processor does not speak when focus or mute prevents claiming', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  const spoken: string[] = []

  const result = processOneRelay(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(result, { status: 'idle', exitCode: 0 })
  assert.deepEqual(spoken, [])
  assert.equal(store.list()[0].status, 'queued')
  store.close()
})

test('processor converts missing speech status to failure exit code', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneRelay(store, (): SpeechResult => ({ status: null }))

  assert.deepEqual(result, { status: 'failed', exitCode: 1, relayId: queued.id })
  assert.equal(store.list()[0].status, 'failed')
  store.close()
})

test('processor uses configured speech command without shell expansion', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'hello; rm -rf ~' })
  store.setMode('ready')
  store.setSpeechCommand('/usr/bin/printf <message>')

  const result = processOneRelay(store)

  assert.deepEqual(result, { status: 'heard', exitCode: 0, relayId: queued.id })
  assert.equal(store.list()[0].status, 'heard')
  store.close()
})

test('processor lock prevents a second speaker from claiming relay', () => {
  const dbPath = temporaryDatabasePath()
  const store = new RelayStore(dbPath)
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')
  store.acquireProcessorLock('other-processor')
  const spoken: string[] = []

  const result = processOneRelayWithLock(store, (text) => {
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
  const store = new RelayStore(dbPath)
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')

  const result = processOneRelayWithLock(store, () => ({ status: 0 }))

  assert.equal(result.status, 'heard')
  assert.equal(store.acquireProcessorLock('next-processor'), true)
  store.releaseProcessorLock('next-processor')
  store.close()
})

test('app loop prefers the current active line and follows line changes', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const firstBrain = store.enqueue({ line: 'Brain', message: 'Brain first.' })
  const tsrs = store.enqueue({ line: 'TSRS', message: 'TSRS update.' })
  const secondBrain = store.enqueue({ line: 'Brain', message: 'Brain second.' })
  const spoken: string[] = []

  store.setActiveLine('Brain')
  assert.deepEqual(processOneAppLoopRelayWithLock(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  }), { status: 'heard', exitCode: 0, relayId: firstBrain.id })

  store.setActiveLine('TSRS')
  assert.deepEqual(processOneAppLoopRelayWithLock(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  }), { status: 'heard', exitCode: 0, relayId: tsrs.id })

  store.setMode('ready')
  assert.deepEqual(processOneAppLoopRelayWithLock(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  }), { status: 'heard', exitCode: 0, relayId: secondBrain.id })

  assert.deepEqual(spoken, [
    'Brain. Brain first.',
    'TSRS. TSRS update.',
    'Brain. Brain second.',
  ])
  store.close()
})

test('app loop fails stale speaking rows before claiming the next relay', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const stale = store.enqueue({ line: 'Brain', message: 'Stale speaking.' })
  const queued = store.enqueue({ line: 'Brain', message: 'Fresh update.' })
  const spoken: string[] = []
  store.markStatus(stale.id, 'speaking')
  store.database.prepare(`
    UPDATE relays
    SET updated_at = '2026-05-31T19:00:00.000Z'
    WHERE id = ?
  `).run(stale.id)
  store.setActiveLine('Brain')

  assert.deepEqual(processOneAppLoopRelayWithLock(store, (text) => {
    spoken.push(text)
    return { status: 0 }
  }), { status: 'heard', exitCode: 0, relayId: queued.id })
  assert.equal(store.list().find((relay) => relay.id === stale.id)?.status, 'failed')
  assert.deepEqual(spoken, ['Brain. Fresh update.'])
  store.close()
})

test('processor lock keeps live owners and reclaims stale or dead owners', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const now = new Date('2026-05-31T19:00:00.000Z')

  assert.equal(store.acquireProcessorLock('processor:123', {
    now,
    isOwnerAlive: () => true,
  }), true)
  assert.equal(store.acquireProcessorLock('processor:456', {
    now: new Date('2026-05-31T19:00:10.000Z'),
    isOwnerAlive: () => true,
  }), false)
  assert.equal(store.acquireProcessorLock('processor:456', {
    now: new Date('2026-05-31T19:00:10.000Z'),
    isOwnerAlive: () => false,
  }), true)
  assert.equal(store.acquireProcessorLock('processor:789', {
    now: new Date('2026-05-31T19:02:00.000Z'),
    isOwnerAlive: () => true,
  }), true)
  store.releaseProcessorLock('processor:789')
  store.close()
})

test('processor can claim one relay from a specific active line', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({ line: 'Other', message: 'Other line update.' })
  const active = store.enqueue({ line: 'Brain', message: 'Active line update.' })
  const spoken: string[] = []

  const result = processOneLineRelay(store, 'Brain', (text) => {
    spoken.push(text)
    return { status: 0 }
  })

  assert.deepEqual(result, { status: 'heard', exitCode: 0, relayId: active.id })
  assert.deepEqual(spoken, ['Brain. Active line update.'])
  assert.equal(store.list().find((relay) => relay.line === 'Other')?.status, 'queued')
  store.close()
})

test('processor main entrypoint requires app authorization', () => {
  assert.equal(processorIsAppAuthorized({}), false)
  assert.equal(processorIsAppAuthorized({ [appProcessorAuthorizationEnv]: 'wrong' }), false)
  assert.equal(processorIsAppAuthorized({ [appProcessorAuthorizationEnv]: appProcessorAuthorization }), true)
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'relay.db')
}

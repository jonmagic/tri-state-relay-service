import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { runAppProcessorLoop } from '../src/app/processor-loop.ts'
import { RelayStore } from '../src/storage/store.ts'

test('app processor loop processes ready relay through locked processor path', async () => {
  const store = new RelayStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')
  const slept: number[] = []

  const results = await runAppProcessorLoop(store, {
    intervalMs: 5,
    maxIterations: 2,
    sleep: (milliseconds) => {
      slept.push(milliseconds)
      return Promise.resolve()
    },
    speak: () => ({ status: 0 }),
  })

  assert.deepEqual(results, [
    { status: 'heard', exitCode: 0, relayId: queued.id },
    { status: 'idle', exitCode: 0 },
  ])
  assert.deepEqual(slept, [5])
  assert.equal(store.list()[0].status, 'heard')
  store.close()
})

test('app processor loop can be stopped by the owning app', async () => {
  const store = new RelayStore(temporaryDatabasePath())
  let iterations = 0

  const results = await runAppProcessorLoop(store, {
    sleep: () => Promise.resolve(),
    shouldContinue: () => iterations++ < 1,
    onResult: (result) => assert.equal(result.status, 'idle'),
  })

  assert.deepEqual(results, [{ status: 'idle', exitCode: 0 }])
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'relay.db')
}

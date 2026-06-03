import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { RelayStore } from '../src/storage/store.ts'

test('persists queued relay in SQLite', () => {
  const dbPath = temporaryDatabasePath()
  const firstStore = new RelayStore(dbPath)
  const queued = firstStore.enqueue({
    line: 'Brain',
    message: 'The plan is ready.',
  })
  firstStore.close()

  const secondStore = new RelayStore(dbPath)
  assert.equal(secondStore.list()[0].id, queued.id)
  assert.equal(secondStore.list()[0].status, 'queued')
  secondStore.close()
})

test('focus mode prevents claiming a queued relay', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })

  assert.equal(store.claimNextForSpeech(), undefined)
  assert.equal(store.list()[0].status, 'queued')
  store.close()
})

test('ready mode claims exactly one relay and returns to focus', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({ line: 'Low', priority: 'low', message: 'Low priority update.' })
  store.enqueue({ line: 'High', priority: 'high', message: 'High priority update.' })
  store.setMode('ready')

  const claimed = store.claimNextForSpeech()

  assert.equal(claimed?.line, 'High')
  assert.equal(store.getState().mode, 'focus')
  assert.equal(store.claimNextForSpeech(), undefined)
  assert.equal(store.list().filter((relay) => relay.status === 'speaking').length, 1)
  store.close()
})

test('mute prevents ready mode from claiming relay', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.setMode('ready')
  store.setMuted(true)

  assert.equal(store.claimNextForSpeech(), undefined)
  assert.equal(store.getState().mode, 'ready')
  store.close()
})

test('command settings default safely and can be configured', () => {
  const store = new RelayStore(temporaryDatabasePath())

  assert.equal(store.getState().inactiveLineCombiner, 'none')
  assert.equal(store.getState().inactiveLineCombinerCommand.includes('https://github.com/simonw/llm'), true)
  assert.equal(store.getState().speechCommand.includes('/usr/bin/say <message>'), true)
  assert.equal(store.setInactiveLineCombinerCommand('llm prompt <input> --system <system>').inactiveLineCombiner, 'custom')
  assert.equal(store.setInactiveLineCombinerCommand('').inactiveLineCombiner, 'none')
  assert.equal(store.setSpeechCommand('').speechCommand.includes('/usr/bin/say <message>'), true)
  store.close()
})

test('app-store profile disables external command settings without overwriting direct settings', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.setInactiveLineCombinerCommand('llm prompt <input> --system <system>')
  store.setSpeechCommand('/usr/bin/printf <message>')

  const appStoreState = store.getState('app-store')

  assert.equal(appStoreState.inactiveLineCombiner, 'none')
  assert.equal(appStoreState.inactiveLineCombinerCommand.includes('unavailable in the App Store-safe profile'), true)
  assert.equal(appStoreState.speechCommand.includes('unavailable in the App Store-safe profile'), true)
  assert.equal(store.setInactiveLineCombinerCommandForProfile('apfel <input>', 'app-store').inactiveLineCombiner, 'none')
  assert.equal(store.setSpeechCommandForProfile('/usr/bin/say <message>', 'app-store').speechCommand.includes('unavailable in the App Store-safe profile'), true)
  assert.equal(store.getState('direct').inactiveLineCombiner, 'custom')
  assert.equal(store.getState('direct').inactiveLineCombinerCommand, 'llm prompt <input> --system <system>')
  assert.equal(store.getState('direct').speechCommand, '/usr/bin/printf <message>')
  store.close()
})

test('legacy llm combiner setting migrates to command template', () => {
  const dbPath = temporaryDatabasePath()
  const store = new RelayStore(dbPath)
  store.database.prepare("UPDATE settings SET value = 'llm' WHERE key = 'inactive_line_combiner'").run()
  store.database.prepare("DELETE FROM settings WHERE key = 'inactive_line_combiner_command'").run()
  store.close()

  const migrated = new RelayStore(dbPath)
  assert.equal(migrated.getState().inactiveLineCombiner, 'custom')
  assert.equal(migrated.getState().inactiveLineCombinerCommand, 'llm prompt <input> --system <system> --no-stream --no-log')
  migrated.close()
})

test('legacy apfel combiner setting migrates to command template', () => {
  const dbPath = temporaryDatabasePath()
  const store = new RelayStore(dbPath)
  store.database.prepare("UPDATE settings SET value = 'apfel' WHERE key = 'inactive_line_combiner'").run()
  store.database.prepare("DELETE FROM settings WHERE key = 'inactive_line_combiner_command'").run()
  store.close()

  const migrated = new RelayStore(dbPath)
  assert.equal(migrated.getState().inactiveLineCombiner, 'custom')
  assert.equal(migrated.getState().inactiveLineCombinerCommand, 'apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>')
  migrated.close()
})

test('active line setting and line counts are persisted', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.enqueue({ line: 'Brain', message: 'The second update is ready.' })
  store.enqueue({ line: 'TSRS', message: 'The app is ready.' })
  store.markStatus(3, 'heard')

  assert.equal(store.setActiveLine('Brain').activeLine, 'Brain')
  assert.deepEqual(store.lineSummaries(), [
    { line: 'Brain', queued: 2, heard: 0, failed: 0 },
    { line: 'TSRS', queued: 0, heard: 1, failed: 0 },
  ])
  store.close()
})

test('first accepted relay becomes active line when unset', () => {
  const store = new RelayStore(temporaryDatabasePath())

  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  store.enqueue({ line: 'TSRS', message: 'The app is ready.' })

  assert.equal(queued.line, 'Brain')
  assert.equal(store.getState().activeLine, 'Brain')
  store.close()
})

test('first accepted relay through line policy becomes active line when unset', () => {
  const store = new RelayStore(temporaryDatabasePath())

  const queued = store.enqueueWithLinePolicy({ line: 'Brain', message: 'The plan is ready.' })

  assert.equal(queued?.line, 'Brain')
  assert.equal(store.getState().activeLine, 'Brain')
  store.close()
})

test('stale relay expiry removes old menu lines without expiring important queued work', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const now = new Date('2026-05-31T15:00:00.000Z')
  const stale = '2026-05-31T14:00:00.000Z'
  const recent = '2026-05-31T14:45:00.000Z'

  store.enqueue({ line: 'OldUpdate', message: 'Old update.' })
  store.enqueue({ line: 'OldComplete', type: 'complete', message: 'Old complete.' })
  store.enqueue({ line: 'OldHigh', priority: 'high', message: 'High update.' })
  store.enqueue({ line: 'OldBlocked', type: 'blocked', message: 'Blocked update.' })
  store.enqueue({ line: 'Recent', message: 'Recent update.' })
  store.enqueue({ line: 'Delivered', message: 'Delivered update.' })
  store.enqueue({ line: 'Failed', message: 'Failed update.' })
  store.markStatus(6, 'heard')
  store.markStatus(7, 'failed')
  store.database.prepare(`
    UPDATE relays
    SET created_at = ?, updated_at = ?
    WHERE line IN ('OldUpdate', 'OldComplete', 'OldHigh', 'OldBlocked', 'Delivered', 'Failed')
  `).run(stale, stale)
  store.database.prepare(`
    UPDATE relays
    SET created_at = ?, updated_at = ?
    WHERE line = 'Recent'
  `).run(recent, recent)

  assert.equal(store.expireStaleRelays({ now, ageMinutes: 30 }), 4)
  assert.deepEqual(store.lineSummaries(), [
    { line: 'OldBlocked', queued: 1, heard: 0, failed: 0 },
    { line: 'OldHigh', queued: 1, heard: 0, failed: 0 },
    { line: 'Recent', queued: 1, heard: 0, failed: 0 },
  ])
  assert.deepEqual(
    store.list(20)
      .filter((relay) => relay.status === 'expired')
      .map((relay) => relay.line)
      .sort(),
    ['Delivered', 'Failed', 'OldComplete', 'OldUpdate'],
  )
  store.close()
})

test('inactive line without combiner keeps only latest queued message', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.setActiveLine('TSRS')
  store.enqueueWithLinePolicy({ line: 'Brain', message: 'First inactive update.' })
  const latest = store.enqueueWithLinePolicy({ line: 'Brain', message: 'Latest inactive update.' })

  assert.equal(latest?.message, 'Latest inactive update.')
  assert.deepEqual(store.list().map((relay) => relay.message), ['Latest inactive update.'])
  store.close()
})

test('inactive line with combiner replaces queued messages with one relay', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.setActiveLine('TSRS')
  store.setInactiveLineCombinerCommand('llm prompt <input> --system <system>')
  store.enqueueWithLinePolicy({ line: 'Brain', message: 'I found the issue.' }, () => ({
    action: 'replace',
    type: 'update',
    priority: 'normal',
    message: 'Brain update: I found the issue.',
  }))

  const combined = store.enqueueWithLinePolicy({ line: 'Brain', type: 'blocked', priority: 'high', message: 'I need input.' }, (input) => {
    assert.equal(input.activeLine, 'TSRS')
    assert.equal(input.inactiveLine, 'Brain')
    assert.deepEqual(input.incoming.map((message) => message.message), ['Brain update: I found the issue.', 'I need input.'])

    return {
      action: 'promote',
      type: 'blocked',
      priority: 'high',
      message: 'Brain is blocked and needs input.',
    }
  })

  assert.equal(combined?.message, 'Brain is blocked and needs input.')
  assert.deepEqual(store.list().map((relay) => relay.message), ['Brain is blocked and needs input.'])
  store.close()
})

test('inactive line combiner drop preserves existing pending relay', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.setActiveLine('TSRS')
  store.setInactiveLineCombinerCommand('llm prompt <input> --system <system>')
  const existing = store.enqueueWithLinePolicy({ line: 'Brain', message: 'Indexing is running.' }, () => ({
    action: 'replace',
    type: 'update',
    priority: 'normal',
    message: 'Brain update: indexing is running.',
  }))
  const dropped = store.enqueueWithLinePolicy({ line: 'Brain', message: 'Indexing is still running.' }, () => ({
    action: 'drop',
    type: 'update',
    priority: 'normal',
    message: 'Brain update: indexing is still running.',
  }))

  assert.equal(dropped?.id, existing?.id)
  assert.deepEqual(store.list().map((relay) => relay.message), ['Brain update: indexing is running.'])
  store.close()
})

test('lifecycle controls skip replay handle and clear heard relays', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const queued = store.enqueue({ line: 'Brain', message: 'The plan is ready.' })

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

test('lifecycle controls can be scoped to a line', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const brain = store.enqueue({ line: 'Brain', message: 'Brain update.' })
  const tsrs = store.enqueue({ line: 'TSRS', message: 'TSRS update.' })

  assert.equal(store.skipNextQueued('Brain')?.id, brain.id)
  assert.equal(store.list().find((relay) => relay.id === tsrs.id)?.status, 'queued')

  store.markStatus(brain.id, 'heard')
  store.markStatus(tsrs.id, 'heard')
  assert.equal(store.replayLatestHeard('Brain')?.id, brain.id)
  assert.equal(store.list().find((relay) => relay.id === tsrs.id)?.status, 'heard')

  store.markStatus(brain.id, 'heard')
  assert.equal(store.markLatestHeardHandled('Brain')?.id, brain.id)
  assert.equal(store.list().find((relay) => relay.id === tsrs.id)?.status, 'heard')

  assert.equal(store.clearHeard('TSRS'), 1)
  assert.equal(store.list().some((relay) => relay.id === tsrs.id), false)
  store.close()
})

test('latest source context omits message text and prefers newest metadata', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({
    line: 'Brain',
    message: 'Brain source ready.',
    cwd: '~/Brain',
  })
  store.enqueue({
    line: 'TSRS',
    message: 'The app is ready.',
    session: 'agent session',
    app: 'Ghostty',
    cwd: '~/code/tri-state-relay-service',
    url: 'https://github.com/jonmagic/tri-state-relay-service',
  })

  assert.deepEqual(store.latestSourceContext(), {
    id: 2,
    line: 'TSRS',
    session: 'agent session',
    app: 'Ghostty',
    cwd: '~/code/tri-state-relay-service',
    url: 'https://github.com/jonmagic/tri-state-relay-service',
  })
  assert.deepEqual(store.latestSourceContext('Brain'), {
    id: 1,
    line: 'Brain',
    cwd: '~/Brain',
  })
  assert.deepEqual(store.latestSourceContextsByLine(), [
    {
      id: 1,
      line: 'Brain',
      cwd: '~/Brain',
    },
    {
      id: 2,
      line: 'TSRS',
      session: 'agent session',
      app: 'Ghostty',
      cwd: '~/code/tri-state-relay-service',
      url: 'https://github.com/jonmagic/tri-state-relay-service',
    },
  ])
  assert.equal(JSON.stringify(store.latestSourceContext()).includes('The app is ready.'), false)
  assert.equal(JSON.stringify(store.latestSourceContext('Brain')).includes('Brain source ready.'), false)
  assert.equal(JSON.stringify(store.latestSourceContextsByLine()).includes('The app is ready.'), false)
  store.close()
})

test('queue overview summarizes priority producer and stale blockers without message text', () => {
  const store = new RelayStore(temporaryDatabasePath())
  store.enqueue({
    line: 'Brain',
    message: 'Secret planning text.',
    priority: 'high',
    type: 'blocked',
    session: 'brain-agent',
  })
  store.enqueue({
    line: 'TSRS',
    message: 'Private status text.',
    priority: 'normal',
    app: 'Ghostty',
  })
  store.enqueue({
    line: 'Unknown',
    message: 'Another private message.',
    priority: 'low',
  })
  store.markStatus(2, 'heard')
  store.markStatus(3, 'failed')
  store.database.prepare(`
    UPDATE relays
    SET created_at = '2026-05-31T14:00:00.000Z'
    WHERE id = 1
  `).run()

  const overview = store.queueOverview({ now: new Date('2026-05-31T15:00:00.000Z') })

  assert.deepEqual(overview.byPriority, [
    { priority: 'high', count: 1 },
    { priority: 'normal', count: 1 },
    { priority: 'low', count: 1 },
  ])
  assert.deepEqual(overview.byProducer, [
    { producer: 'Ghostty', count: 1 },
    { producer: 'brain-agent', count: 1 },
    { producer: 'unknown', count: 1 },
  ])
  assert.deepEqual(overview.staleBlockers, {
    count: 1,
    oldestCreatedAt: '2026-05-31T14:00:00.000Z',
    thresholdMinutes: 15,
  })
  assert.equal(JSON.stringify(overview).includes('Secret planning text.'), false)
  assert.equal(JSON.stringify(overview).includes('Private status text.'), false)
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'relay.db')
}

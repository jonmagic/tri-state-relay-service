import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { MenuBarAppShell, menuBarTitle, type MenuBarSnapshot } from '../src/app/menu-bar-shell.ts'
import { RelayStore } from '../src/storage/store.ts'

test('menu bar shell exposes focus ready and mute snapshots', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const snapshots: MenuBarSnapshot[] = []
  const shell = new MenuBarAppShell(store, { onSnapshot: (snapshot) => snapshots.push(snapshot) })
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })

  assert.equal(shell.snapshot().title, 'TSRS focus (1)')
  assert.equal(shell.ready().title, 'TSRS ready (1)')
  assert.equal(shell.mute().title, 'TSRS muted (1)')
  assert.equal(shell.unmute().title, 'TSRS ready (1)')
  assert.equal(shell.focus().title, 'TSRS focus (1)')
  assert.deepEqual(snapshots.map((snapshot) => snapshot.title), [
    'TSRS ready (1)',
    'TSRS muted (1)',
    'TSRS ready (1)',
    'TSRS focus (1)',
  ])
  store.close()
})

test('menu bar shell updates snapshot after app-owned processor loop runs', async () => {
  const store = new RelayStore(temporaryDatabasePath())
  const snapshots: MenuBarSnapshot[] = []
  const shell = new MenuBarAppShell(store, {
    maxIterations: 1,
    speak: () => ({ status: 0 }),
    onSnapshot: (snapshot) => snapshots.push(snapshot),
  })
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })
  shell.ready()

  const results = await shell.runProcessorLoop()

  assert.equal(results[0].status, 'heard')
  assert.equal(shell.snapshot().title, 'TSRS focus (0)')
  assert.equal(snapshots.at(-1)?.title, 'TSRS focus (0)')
  store.close()
})

test('menu bar title summarizes state without exposing message text', () => {
  const store = new RelayStore(temporaryDatabasePath())
  const shell = new MenuBarAppShell(store)
  store.enqueue({ line: 'Brain', message: 'Secret-looking content should stay out of the title.' })

  const title = menuBarTitle(shell.ready().status)

  assert.equal(title, 'TSRS ready (1)')
  assert.equal(title.includes('Secret-looking content'), false)
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'relay.db')
}

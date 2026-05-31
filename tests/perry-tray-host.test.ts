import assert from 'node:assert/strict'
import test from 'node:test'

import { attachPerryTray, createPerryTrayHost, type PerryTrayBindings } from '../src/app/perry-tray-host.ts'
import { MenuBarAppShell } from '../src/app/menu-bar-shell.ts'
import { VoicemailStore } from '../src/storage/store.ts'
import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

test('Perry tray host renders menu items and tooltip', () => {
  const calls: string[] = []
  const bindings = fakeBindings(calls)
  const actions: string[] = []
  const host = createPerryTrayHost(bindings, (action) => actions.push(action))

  host.render({
    title: 'TSRS ready (1)',
    items: [
      { id: 'ready', label: 'Ready', enabled: false },
      { id: 'focus', label: 'Focus', enabled: true },
    ],
  })

  assert.deepEqual(calls, [
    'trayCreate:',
    'menuCreate',
    'traySetTooltip:1:TSRS ready (1)',
    'menuClear:2',
    'menuAddItem:2:Ready ✓',
    'menuAddItem:2:Focus',
    'trayAttachMenu:1:2',
  ])
  assert.deepEqual(actions, [])
})

test('Perry tray adapter performs enabled shell actions', () => {
  const calls: string[] = []
  const callbacks: Array<() => void> = []
  const bindings = fakeBindings(calls, callbacks)
  const store = new VoicemailStore(temporaryDatabasePath())
  const shell = new MenuBarAppShell(store)
  store.enqueue({ project: 'Brain', message: 'The plan is ready.' })

  attachPerryTray(shell, bindings)
  callbacks[0]()

  assert.equal(shell.snapshot().title, 'TSRS ready (1)')
  store.close()
})

function fakeBindings(calls: string[], callbacks: Array<() => void> = []): PerryTrayBindings {
  return {
    trayCreate: (iconPath) => {
      calls.push(`trayCreate:${iconPath}`)
      return 1
    },
    traySetTooltip: (tray, tooltip) => calls.push(`traySetTooltip:${tray}:${tooltip}`),
    trayAttachMenu: (tray, menu) => calls.push(`trayAttachMenu:${tray}:${menu}`),
    menuCreate: () => {
      calls.push('menuCreate')
      return 2
    },
    menuClear: (menu) => calls.push(`menuClear:${menu}`),
    menuAddItem: (menu, label, callback) => {
      calls.push(`menuAddItem:${menu}:${label}`)
      callbacks.push(callback)
    },
    menuAddSeparator: (menu) => calls.push(`menuAddSeparator:${menu}`),
  }
}

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'voicemail.db')
}

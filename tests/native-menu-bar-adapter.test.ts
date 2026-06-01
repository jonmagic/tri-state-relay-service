import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import {
  NativeMenuBarAdapter,
  renderModel,
  type NativeMenuBarRenderModel,
} from '../src/app/native-menu-bar-adapter.ts'
import { MenuBarAppShell } from '../src/app/menu-bar-shell.ts'
import { VoicemailStore } from '../src/storage/store.ts'

test('native menu bar render model exposes safe title and controls', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const shell = new MenuBarAppShell(store)
  store.enqueue({ line: 'Brain', message: 'Do not render this message text.' })

  const model = renderModel(shell.ready())

  assert.equal(model.title, 'TSRS ready (1)')
  assert.deepEqual(model.overview, [
    'Priority: normal 1',
    'Producer: unknown 1',
  ])
  assert.equal(JSON.stringify(model).includes('Do not render this message text.'), false)
  assert.deepEqual(model.items, [
    { id: 'ready', label: 'Ready', enabled: false },
    { id: 'focus', label: 'Focus', enabled: true },
    { id: 'mute', label: 'Mute', enabled: true },
    { id: 'unmute', label: 'Unmute', enabled: false },
    { id: 'clear', label: 'Clear Queue', enabled: true },
  ])
  store.close()
})

test('native menu bar adapter sends rendered models to the host', () => {
  const store = new VoicemailStore(temporaryDatabasePath())
  const rendered: NativeMenuBarRenderModel[] = []
  const shell = new MenuBarAppShell(store)
  const adapter = new NativeMenuBarAdapter(shell, {
    render: (model) => rendered.push(model),
  })
  store.enqueue({ line: 'Brain', message: 'The plan is ready.' })

  adapter.render()
  adapter.perform('ready')
  adapter.perform('mute')
  adapter.perform('clear')

  assert.deepEqual(rendered.map((model) => model.title), [
    'TSRS focus (1)',
    'TSRS ready (1)',
    'TSRS muted (1)',
    'TSRS muted (0)',
  ])
  store.close()
})

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'voicemail.db')
}

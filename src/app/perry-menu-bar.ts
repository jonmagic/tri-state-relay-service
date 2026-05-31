#!/usr/bin/env node
import {
  App,
  Button,
  State,
  Text,
  VStack,
  menuAddItem,
  menuAddSeparator,
  menuBarAddMenu,
  menuBarAttach,
  menuBarCreate,
  menuCreate,
} from 'perry/ui'

import { MenuBarAppShell } from './menu-bar-shell.ts'
import { VoicemailStore } from '../storage/store.ts'

const store = new VoicemailStore()
const shell = new MenuBarAppShell(store, { maxIterations: 1 })
const status = State(shell.snapshot().title)

function refresh(): void {
  status.set(shell.snapshot().title)
}

function ready(): void {
  shell.ready()
  shell.runProcessorLoop().then(refresh)
  refresh()
}

function focus(): void {
  shell.focus()
  refresh()
}

function mute(): void {
  shell.mute()
  refresh()
}

function unmute(): void {
  shell.unmute()
  refresh()
}

function clear(): void {
  shell.clear()
  refresh()
}

const menuBar = menuBarCreate()
const voicemailMenu = menuCreate()
menuAddItem(voicemailMenu, 'Ready', ready)
menuAddItem(voicemailMenu, 'Focus', focus)
menuAddSeparator(voicemailMenu)
menuAddItem(voicemailMenu, 'Mute', mute)
menuAddItem(voicemailMenu, 'Unmute', unmute)
menuAddSeparator(voicemailMenu)
menuAddItem(voicemailMenu, 'Clear Queue', clear)
menuAddItem(voicemailMenu, 'Refresh Status', refresh)
menuBarAddMenu(menuBar, 'Voicemail', voicemailMenu)
menuBarAttach(menuBar)

App({
  title: 'Tri-State Relay Service',
  width: 360,
  height: 220,
  body: VStack(12, [
    Text(`Status: ${status.value}`),
    Button('Ready', ready),
    Button('Focus', focus),
    Button('Mute', mute),
    Button('Unmute', unmute),
    Button('Clear Queue', clear),
    Button('Refresh Status', refresh),
  ]),
})

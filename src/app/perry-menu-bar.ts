#!/usr/bin/env node
import {
  App,
  Text,
  menuAddItem,
  menuAddSeparator,
  menuClear,
  menuCreate,
  trayAttachMenu,
  trayCreate,
  traySetTooltip,
} from 'perry/ui'

import { MenuBarAppShell } from './menu-bar-shell.ts'
import { attachPerryTray } from './perry-tray-host.ts'
import { VoicemailStore } from '../storage/store.ts'

const store = new VoicemailStore()
const shell = new MenuBarAppShell(store, { maxIterations: 1 })

attachPerryTray(shell, {
  trayCreate,
  traySetTooltip,
  trayAttachMenu,
  menuCreate,
  menuClear,
  menuAddItem,
  menuAddSeparator,
})

App({
  title: 'Tri-State Relay Service',
  width: 320,
  height: 120,
  activationPolicy: 'accessory',
  body: Text('Tri-State Relay Service is running in the menu bar.'),
})

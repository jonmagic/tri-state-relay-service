import type { MenuBarAppShell, MenuBarSnapshot } from './menu-bar-shell.ts'

export type NativeMenuBarAction = 'ready' | 'focus' | 'mute' | 'unmute' | 'clear'

export interface NativeMenuBarItem {
  id: NativeMenuBarAction
  label: string
  enabled: boolean
}

export interface NativeMenuBarRenderModel {
  title: string
  items: NativeMenuBarItem[]
}

export interface NativeMenuBarHost {
  render(model: NativeMenuBarRenderModel): void
}

export class NativeMenuBarAdapter {
  private readonly shell: MenuBarAppShell
  private readonly host: NativeMenuBarHost

  constructor(shell: MenuBarAppShell, host: NativeMenuBarHost) {
    this.shell = shell
    this.host = host
  }

  render(): NativeMenuBarRenderModel {
    const model = renderModel(this.shell.snapshot())
    this.host.render(model)
    return model
  }

  perform(action: NativeMenuBarAction): NativeMenuBarRenderModel {
    if (action === 'ready') this.shell.ready()
    if (action === 'focus') this.shell.focus()
    if (action === 'mute') this.shell.mute()
    if (action === 'unmute') this.shell.unmute()
    if (action === 'clear') this.shell.clear()

    return this.render()
  }
}

export function renderModel(snapshot: MenuBarSnapshot): NativeMenuBarRenderModel {
  const status = snapshot.status

  return {
    title: snapshot.title,
    items: [
      { id: 'ready', label: 'Ready', enabled: status.mode !== 'ready' },
      { id: 'focus', label: 'Focus', enabled: status.mode !== 'focus' },
      { id: 'mute', label: 'Mute', enabled: !status.muted },
      { id: 'unmute', label: 'Unmute', enabled: status.muted },
      { id: 'clear', label: 'Clear Queue', enabled: status.attentionCount > 0 },
    ],
  }
}

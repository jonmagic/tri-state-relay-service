import {
  NativeMenuBarAdapter,
  type NativeMenuBarAction,
  type NativeMenuBarHost,
  type NativeMenuBarItem,
  type NativeMenuBarRenderModel,
} from './native-menu-bar-adapter.ts'
import type { MenuBarAppShell } from './menu-bar-shell.ts'

export interface PerryTrayBindings {
  trayCreate(iconPath: string): number
  traySetTooltip(tray: number, tooltip: string): void
  trayAttachMenu(tray: number, menu: number): void
  menuCreate(): number
  menuClear(menu: number): void
  menuAddItem(menu: number, label: string, callback: () => void): void
  menuAddSeparator(menu: number): void
}

export interface PerryTrayHost extends NativeMenuBarHost {
  readonly tray: number
  readonly menu: number
}

export function createPerryTrayHost(bindings: PerryTrayBindings, perform: (action: NativeMenuBarAction) => void): PerryTrayHost {
  const tray = bindings.trayCreate('')
  const menu = bindings.menuCreate()

  return {
    tray,
    menu,
    render: (model) => {
      bindings.traySetTooltip(tray, model.title)
      bindings.menuClear(menu)

      for (const item of model.items) {
        addItem(bindings, menu, item, perform)
      }

      bindings.trayAttachMenu(tray, menu)
    },
  }
}

export function attachPerryTray(shell: MenuBarAppShell, bindings: PerryTrayBindings): NativeMenuBarAdapter {
  let adapter: NativeMenuBarAdapter
  const host = createPerryTrayHost(bindings, (action) => adapter.perform(action))
  adapter = new NativeMenuBarAdapter(shell, host)
  adapter.render()
  return adapter
}

function addItem(
  bindings: PerryTrayBindings,
  menu: number,
  item: NativeMenuBarItem,
  perform: (action: NativeMenuBarAction) => void,
): void {
  const label = item.enabled ? item.label : `${item.label} ✓`

  bindings.menuAddItem(menu, label, () => {
    if (item.enabled) {
      perform(item.id)
    }
  })
}

export function titleFromModel(model: NativeMenuBarRenderModel): string {
  return model.title
}

declare module 'perry/ui' {
  export function App(options: {
    title: string
    width: number
    height: number
    activationPolicy?: 'regular' | 'accessory' | 'background'
    body: number
  }): void

  export function Text(value: string): number
  export function menuAddItem(menu: number, label: string, callback: () => void): void
  export function menuAddSeparator(menu: number): void
  export function menuClear(menu: number): void
  export function menuCreate(): number
  export function trayAttachMenu(tray: number, menu: number): void
  export function trayCreate(iconPath: string): number
  export function traySetTooltip(tray: number, tooltip: string): void
}

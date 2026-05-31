declare module 'perry/ui' {
  export function App(options: {
    title: string
    width: number
    height: number
    activationPolicy?: 'regular' | 'accessory' | 'background'
    body: number
  }): void

  export interface PerryState<T> {
    value: T
    set(value: T): void
  }

  export function Button(label: string, callback: () => void): number
  export function State<T>(value: T): PerryState<T>
  export function Text(value: string): number
  export function VStack(spacing: number, children: number[]): number
  export function menuAddItem(menu: number, label: string, callback: () => void): void
  export function menuAddSeparator(menu: number): void
  export function menuBarAddMenu(menuBar: number, title: string, menu: number): void
  export function menuBarAttach(menuBar: number): void
  export function menuBarCreate(): number
  export function menuCreate(): number
}

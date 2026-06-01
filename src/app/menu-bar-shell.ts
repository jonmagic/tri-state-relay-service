import { AppQueueController, type AppQueueStatus } from './controller.ts'
import { runAppProcessorLoop, type AppProcessorLoopOptions } from './processor-loop.ts'
import type { ProcessOneResult } from '../processor.ts'
import type { RelayStore } from '../storage/store.ts'

export interface MenuBarSnapshot {
  title: string
  status: AppQueueStatus
}

export interface MenuBarAppShellOptions extends AppProcessorLoopOptions {
  onSnapshot?: (snapshot: MenuBarSnapshot) => void
}

export class MenuBarAppShell {
  readonly controller: AppQueueController
  private readonly store: RelayStore
  private readonly options: MenuBarAppShellOptions

  constructor(store: RelayStore, options: MenuBarAppShellOptions = {}) {
    this.store = store
    this.options = options
    this.controller = new AppQueueController(store)
  }

  snapshot(): MenuBarSnapshot {
    const status = this.controller.status()

    return {
      title: menuBarTitle(status),
      status,
    }
  }

  ready(): MenuBarSnapshot {
    this.controller.ready()
    return this.emitSnapshot()
  }

  focus(): MenuBarSnapshot {
    this.controller.focus()
    return this.emitSnapshot()
  }

  mute(): MenuBarSnapshot {
    this.controller.mute()
    return this.emitSnapshot()
  }

  unmute(): MenuBarSnapshot {
    this.controller.unmute()
    return this.emitSnapshot()
  }

  clear(): MenuBarSnapshot {
    this.controller.clear()
    return this.emitSnapshot()
  }

  async runProcessorLoop(): Promise<ProcessOneResult[]> {
    return runAppProcessorLoop(this.store, {
      ...this.options,
      onResult: (result) => {
        this.options.onResult?.(result)
        this.emitSnapshot()
      },
    })
  }

  private emitSnapshot(): MenuBarSnapshot {
    const snapshot = this.snapshot()
    this.options.onSnapshot?.(snapshot)
    return snapshot
  }
}

export function menuBarTitle(status: AppQueueStatus): string {
  if (status.muted) {
    return `TSRS muted (${status.queueCount})`
  }

  if (status.canPlay) {
    return `TSRS ready (${status.queueCount})`
  }

  return `TSRS focus (${status.queueCount})`
}

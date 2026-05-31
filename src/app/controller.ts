import type { QueueCounts, QueueOverview, QueueState, VoicemailStore } from '../storage/store.ts'

export interface AppQueueStatus {
  mode: QueueState['mode']
  muted: boolean
  counts: QueueCounts
  overview: QueueOverview
  queueCount: number
  attentionCount: number
  canPlay: boolean
}

export class AppQueueController {
  private readonly store: VoicemailStore

  constructor(store: VoicemailStore) {
    this.store = store
  }

  status(): AppQueueStatus {
    const state = this.store.getState()
    const counts = this.store.countByStatus()
    const overview = this.store.queueOverview()

    return {
      mode: state.mode,
      muted: state.muted,
      counts,
      overview,
      queueCount: counts.queued,
      attentionCount: counts.queued + counts.heard + counts.failed,
      canPlay: state.mode === 'ready' && !state.muted && counts.queued > 0,
    }
  }

  ready(): AppQueueStatus {
    this.store.setMode('ready')
    return this.status()
  }

  focus(): AppQueueStatus {
    this.store.setMode('focus')
    return this.status()
  }

  mute(): AppQueueStatus {
    this.store.setMuted(true)
    return this.status()
  }

  unmute(): AppQueueStatus {
    this.store.setMuted(false)
    return this.status()
  }

  clear(): AppQueueStatus {
    this.store.clear()
    return this.status()
  }
}

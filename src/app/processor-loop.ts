import { processOneVoicemailWithLock, type ProcessOneResult, type SpeakVoicemail } from '../processor.ts'
import { VoicemailStore } from '../storage/store.ts'

export interface AppProcessorLoopOptions {
  intervalMs?: number
  maxIterations?: number
  sleep?: (milliseconds: number) => Promise<void>
  speak?: SpeakVoicemail
  onResult?: (result: ProcessOneResult) => void
  shouldContinue?: () => boolean
}

export async function runAppProcessorLoop(
  store: VoicemailStore,
  options: AppProcessorLoopOptions = {},
): Promise<ProcessOneResult[]> {
  const intervalMs = options.intervalMs ?? 1000
  const sleep = options.sleep ?? defaultSleep
  const shouldContinue = options.shouldContinue ?? (() => true)
  const results: ProcessOneResult[] = []

  while (shouldContinue() && (options.maxIterations === undefined || results.length < options.maxIterations)) {
    const result = processOneVoicemailWithLock(store, options.speak)
    results.push(result)
    options.onResult?.(result)

    if (!shouldContinue() || (options.maxIterations !== undefined && results.length >= options.maxIterations)) {
      break
    }

    await sleep(intervalMs)
  }

  return results
}

function defaultSleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

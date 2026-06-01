import assert from 'node:assert/strict'
import test from 'node:test'

import { relayCapabilities } from '../src/core/capabilities.ts'

test('app-store capabilities define free safe relay behavior', () => {
  assert.deepEqual(relayCapabilities('app-store'), {
    profile: 'app-store',
    lineLimit: 1,
    nativeSpeech: true,
    terminalEnqueue: false,
    externalSpeechCommand: false,
    externalInactiveLineCombiner: false,
    lineSourceActions: true,
  })
})

test('direct capabilities preserve power-user relay behavior', () => {
  assert.deepEqual(relayCapabilities('direct'), {
    profile: 'direct',
    nativeSpeech: false,
    terminalEnqueue: true,
    externalSpeechCommand: true,
    externalInactiveLineCombiner: true,
    lineSourceActions: true,
  })
})

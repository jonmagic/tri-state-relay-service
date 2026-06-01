import assert from 'node:assert/strict'
import test from 'node:test'

import { normalizeRelay, spokenText } from '../src/core/message.ts'

test('normalizes the smallest agent relay contract', () => {
  const relay = normalizeRelay({
    line: ' Brain ',
    message: ' The plan   is ready. ',
  })

  assert.deepEqual(relay, {
    line: 'Brain',
    message: 'The plan is ready.',
    type: 'update',
    priority: 'normal',
  })
})

test('accepts v0 type, priority, and source metadata', () => {
  const relay = normalizeRelay({
    line: 'Brain',
    message: 'The plan is ready.',
    type: 'complete',
    priority: 'high',
    session: 'agent relay plan',
    app: 'Ghostty',
    cwd: '~/Brain',
  })

  assert.equal(relay.type, 'complete')
  assert.equal(relay.priority, 'high')
  assert.equal(relay.session, 'agent relay plan')
  assert.equal(relay.app, 'Ghostty')
  assert.equal(relay.cwd, '~/Brain')
})

test('rejects obvious token-looking strings', () => {
  assert.throws(() => normalizeRelay({
    line: 'Brain',
    message: 'token=TEST_TOKEN',
  }), /secret or token/)
})

test('formats spoken text with line and non-update type', () => {
  const text = spokenText({
    line: 'Brain',
    type: 'blocked',
    message: 'I need a decision.',
  })

  assert.equal(text, 'Brain. blocked. I need a decision.')
})

test('formats repeated spoken text without line prefix', () => {
  const text = spokenText({
    line: 'Brain',
    type: 'update',
    message: 'The plan is ready.',
  }, { includeLine: false })

  assert.equal(text, 'The plan is ready.')
})

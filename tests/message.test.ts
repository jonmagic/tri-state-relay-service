import assert from 'node:assert/strict'
import test from 'node:test'

import { normalizeVoicemail, spokenText } from '../src/core/message.ts'

test('normalizes the smallest agent voicemail contract', () => {
  const voicemail = normalizeVoicemail({
    project: ' Brain ',
    message: ' The plan   is ready. ',
  })

  assert.deepEqual(voicemail, {
    project: 'Brain',
    message: 'The plan is ready.',
    type: 'update',
    priority: 'normal',
  })
})

test('accepts v0 type, priority, and source metadata', () => {
  const voicemail = normalizeVoicemail({
    project: 'Brain',
    message: 'The plan is ready.',
    type: 'complete',
    priority: 'high',
    session: 'agent voicemail plan',
    app: 'Ghostty',
    cwd: '~/Brain',
  })

  assert.equal(voicemail.type, 'complete')
  assert.equal(voicemail.priority, 'high')
  assert.equal(voicemail.session, 'agent voicemail plan')
  assert.equal(voicemail.app, 'Ghostty')
  assert.equal(voicemail.cwd, '~/Brain')
})

test('rejects obvious token-looking strings', () => {
  assert.throws(() => normalizeVoicemail({
    project: 'Brain',
    message: 'token=TEST_TOKEN',
  }), /secret or token/)
})

test('formats spoken text with project and non-update type', () => {
  const text = spokenText({
    project: 'Brain',
    type: 'blocked',
    message: 'I need a decision.',
  })

  assert.equal(text, 'Brain. blocked. I need a decision.')
})

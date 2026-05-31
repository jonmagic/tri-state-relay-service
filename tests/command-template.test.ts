import assert from 'node:assert/strict'
import test from 'node:test'

import { buildCommandInvocation, commandIsEnabled, defaultInactiveLineCombinerCommand } from '../src/core/command-template.ts'

test('comment-only command templates are disabled', () => {
  assert.equal(commandIsEnabled(defaultInactiveLineCombinerCommand), false)
})

test('placeholders are inserted as single argv values', () => {
  const command = buildCommandInvocation('tool --message <message>', {
    '<message>': 'hello; rm -rf ~',
  })

  assert.deepEqual(command, {
    command: 'tool',
    args: ['--message', 'hello; rm -rf ~'],
  })
})

test('quoted command template values are tokenized before placeholder insertion', () => {
  const command = buildCommandInvocation('/usr/bin/say --voice "Good News" <message>', {
    '<message>': 'Build complete.',
  })

  assert.deepEqual(command, {
    command: '/usr/bin/say',
    args: ['--voice', 'Good News', 'Build complete.'],
  })
})

import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import assert from 'node:assert/strict'
import test from 'node:test'

import { assertRelayProcessorNotBundled } from '../scripts/macos-bundle-validation.mjs'

const fixtureRoot = join('dist', 'test-bundle-validation')

test('bundle validation accepts app bundles without relay-processor', (t) => {
  const appPath = fixtureApp('Good.app')
  t.after(() => rmSync(appPath, { recursive: true, force: true }))

  assert.doesNotThrow(() => assertRelayProcessorNotBundled(appPath))
})

test('bundle validation rejects relay-processor anywhere in the app bundle', (t) => {
  const appPath = fixtureApp('Bad.app')
  t.after(() => rmSync(appPath, { recursive: true, force: true }))
  const nestedProcessor = join(appPath, 'Contents', 'Resources', 'Nested', 'relay-processor')
  writeFileSync(nestedProcessor, '')

  assert.throws(
    () => assertRelayProcessorNotBundled(appPath),
    /relay-processor must not be bundled/,
  )
})

function fixtureApp(name: string): string {
  const appPath = join(fixtureRoot, name)
  rmSync(appPath, { recursive: true, force: true })
  mkdirSync(join(appPath, 'Contents', 'MacOS'), { recursive: true })
  mkdirSync(join(appPath, 'Contents', 'Resources', 'Nested'), { recursive: true })

  return appPath
}

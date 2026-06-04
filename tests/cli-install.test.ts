import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import assert from 'node:assert/strict'
import test from 'node:test'

import { cliInstallStatus, installRelayCli } from '../src/core/cli-install.ts'

test('cli install status reports missing target and PATH guidance', () => {
  const dir = temporaryDirectory()
  const source = executableFile(dir, 'bundled-relay', relayScript('0.1.0', 'bundled'))
  const target = join(dir, 'bin', 'relay')

  const status = cliInstallStatus({ sourcePath: source, targetPath: target, pathValue: '/usr/bin:/bin' })

  assert.equal(status.status, 'missing')
  assert.equal(status.targetDirectoryOnPath, false)
  assert.equal(status.targetPath, target)
})

test('install relay cli copies bundled executable to target', async () => {
  const dir = temporaryDirectory()
  const source = executableFile(dir, 'bundled-relay', relayScript('0.1.0', 'bundled'))
  const target = join(dir, 'bin', 'relay')

  const installed = await installRelayCli({ sourcePath: source, targetPath: target, pathValue: `${join(dir, 'bin')}:/usr/bin` })

  assert.equal(installed.status, 'current')
  assert.equal(installed.targetDirectoryOnPath, true)
  assert.equal(cliInstallStatus({ sourcePath: source, targetPath: target }).status, 'current')
})

test('cli install status detects stale TSRS relay and updates it', async () => {
  const dir = temporaryDirectory()
  const source = executableFile(dir, 'bundled-relay', relayScript('0.1.0', 'bundled'))
  const target = executableFile(join(dir, 'bin'), 'relay', relayScript('0.0.9', 'old'))

  const stale = cliInstallStatus({ sourcePath: source, targetPath: target })

  assert.equal(stale.status, 'stale')

  const updated = await installRelayCli({ sourcePath: source, targetPath: target })

  assert.equal(updated.status, 'current')
})

test('install relay cli refuses to overwrite a foreign relay binary', async () => {
  const dir = temporaryDirectory()
  const source = executableFile(dir, 'bundled-relay', relayScript('0.1.0', 'bundled'))
  const target = executableFile(join(dir, 'bin'), 'relay', '#!/bin/sh\necho "not tsrs"\n')

  const foreign = cliInstallStatus({ sourcePath: source, targetPath: target })

  assert.equal(foreign.status, 'foreign')
  assert.throws(
    () => installRelayCli({ sourcePath: source, targetPath: target }),
    /does not look like a TSRS relay CLI/,
  )
})

test('cli install status reports missing bundled source', () => {
  const dir = temporaryDirectory()

  const status = cliInstallStatus({
    sourcePath: join(dir, 'missing-relay'),
    targetPath: join(dir, 'bin', 'relay'),
  })

  assert.equal(status.status, 'source-missing')
})

function temporaryDirectory(): string {
  return mkdtempSync(join(tmpdir(), 'tsrs-cli-install-'))
}

function executableFile(dir: string, name: string, content: string): string {
  mkdirSync(dir, { recursive: true })
  const path = join(dir, name)
  writeFileSync(path, content)
  chmodSync(path, 0o755)
  return path
}

function relayScript(version: string, marker: string): string {
  return `#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "relay ${version}"
  exit 0
fi
echo "${marker}"
`
}

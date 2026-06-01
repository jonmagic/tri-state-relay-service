import { mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { spawnSync } from 'node:child_process'
import assert from 'node:assert/strict'
import test from 'node:test'

const cliPath = join(process.cwd(), 'src', 'cli.ts')

test('app helper commands require app authorization', () => {
  const dbPath = temporaryDatabasePath()
  runCli(dbPath, ['--line', 'Brain', '--message', 'The plan is ready.'])

  const denied = runCli(dbPath, ['app-claim-next'], { TSRS_DISTRIBUTION_PROFILE: 'app-store' })

  assert.notEqual(denied.status, 0)
  assert.match(denied.stderr, /app helper commands require TSRS app authorization/)
})

test('app-store profile rejects terminal relay enqueueing', () => {
  const dbPath = temporaryDatabasePath()

  const denied = runCli(dbPath, ['--line', 'Brain', '--message', 'The plan is ready.'], {
    TSRS_DISTRIBUTION_PROFILE: 'app-store',
  })
  const listed = runCli(dbPath, ['list'])

  assert.notEqual(denied.status, 0)
  assert.match(denied.stderr, /terminal relay enqueueing is direct-profile-only/)
  assert.equal(listed.stdout, 'mode=focus muted=false')
})

test('direct profile allows terminal relay enqueueing', () => {
  const dbPath = temporaryDatabasePath()

  const queued = runCli(dbPath, ['--line', 'Brain', '--message', 'The plan is ready.'])

  assert.equal(queued.status, 0)
  assert.match(queued.stdout, /queued relay #1 Brain/)
})

test('authorized app helper command claims one relay for native speech', () => {
  const dbPath = temporaryDatabasePath()
  runCli(dbPath, ['--line', 'Brain', '--message', 'The plan is ready.'])
  runCli(dbPath, ['ready'])

  const claimed = runCli(dbPath, ['app-claim-next'], {
    TSRS_DISTRIBUTION_PROFILE: 'app-store',
    TSRS_PROCESSOR_AUTH: 'app-owned-processor',
  })

  assert.equal(claimed.status, 0)
  assert.deepEqual(JSON.parse(claimed.stdout), {
    id: 1,
    text: 'Brain. The plan is ready.',
    line: 'Brain',
  })
})

test('app-store source CLI commands do not shell out', () => {
  const dbPath = temporaryDatabasePath()
  runCli(dbPath, ['--line', 'Brain', '--message', 'The plan is ready.', '--cwd', '/tmp'])

  const revealed = runCli(dbPath, ['reveal-source'], { TSRS_DISTRIBUTION_PROFILE: 'app-store' })
  const copied = runCli(dbPath, ['copy-source'], { TSRS_DISTRIBUTION_PROFILE: 'app-store' })

  assert.equal(revealed.status, 0)
  assert.match(revealed.stdout, /unavailable from the CLI in the App Store-safe profile/)
  assert.equal(copied.status, 0)
  assert.match(copied.stdout, /unavailable from the CLI in the App Store-safe profile/)
})

test('status and settings expose the active distribution profile', () => {
  const dbPath = temporaryDatabasePath()
  runCli(dbPath, ['--line', 'Brain', '--message', 'The plan is ready.'])

  const status = runCli(dbPath, ['status'], { TSRS_DISTRIBUTION_PROFILE: 'app-store' })
  const settings = runCli(dbPath, ['settings'], { TSRS_DISTRIBUTION_PROFILE: 'app-store' })

  assert.equal(status.status, 0)
  assert.equal(JSON.parse(status.stdout).profile, 'app-store')
  assert.equal(JSON.parse(status.stdout).capabilities.nativeSpeech, true)
  assert.equal(settings.status, 0)
  assert.equal(JSON.parse(settings.stdout).profile, 'app-store')
})

test('relay terminology lifecycle aliases preserve storage behavior', () => {
  const dbPath = temporaryDatabasePath()
  runCli(dbPath, ['--line', 'Brain', '--message', 'The plan is ready.'])
  runCli(dbPath, ['ready'])
  runCli(dbPath, ['app-claim-next'], { TSRS_PROCESSOR_AUTH: 'app-owned-processor' })
  runCli(dbPath, ['app-mark-heard', '--id', '1'], { TSRS_PROCESSOR_AUTH: 'app-owned-processor' })

  const acknowledged = runCli(dbPath, ['acknowledge'])

  assert.equal(acknowledged.status, 0)
  assert.match(acknowledged.stdout, /handled relay #1/)

  runCli(dbPath, ['--line', 'Brain', '--message', 'The second plan is ready.'])
  runCli(dbPath, ['ready'])
  runCli(dbPath, ['app-claim-next'], { TSRS_PROCESSOR_AUTH: 'app-owned-processor' })
  runCli(dbPath, ['app-mark-heard', '--id', '2'], { TSRS_PROCESSOR_AUTH: 'app-owned-processor' })

  const cleared = runCli(dbPath, ['clear-delivered'])

  assert.equal(cleared.status, 0)
  assert.match(cleared.stdout, /cleared 1 delivered relays/)
})

function runCli(dbPath: string, args: string[], env: Record<string, string> = {}): { status: number | null, stdout: string, stderr: string } {
  const result = spawnSync(process.execPath, ['--experimental-strip-types', cliPath, ...args], {
    encoding: 'utf8',
    env: {
      ...process.env,
      TSRS_DB_PATH: dbPath,
      ...env,
    },
  })

  return {
    status: result.status,
    stdout: result.stdout.trim(),
    stderr: result.stderr.trim(),
  }
}

function temporaryDatabasePath(): string {
  return join(mkdtempSync(join(tmpdir(), 'tsrs-')), 'relay.db')
}

#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs'
import { basename, join } from 'node:path'
import { spawnSync } from 'node:child_process'

const appName = 'Tri-State Relay Service.app'
const appPath = join('dist/macos', appName)
const appExecutable = join(appPath, 'Contents/MacOS/Tri-State Relay Service')
const relayExecutable = join(appPath, 'Contents/MacOS/relay')
const infoPlist = join(appPath, 'Contents/Info.plist')
const releasesDir = 'dist/releases'
const submissionZip = join(releasesDir, 'notary-submission.zip')

const packageJson = JSON.parse(readFileSync('package.json', 'utf8'))
const version = packageJson.version
const arch = process.arch === 'arm64' ? 'arm64' : process.arch
const releaseZip = join(releasesDir, `Tri-State Relay Service-${version}-macos-${arch}.zip`)
const identity = selectedIdentity()
const notaryProfile = process.env.TSRS_NOTARYTOOL_PROFILE

if (!notaryProfile) {
  throw new Error('TSRS_NOTARYTOOL_PROFILE is required for a shareable notarized build')
}

run('npm', ['run', 'build:macos:direct'])
assertBuiltBundle()
assertVersionMatches()

mkdirSync(releasesDir, { recursive: true })
rmSync(submissionZip, { force: true })
rmSync(releaseZip, { force: true })

sign(relayExecutable)
run(relayExecutable, ['status'])
sign(appPath)
verifySignedBundle()

zipApp(submissionZip)
run('xcrun', ['notarytool', 'submit', submissionZip, '--keychain-profile', notaryProfile, '--wait'])
run('xcrun', ['stapler', 'staple', appPath])
run('xcrun', ['stapler', 'validate', appPath])
run('spctl', ['--assess', '--type', 'exec', '--verbose=2', appPath])

zipApp(releaseZip)
rmSync(submissionZip, { force: true })

console.log(`Wrote ${releaseZip}`)

function selectedIdentity() {
  if (process.env.TSRS_CODESIGN_IDENTITY) {
    ensureDeveloperId(process.env.TSRS_CODESIGN_IDENTITY)
    return process.env.TSRS_CODESIGN_IDENTITY
  }

  const result = spawnSync('security', ['find-identity', '-v', '-p', 'codesigning'], {
    encoding: 'utf8',
  })

  if (result.status !== 0) {
    throw new Error(`could not read code signing identities: ${result.stderr}`)
  }

  const identities = result.stdout
    .split('\n')
    .map((line) => line.match(/"([^"]+)"/)?.[1])
    .filter(Boolean)
  const developerIds = identities.filter((name) => name.startsWith('Developer ID Application: '))

  if (developerIds.length === 1) {
    return developerIds[0]
  }

  if (developerIds.length > 1) {
    throw new Error('multiple Developer ID Application identities found; set TSRS_CODESIGN_IDENTITY')
  }

  const developmentIds = identities.filter((name) => name.startsWith('Apple Development: '))

  if (developmentIds.length > 0) {
    throw new Error('Apple Development certificates are not sufficient for sharing outside your machines; install a Developer ID Application certificate')
  }

  throw new Error('no Developer ID Application signing identity found')
}

function ensureDeveloperId(name) {
  if (!name.startsWith('Developer ID Application: ')) {
    throw new Error('TSRS_CODESIGN_IDENTITY must be a Developer ID Application identity')
  }
}

function assertBuiltBundle() {
  for (const path of [appPath, appExecutable, relayExecutable, infoPlist]) {
    if (!existsSync(path)) {
      throw new Error(`expected build output is missing: ${path}`)
    }
  }
}

function assertVersionMatches() {
  const bundleVersion = plistValue('CFBundleShortVersionString')

  if (bundleVersion !== version) {
    throw new Error(`package.json version ${version} does not match app version ${bundleVersion}`)
  }
}

function sign(path) {
  run('codesign', ['--force', '--options', 'runtime', '--timestamp', '--sign', identity, path])
}

function verifySignedBundle() {
  run('codesign', ['--verify', '--strict', '--deep', '--verbose=2', appPath])
  run('codesign', ['--display', '--verbose=2', appPath])
}

function zipApp(outputPath) {
  run('ditto', ['-c', '-k', '--keepParent', basename(appPath), join('..', '..', outputPath)], {
    cwd: 'dist/macos',
  })
}

function plistValue(key) {
  const result = spawnSync('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, infoPlist], {
    encoding: 'utf8',
  })

  if (result.status !== 0) {
    throw new Error(`could not read ${key} from ${infoPlist}: ${result.stderr}`)
  }

  return result.stdout.trim()
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options })

  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed`)
  }
}

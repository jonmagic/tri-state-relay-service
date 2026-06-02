#!/usr/bin/env node
import { existsSync } from 'node:fs'
import { spawnSync } from 'node:child_process'

const appPath = 'dist/macos/Tri-State Relay Service.app'
const executablePath = `${appPath}/Contents/MacOS/Tri-State Relay Service`

if (!existsSync(executablePath)) {
  throw new Error(`rebuilt app executable missing: ${executablePath}`)
}

for (const pid of runningAppPids()) {
  run('kill', [pid])
}

if (runningAppPids().length > 0) {
  run('sleep', ['1'])
}

for (const pid of runningAppPids()) {
  run('kill', ['-9', pid])
}

run('open', [appPath])
run('sleep', ['2'])

const pids = runningAppPids()

if (pids.length === 0) {
  throw new Error('rebuilt app did not start')
}

console.log(`running ${pids[0]} ${executablePath}`)

function runningAppPids() {
  const result = spawnSync('pgrep', ['-f', executablePath], { encoding: 'utf8' })

  if (result.status !== 0 && result.status !== 1) {
    throw new Error(result.stderr || 'pgrep failed')
  }

  return result.stdout
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => /^[0-9]+$/.test(line))
}

function run(command, args) {
  const result = spawnSync(command, args, { stdio: 'inherit' })

  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed`)
  }
}

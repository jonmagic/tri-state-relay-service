import { copyFileSync, existsSync, mkdirSync, readFileSync, statSync } from 'node:fs'
import { chmodSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { homedir } from 'node:os'
import { spawnSync } from 'node:child_process'

export const relayVersion = '0.1.0'

export type CliInstallStatusKind = 'missing' | 'current' | 'stale' | 'foreign' | 'source-missing'

export interface CliInstallStatus {
  status: CliInstallStatusKind
  sourcePath: string
  targetPath: string
  sourceSignature?: string
  targetSignature?: string
  targetDirectoryOnPath: boolean
  version: string
  message: string
}

export interface CliInstallOptions {
  sourcePath?: string
  targetPath?: string
  pathValue?: string
}

export function defaultCliInstallTarget(): string {
  return join(homedir(), '.local', 'bin', 'relay')
}

export function currentRelayExecutable(): string {
  if (process.env.TSRS_RELAY_SOURCE !== undefined) {
    return process.env.TSRS_RELAY_SOURCE
  }

  if (process.argv[1] !== undefined && process.argv[1].endsWith('/relay')) {
    return process.argv[1]
  }

  return process.execPath
}

export function cliInstallStatus(options: CliInstallOptions = {}): CliInstallStatus {
  const sourcePath = options.sourcePath ?? currentRelayExecutable()
  const targetPath = options.targetPath ?? process.env.TSRS_RELAY_INSTALL_TARGET ?? defaultCliInstallTarget()
  const targetDirectoryOnPath = pathContainsDirectory(dirname(targetPath), options.pathValue ?? process.env.PATH ?? '')

  if (!existsSync(sourcePath)) {
    return {
      status: 'source-missing',
      sourcePath,
      targetPath,
      targetDirectoryOnPath,
      version: relayVersion,
      message: `relay source is missing: ${sourcePath}`,
    }
  }

  const sourceSignature = fileSignature(sourcePath)

  if (!existsSync(targetPath)) {
    return {
      status: 'missing',
      sourcePath,
      targetPath,
      sourceSignature,
      targetDirectoryOnPath,
      version: relayVersion,
      message: `relay CLI is not installed at ${targetPath}`,
    }
  }

  const targetSignature = fileSignature(targetPath)

  if (filesAreEqual(sourcePath, targetPath)) {
    return {
      status: 'current',
      sourcePath,
      targetPath,
      sourceSignature,
      targetSignature,
      targetDirectoryOnPath,
      version: relayVersion,
      message: `relay CLI is current at ${targetPath}`,
    }
  }

  if (!targetLooksLikeRelay(targetPath)) {
    return {
      status: 'foreign',
      sourcePath,
      targetPath,
      sourceSignature,
      targetSignature,
      targetDirectoryOnPath,
      version: relayVersion,
      message: `${targetPath} exists but does not look like a TSRS relay CLI`,
    }
  }

  return {
    status: 'stale',
    sourcePath,
    targetPath,
    sourceSignature,
    targetSignature,
    targetDirectoryOnPath,
    version: relayVersion,
    message: `relay CLI at ${targetPath} differs from bundled version ${relayVersion}`,
  }
}

export function installRelayCli(options: CliInstallOptions = {}): CliInstallStatus {
  const status = cliInstallStatus(options)

  if (status.status === 'current') {
    return status
  }

  if (status.status === 'source-missing' || status.status === 'foreign') {
    throw new Error(status.message)
  }

  mkdirSync(dirname(status.targetPath), { recursive: true })
  copyFileSync(status.sourcePath, status.targetPath)
  chmodSync(status.targetPath, executableMode(status.sourcePath))

  return cliInstallStatus(options)
}

function fileSignature(path: string): string {
  const stats = statSync(path)
  return `${stats.size}:${stats.mtimeMs}`
}

function filesAreEqual(left: string, right: string): boolean {
  const leftContent = readFileSync(left)
  const rightContent = readFileSync(right)

  if (leftContent.length !== rightContent.length) {
    return false
  }

  for (let index = 0; index < leftContent.length; index += 1) {
    if (leftContent[index] !== rightContent[index]) {
      return false
    }
  }

  return true
}

function executableMode(path: string): number {
  return statSync(path).mode | 0o755
}

function pathContainsDirectory(directory: string, pathValue: string): boolean {
  return pathValue.split(':').filter(Boolean).some((entry) => entry === directory)
}

function targetLooksLikeRelay(path: string): boolean {
  const result = spawnSync(path, ['--version'], {
    encoding: 'utf8',
    timeout: 2_000,
  })

  return result.status === 0 && result.stdout.trim().startsWith('relay ')
}

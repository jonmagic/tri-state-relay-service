import { readdirSync } from 'node:fs'
import { join } from 'node:path'

export function assertRelayProcessorNotBundled(appPath) {
  const bundledProcessorPaths = findEntriesNamed(appPath, 'relay-processor')

  if (bundledProcessorPaths.length > 0) {
    throw new Error(`relay-processor must not be bundled in the macOS app: ${bundledProcessorPaths.join(', ')}`)
  }
}

function findEntriesNamed(rootPath, forbiddenName) {
  const matches = []
  const pending = [rootPath]

  while (pending.length > 0) {
    const currentPath = pending.pop()

    for (const entry of readdirSync(currentPath, { withFileTypes: true })) {
      const entryPath = join(currentPath, entry.name)

      if (entry.name === forbiddenName) {
        matches.push(entryPath)
      }

      if (entry.isDirectory()) {
        pending.push(entryPath)
      }
    }
  }

  return matches
}

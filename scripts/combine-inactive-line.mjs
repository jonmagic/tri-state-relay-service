import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const tool = process.argv[2]
const input = process.argv[3] ?? readStdin()
const prompt = readFileSync(join(process.cwd(), 'docs', 'prompts', 'combine-inactive-line.md'), 'utf8')

if (tool !== 'llm' && tool !== 'apfel') {
  process.stderr.write('tool must be llm or apfel\n')
  process.exit(2)
}

const result = tool === 'apfel'
  ? spawnSync('apfel', ['--system', prompt, '--max-tokens', '160', '--temperature', '0', '--output', 'plain', input], { encoding: 'utf8' })
  : spawnSync('llm', ['prompt', input, '--system', prompt, '--no-stream', '--no-log'], { encoding: 'utf8' })

if (result.status !== 0) {
  process.stderr.write(`${result.stdout}${result.stderr}`)
  process.exit(result.status ?? 1)
}

const json = extractJson(result.stdout)

if (json === undefined) {
  process.stderr.write(`No JSON object in combiner output: ${result.stdout}\n`)
  process.exit(1)
}

process.stdout.write(`${json}\n`)

function readStdin() {
  try {
    return readFileSync(0, 'utf8')
  } catch {
    return ''
  }
}

function extractJson(output) {
  const start = output.indexOf('{')
  const end = output.lastIndexOf('}')

  if (start >= 0 && end > start) {
    return output.slice(start, end + 1)
  }

  return undefined
}

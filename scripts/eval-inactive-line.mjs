import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

const root = new URL('..', import.meta.url).pathname
const fixturesPath = join(root, 'evals/inactive-line-fixtures.json')
const combinePromptPath = join(root, 'docs/prompts/combine-inactive-line.md')
const evaluatorPromptPath = join(root, 'docs/prompts/evaluate-inactive-line.md')
const outputPath = join(root, 'evals/results/inactive-line-results.json')
const fixtures = JSON.parse(readFileSync(fixturesPath, 'utf8'))
const combinePrompt = readFileSync(combinePromptPath, 'utf8')
const evaluatorPrompt = readFileSync(evaluatorPromptPath, 'utf8')
const requestedTools = (process.env.TSRS_EVAL_TOOLS ?? 'apfel,llm').split(',').map((tool) => tool.trim()).filter(Boolean)
const judgeTool = process.env.TSRS_EVAL_JUDGE ?? 'apfel'
const results = []

for (const fixture of fixtures) {
  for (const tool of requestedTools) {
    if (!commandExists(tool)) {
      results.push({ fixture: fixture.id, tool, ok: false, error: 'tool not found' })
      continue
    }

    const candidateText = runCandidateTool(tool, JSON.stringify(fixture.input))
    const contract = validateCandidate(candidateText, fixture.expect)
    const judge = commandExists(judgeTool)
      ? runJudge(judgeTool, fixture, candidateText)
      : { score: 0, verdict: 'reject', reason: 'judge tool not found' }

    results.push({
      fixture: fixture.id,
      tool,
      ok: contract.ok && judge.verdict === 'keep' && Number(judge.score) >= 7,
      contract,
      judge,
      candidateText,
    })
  }
}

mkdirSync(dirname(outputPath), { recursive: true })
writeFileSync(outputPath, `${JSON.stringify(results, null, 2)}\n`)
printSummary(results)

function runCandidateTool(tool, input) {
  if (tool === 'apfel') {
    return run('apfel', ['--system-file', combinePromptPath, '--max-tokens', '160', '--temperature', '0', '--output', 'plain', input])
  }

  if (tool === 'llm') {
    return run('llm', ['prompt', input, '--system', combinePrompt, '--no-stream', '--no-log'])
  }

  throw new Error(`unsupported tool: ${tool}`)
}

function runJudge(tool, fixture, candidateText) {
  const judgeInput = JSON.stringify({
    fixture,
    candidateText,
  })
  const output = tool === 'apfel'
    ? run('apfel', ['--system-file', evaluatorPromptPath, '--max-tokens', '120', '--temperature', '0', '--output', 'plain', judgeInput])
    : run('llm', ['prompt', judgeInput, '--system', evaluatorPrompt, '--no-stream', '--no-log'])

  try {
    return JSON.parse(extractJson(output))
  } catch {
    return { score: 0, verdict: 'reject', reason: `invalid judge output: ${output.slice(0, 120)}` }
  }
}

function validateCandidate(candidateText, expect) {
  const errors = []
  let candidate

  try {
    candidate = JSON.parse(extractJson(candidateText))
  } catch {
    return { ok: false, errors: ['candidate is not valid JSON'] }
  }

  for (const key of ['action', 'type', 'priority', 'message']) {
    if (!(key in candidate)) errors.push(`missing ${key}`)
  }

  if (!['drop', 'replace', 'promote'].includes(candidate.action)) errors.push('invalid action')
  if (candidate.action !== expect.action) errors.push(`expected action ${expect.action}`)
  if (expect.type !== undefined && candidate.type !== expect.type) errors.push(`expected type ${expect.type}`)
  if (expect.priority !== undefined && candidate.priority !== expect.priority) errors.push(`expected priority ${expect.priority}`)
  if (typeof candidate.message !== 'string') errors.push('message is not a string')
  if (typeof candidate.message === 'string' && candidate.message.length > 160) errors.push('message is longer than 160 chars')

  for (const text of expect.mustInclude ?? []) {
    if (!candidate.message.toLowerCase().includes(text.toLowerCase())) errors.push(`message missing ${text}`)
  }

  for (const text of expect.mustAvoid ?? []) {
    if (candidate.message.toLowerCase().includes(text.toLowerCase())) errors.push(`message includes ${text}`)
  }

  return { ok: errors.length === 0, errors, candidate }
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    input: '',
    maxBuffer: 1024 * 1024,
  })

  if (result.error !== undefined) {
    throw result.error
  }

  if (result.status !== 0) {
    return `${result.stdout}${result.stderr}`.trim()
  }

  return result.stdout.trim()
}

function extractJson(text) {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (fenced !== null) return fenced[1].trim()
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start >= 0 && end > start) return text.slice(start, end + 1)
  return text.trim()
}

function commandExists(command) {
  return spawnSync('sh', ['-lc', `command -v ${command}`], { stdio: 'ignore' }).status === 0
}

function printSummary(items) {
  console.log('| Scenario | Tool | Contract | Judge | Score | Candidate |')
  console.log('| --- | --- | --- | --- | ---: | --- |')

  for (const item of items) {
    const contract = item.contract?.ok ? 'pass' : 'fail'
    const judge = item.judge?.verdict ?? 'n/a'
    const score = item.judge?.score ?? 0
    const message = item.contract?.candidate?.message ?? item.candidateText ?? item.error
    console.log(`| ${item.fixture} | ${item.tool} | ${contract} | ${judge} | ${score} | ${String(message).replaceAll('|', '\\|')} |`)
  }

  console.log(`\nWrote ${outputPath}`)
}

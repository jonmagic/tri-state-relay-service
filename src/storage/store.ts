import { mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { homedir } from 'node:os'
import Database from 'better-sqlite3'

import { commandIsEnabled, defaultInactiveLineCombinerCommand, defaultSpeechCommand, resetBlankCommand } from '../core/command-template.ts'
import { type DistributionProfile, distributionProfile } from '../core/distribution-profile.ts'
import { normalizeRelay, priorities, type MessageStatus, type MessageType, type NewRelay, type NewRelayInput, type Priority, type Relay } from '../core/message.ts'

export type PlaybackMode = 'focus' | 'ready'
export type InactiveLineCombiner = 'none' | 'custom'

export interface QueueState {
  mode: PlaybackMode
  muted: boolean
  inactiveLineCombiner: InactiveLineCombiner
  inactiveLineCombinerCommand: string
  speechCommand: string
  activeLine?: string
}

export type QueueCounts = Record<MessageStatus, number>

export interface LineSummary {
  line: string
  queued: number
  heard: number
  failed: number
}

export interface QueueOverviewItem {
  count: number
}

export interface PriorityOverviewItem extends QueueOverviewItem {
  priority: Priority
}

export interface ProducerOverviewItem extends QueueOverviewItem {
  producer: string
}

export interface StaleBlockerOverview {
  count: number
  thresholdMinutes: number
  oldestCreatedAt?: string
}

export interface QueueOverviewOptions {
  now?: Date
  staleBlockerAgeMinutes?: number
  limit?: number
}

export interface QueueOverview {
  byPriority: PriorityOverviewItem[]
  byProducer: ProducerOverviewItem[]
  staleBlockers: StaleBlockerOverview
}

export interface SourceContext {
  id: number
  line: string
  session?: string
  app?: string
  cwd?: string
  url?: string
}

export interface InactiveLineCombineInput {
  activeLine?: string
  inactiveLine: string
  existingPendingMessage?: string
  incoming: Array<{
    type: MessageType
    priority: Priority
    message: string
  }>
}

export interface InactiveLineCombineResult {
  action: 'drop' | 'replace' | 'promote'
  type: MessageType
  priority: Priority
  message: string
}

export type InactiveLineCombinerFunction = (input: InactiveLineCombineInput) => InactiveLineCombineResult | undefined

const schemaVersion = 1
const defaultQueueOverviewLimit = 10
export const defaultStaleBlockerAgeMinutes = 15
export const defaultStaleRelayAgeMinutes = 30
const defaultProcessorLockTtlMs = 60_000

export interface ProcessorLockOptions {
  now?: Date
  ttlMs?: number
  isOwnerAlive?: (owner: string) => boolean
}

export interface SpokenLineState {
  line: string
  spokenAt: string
}

export interface StaleSpeakingOptions {
  now?: Date
  ttlMs?: number
}

export interface StaleRelayOptions {
  now?: Date
  ageMinutes?: number
}

export class RelayStore {
  readonly path: string
  readonly database: Database.Database

  constructor(path = defaultDatabasePath()) {
    this.path = path
    mkdirSync(dirname(path), { recursive: true })
    this.database = new Database(path)
    this.migrate()
  }

  close(): void {
    this.database.close()
  }

  queuedCountForLine(line: string): number {
    const row = this.database.prepare(`
      SELECT COUNT(*) AS count
      FROM relays
      WHERE status = 'queued' AND line = ?
    `).get(line) as { count: number }

    return Number(row.count)
  }

  enqueue(input: NewRelayInput): Relay {
    const relay = normalizeRelay(input)
    const inserted = this.insertRelay(relay)
    this.setInitialActiveLine(inserted.line)
    return inserted
  }

  enqueueWithLinePolicy(input: NewRelayInput, combine?: InactiveLineCombinerFunction): Relay | undefined {
    const relay = normalizeRelay(input)
    const state = this.getState()

    if (state.activeLine === undefined || relay.line === state.activeLine) {
      const inserted = this.insertRelay(relay)
      this.setInitialActiveLine(inserted.line)
      return inserted
    }

    if (state.inactiveLineCombiner === 'none' || combine === undefined) {
      this.deleteQueuedForLine(relay.line)
      return this.insertRelay(relay)
    }

    const existing = this.queuedForLine(relay.line)
    const combined = combine({
      activeLine: state.activeLine,
      inactiveLine: relay.line,
      existingPendingMessage: lastItem(existing)?.message,
      incoming: [
        ...existing.map((item) => ({
          type: item.type,
          priority: item.priority,
          message: item.message,
        })),
        {
          type: relay.type,
          priority: relay.priority,
          message: relay.message,
        },
      ],
    })

    if (combined === undefined || combined.action === 'drop') {
      return lastItem(existing)
    }

    this.deleteQueuedForLine(relay.line)
    return this.insertRelay({
      ...relay,
      message: combined.message,
      type: combined.type,
      priority: combined.priority,
    })
  }

  private insertRelay(relay: NewRelay): Relay {
    const now = new Date().toISOString()
    const insert = this.database.prepare(`
      INSERT INTO relays (
        line, message, type, priority, session, app, cwd, url, status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?)
      RETURNING *
    `)

    return mapRelay(insert.get(
      relay.line,
      relay.message,
      relay.type,
      relay.priority,
      relay.session ?? null,
      relay.app ?? null,
      relay.cwd ?? null,
      relay.url ?? null,
      now,
      now,
    ))
  }

  private queuedForLine(line: string): Relay[] {
    const select = this.database.prepare(`
      SELECT *
      FROM relays
      WHERE line = ? AND status = 'queued'
      ORDER BY created_at ASC
    `)

    return select.all(line).map(mapRelay)
  }

  private deleteQueuedForLine(line: string): number {
    const result = this.database.prepare(`
      DELETE FROM relays
      WHERE line = ? AND status = 'queued'
    `).run(line)

    return Number(result.changes)
  }

  list(limit = 20): Relay[] {
    const select = this.database.prepare(`
      SELECT *
      FROM relays
      ORDER BY
        CASE status
          WHEN 'speaking' THEN 0
          WHEN 'queued' THEN 1
          WHEN 'heard' THEN 2
          ELSE 3
        END,
        created_at ASC
      LIMIT ?
    `)

    return select.all(limit).map(mapRelay)
  }

  countByStatus(): QueueCounts {
    const counts: QueueCounts = {
      queued: 0,
      speaking: 0,
      heard: 0,
      handled: 0,
      skipped: 0,
      expired: 0,
      failed: 0,
    }
    const rows = this.database.prepare(`
      SELECT status, COUNT(*) AS count
      FROM relays
      GROUP BY status
    `).all() as Array<{ status: MessageStatus, count: number }>

    for (const row of rows) {
      counts[row.status] = Number(row.count)
    }

    return counts
  }

  lineSummaries(): LineSummary[] {
    const rows = this.database.prepare(`
      SELECT
        line,
        SUM(CASE WHEN status = 'queued' THEN 1 ELSE 0 END) AS queued,
        SUM(CASE WHEN status = 'heard' THEN 1 ELSE 0 END) AS heard,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
      FROM relays
      WHERE status IN ('queued', 'heard', 'failed')
      GROUP BY line
      HAVING queued > 0 OR heard > 0 OR failed > 0
      ORDER BY queued DESC, heard DESC, failed DESC, line ASC
    `).all() as Array<{ line: string, queued: number, heard: number, failed: number }>

    return rows.map((row) => ({
      line: row.line,
      queued: Number(row.queued),
      heard: Number(row.heard),
      failed: Number(row.failed),
    }))
  }

  expireStaleRelays(options: StaleRelayOptions = {}): number {
    const now = options.now ?? new Date()
    const ageMinutes = options.ageMinutes ?? defaultStaleRelayAgeMinutes
    const staleBefore = new Date(now.getTime() - ageMinutes * 60 * 1000).toISOString()
    const result = this.database.prepare(`
      UPDATE relays
      SET status = 'expired', updated_at = ?
      WHERE (
        status IN ('heard', 'failed') AND updated_at <= ?
      ) OR (
        status = 'queued'
        AND priority != 'high'
        AND type IN ('update', 'complete')
        AND created_at <= ?
      )
    `).run(now.toISOString(), staleBefore, staleBefore)

    return Number(result.changes)
  }

  queueOverview(options: QueueOverviewOptions = {}): QueueOverview {
    const limit = options.limit ?? defaultQueueOverviewLimit
    const staleBlockerAgeMinutes = options.staleBlockerAgeMinutes ?? defaultStaleBlockerAgeMinutes
    const now = options.now ?? new Date()
    const staleBefore = new Date(now.getTime() - staleBlockerAgeMinutes * 60 * 1000).toISOString()
    const byPriority = this.priorityOverview()
    const byProducer = this.producerOverview(limit)
    const staleBlockers = this.staleBlockerOverview(staleBefore, staleBlockerAgeMinutes)

    return {
      byPriority,
      byProducer,
      staleBlockers,
    }
  }

  private priorityOverview(): PriorityOverviewItem[] {
    const rows = this.database.prepare(`
      SELECT priority, COUNT(*) AS count
      FROM relays
      WHERE status IN ('queued', 'heard', 'failed')
      GROUP BY priority
    `).all() as Array<{ priority: Priority, count: number }>
    const counts = new Map(rows.map((row) => [row.priority, Number(row.count)]))

    return [...priorities]
      .reverse()
      .map((priority) => ({ priority, count: counts.get(priority) ?? 0 }))
      .filter((item) => item.count > 0)
  }

  private producerOverview(limit: number): ProducerOverviewItem[] {
    const rows = this.database.prepare(`
      SELECT
        COALESCE(session, app, 'unknown') AS producer,
        COUNT(*) AS count
      FROM relays
      WHERE status IN ('queued', 'heard', 'failed')
      GROUP BY producer
      ORDER BY count DESC, producer ASC
      LIMIT ?
    `).all(limit) as Array<{ producer: string, count: number }>

    return rows.map((row) => ({
      producer: row.producer,
      count: Number(row.count),
    }))
  }

  private staleBlockerOverview(staleBefore: string, thresholdMinutes: number): StaleBlockerOverview {
    const row = this.database.prepare(`
      SELECT COUNT(*) AS count, MIN(created_at) AS oldestCreatedAt
      FROM relays
      WHERE status IN ('queued', 'heard')
        AND priority = 'high'
        AND type IN ('blocked', 'needs-input')
        AND created_at <= ?
    `).get(staleBefore) as { count: number, oldestCreatedAt: string | null }
    const count = Number(row.count)

    return {
      count,
      thresholdMinutes,
      oldestCreatedAt: count > 0 && row.oldestCreatedAt !== null ? row.oldestCreatedAt : undefined,
    }
  }

  latestSourceContext(line?: string): SourceContext | undefined {
    const row = this.database.prepare(`
      SELECT id, line, session, app, cwd, url
      FROM relays
      WHERE (cwd IS NOT NULL OR url IS NOT NULL OR app IS NOT NULL OR session IS NOT NULL)
        AND (? IS NULL OR line = ?)
      ORDER BY created_at DESC, id DESC
      LIMIT 1
    `).get(line ?? null, line ?? null)

    if (row === undefined) {
      return undefined
    }

    return mapSourceContext(row)
  }

  latestSourceContextsByLine(): SourceContext[] {
    const rows = this.database.prepare(`
      SELECT id, line, session, app, cwd, url
      FROM relays AS source
      WHERE (cwd IS NOT NULL OR url IS NOT NULL OR app IS NOT NULL OR session IS NOT NULL)
        AND id = (
          SELECT id
          FROM relays AS candidate
          WHERE candidate.line = source.line
            AND (
              candidate.cwd IS NOT NULL
              OR candidate.url IS NOT NULL
              OR candidate.app IS NOT NULL
              OR candidate.session IS NOT NULL
            )
          ORDER BY created_at DESC, id DESC
          LIMIT 1
      )
      ORDER BY line ASC
    `).all()

    return rows.map(mapSourceContext)
  }

  clear(): number {
    const result = this.database.prepare(`
      DELETE FROM relays
      WHERE status IN ('queued', 'heard', 'handled', 'skipped', 'expired', 'failed')
    `).run()

    return Number(result.changes)
  }

  clearHeard(line?: string): number {
    if (line !== undefined) {
      const result = this.database.prepare(`
        DELETE FROM relays
        WHERE status = 'heard' AND line = ?
      `).run(line)

      return Number(result.changes)
    }

    const result = this.database.prepare(`
      DELETE FROM relays
      WHERE status = 'heard'
    `).run()

    return Number(result.changes)
  }

  clearQueued(line: string): number {
    const result = this.database.prepare(`
      DELETE FROM relays
      WHERE status = 'queued' AND line = ?
    `).run(line)

    return Number(result.changes)
  }

  skipNextQueued(line?: string): Relay | undefined {
    return this.markFirstMatchingStatus('queued', 'skipped', line)
  }

  markLatestHeardHandled(line?: string): Relay | undefined {
    return this.markLatestMatchingStatus('heard', 'handled', line)
  }

  replayLatestHeard(line?: string): Relay | undefined {
    return this.markLatestMatchingStatus('heard', 'queued', line)
  }

  getState(profile: DistributionProfile = distributionProfile()): QueueState {
    const mode = this.getSetting('mode') ?? 'focus'
    const muted = this.getSetting('muted') === 'true'
    const inactiveLineCombinerCommand = this.getSetting('inactive_line_combiner_command') ?? this.migratedInactiveLineCombinerCommand()
    const speechCommand = this.getSetting('speech_command') ?? defaultSpeechCommand
    const activeLine = this.getSetting('active_line')
    const appStore = profile === 'app-store'

    return {
      mode: mode === 'ready' ? 'ready' : 'focus',
      muted,
      inactiveLineCombiner: !appStore && commandIsEnabled(inactiveLineCombinerCommand) ? 'custom' : 'none',
      inactiveLineCombinerCommand: appStore ? appStoreUnavailableCommand('inactive-line combiner') : inactiveLineCombinerCommand,
      speechCommand: appStore ? appStoreUnavailableCommand('speech') : speechCommand,
      activeLine,
    }
  }

  setMode(mode: PlaybackMode): QueueState {
    this.setSetting('mode', mode)
    return this.getState()
  }

  setMuted(muted: boolean): QueueState {
    this.setSetting('muted', String(muted))
    return this.getState()
  }

  setInactiveLineCombinerCommand(command: string): QueueState {
    this.setSetting('inactive_line_combiner_command', resetBlankCommand(command, defaultInactiveLineCombinerCommand))
    return this.getState()
  }

  setSpeechCommand(command: string): QueueState {
    this.setSetting('speech_command', resetBlankCommand(command, defaultSpeechCommand))
    return this.getState()
  }

  setInactiveLineCombinerCommandForProfile(command: string, profile: DistributionProfile = distributionProfile()): QueueState {
    if (profile === 'app-store') {
      return this.getState(profile)
    }

    return this.setInactiveLineCombinerCommand(command)
  }

  setSpeechCommandForProfile(command: string, profile: DistributionProfile = distributionProfile()): QueueState {
    if (profile === 'app-store') {
      return this.getState(profile)
    }

    return this.setSpeechCommand(command)
  }

  setActiveLine(line: string): QueueState {
    const normalized = line.trim()

    if (normalized === '') {
      throw new Error('active line cannot be empty')
    }

    this.setSetting('active_line', normalized)
    return this.getState()
  }

  shouldPrefixSpokenLine(line: string, now = new Date(), timeoutMs = 60_000): boolean {
    const last = this.lastSpokenLine()

    if (last === undefined || last.line !== line) {
      return true
    }

    const spokenAt = Date.parse(last.spokenAt)

    if (Number.isNaN(spokenAt)) {
      return true
    }

    return now.getTime() - spokenAt >= timeoutMs
  }

  recordSpokenLine(line: string, now = new Date()): void {
    this.setSetting('last_spoken_line', JSON.stringify({ line, spokenAt: now.toISOString() }))
  }

  private lastSpokenLine(): SpokenLineState | undefined {
    const value = this.getSetting('last_spoken_line')

    if (value === undefined) {
      return undefined
    }

    try {
      const parsed = JSON.parse(value) as Record<string, unknown>

      if (typeof parsed.line === 'string' && typeof parsed.spokenAt === 'string') {
        return { line: parsed.line, spokenAt: parsed.spokenAt }
      }
    } catch {
      return undefined
    }

    return undefined
  }

  claimNextForSpeech(): Relay | undefined {
    const state = this.getState()

    if (state.muted || state.mode !== 'ready') {
      return undefined
    }

    const row = this.database.prepare(`
      UPDATE relays
      SET status = 'speaking', updated_at = ?
      WHERE id = (
        SELECT id
        FROM relays
        WHERE status = 'queued'
        ORDER BY
          CASE priority
            WHEN 'high' THEN 0
            WHEN 'normal' THEN 1
            ELSE 2
          END,
          created_at ASC
        LIMIT 1
      )
      RETURNING *
    `).get(new Date().toISOString())

    if (row === undefined) {
      return undefined
    }

    this.setMode('focus')
    return mapRelay(row)
  }

  claimNextForLine(line: string): Relay | undefined {
    const state = this.getState()

    if (state.muted) {
      return undefined
    }

    const row = this.database.prepare(`
      UPDATE relays
      SET status = 'speaking', updated_at = ?
      WHERE id = (
        SELECT id
        FROM relays
        WHERE status = 'queued' AND line = ?
        ORDER BY
          CASE priority
            WHEN 'high' THEN 0
            WHEN 'normal' THEN 1
            ELSE 2
          END,
          created_at ASC
        LIMIT 1
      )
      RETURNING *
    `).get(new Date().toISOString(), line)

    if (row === undefined) {
      return undefined
    }

    return mapRelay(row)
  }

  markStatus(id: number, status: MessageStatus): Relay {
    const row = this.database.prepare(`
      UPDATE relays
      SET status = ?, updated_at = ?
      WHERE id = ?
      RETURNING *
    `).get(status, new Date().toISOString(), id)

    if (row === undefined) {
      throw new Error(`relay ${id} not found`)
    }

    return mapRelay(row)
  }

  failStaleSpeaking(options: StaleSpeakingOptions = {}): number {
    const now = options.now ?? new Date()
    const ttlMs = options.ttlMs ?? 60_000
    const staleBefore = new Date(now.getTime() - ttlMs).toISOString()
    const result = this.database.prepare(`
      UPDATE relays
      SET status = 'failed', updated_at = ?
      WHERE status = 'speaking' AND updated_at <= ?
    `).run(now.toISOString(), staleBefore)

    return Number(result.changes)
  }

  private markFirstMatchingStatus(from: MessageStatus, to: MessageStatus, line?: string): Relay | undefined {
    const row = this.database.prepare(`
      UPDATE relays
      SET status = ?, updated_at = ?
      WHERE id = (
        SELECT id
        FROM relays
        WHERE status = ? AND (? IS NULL OR line = ?)
        ORDER BY
          CASE priority
            WHEN 'high' THEN 0
            WHEN 'normal' THEN 1
            ELSE 2
          END,
          created_at ASC
        LIMIT 1
      )
      RETURNING *
    `).get(to, new Date().toISOString(), from, line ?? null, line ?? null)

    return row === undefined ? undefined : mapRelay(row)
  }

  private markLatestMatchingStatus(from: MessageStatus, to: MessageStatus, line?: string): Relay | undefined {
    const row = this.database.prepare(`
      UPDATE relays
      SET status = ?, updated_at = ?
      WHERE id = (
        SELECT id
        FROM relays
        WHERE status = ? AND (? IS NULL OR line = ?)
        ORDER BY updated_at DESC, id DESC
        LIMIT 1
      )
      RETURNING *
    `).get(to, new Date().toISOString(), from, line ?? null, line ?? null)

    return row === undefined ? undefined : mapRelay(row)
  }

  acquireProcessorLock(owner: string, options: ProcessorLockOptions = {}): boolean {
    const now = options.now ?? new Date()
    const ttlMs = options.ttlMs ?? defaultProcessorLockTtlMs
    const isOwnerAlive = options.isOwnerAlive ?? processorOwnerIsAlive
    const lock = JSON.stringify({ owner, acquiredAt: now.toISOString() })
    const current = this.getSetting('processor_lock')

    if (current !== undefined && processorLockIsLive(current, now, ttlMs, isOwnerAlive)) {
      return false
    }

    this.database.prepare(`
      INSERT INTO settings (key, value)
      VALUES ('processor_lock', ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(lock)

    return true
  }

  releaseProcessorLock(owner: string): void {
    this.database.prepare(`
      DELETE FROM settings
      WHERE key = 'processor_lock'
        AND (
          value = ?
          OR (json_valid(value) AND json_extract(value, '$.owner') = ?)
        )
    `).run(owner, owner)
  }

  private migrate(): void {
    this.database.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY
      );
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS relays (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        line TEXT NOT NULL,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        priority TEXT NOT NULL,
        session TEXT,
        app TEXT,
        cwd TEXT,
        url TEXT,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      INSERT OR IGNORE INTO schema_migrations (version) VALUES (${schemaVersion});
      INSERT OR IGNORE INTO settings (key, value) VALUES ('mode', 'focus');
      INSERT OR IGNORE INTO settings (key, value) VALUES ('muted', 'false');
      INSERT OR IGNORE INTO settings (key, value) VALUES ('inactive_line_combiner', 'none');
      INSERT OR IGNORE INTO settings (key, value) VALUES ('inactive_line_combiner_command', '${escapeSql(defaultInactiveLineCombinerCommand)}');
      INSERT OR IGNORE INTO settings (key, value) VALUES ('speech_command', '${escapeSql(defaultSpeechCommand)}');
    `)
    this.migrateLegacyCombinerSetting()
  }

  private getSetting(key: string): string | undefined {
    const row = this.database.prepare('SELECT value FROM settings WHERE key = ?').get(key) as { value: string } | undefined
    return row?.value
  }

  private setSetting(key: string, value: string): void {
    this.database.prepare(`
      INSERT INTO settings (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `).run(key, value)
  }

  private setInitialActiveLine(line: string): void {
    this.database.prepare(`
      INSERT OR IGNORE INTO settings (key, value)
      VALUES ('active_line', ?)
    `).run(line)
  }

  private migratedInactiveLineCombinerCommand(): string {
    const legacy = this.getSetting('inactive_line_combiner')

    if (legacy === 'llm') {
      return 'llm prompt <input> --system <system> --no-stream --no-log'
    }

    if (legacy === 'apfel') {
      return 'apfel --system <system> --max-tokens 160 --temperature 0 --output plain <input>'
    }

    return defaultInactiveLineCombinerCommand
  }

  private migrateLegacyCombinerSetting(): void {
    const current = this.getSetting('inactive_line_combiner_command')

    if (current !== defaultInactiveLineCombinerCommand) {
      return
    }

    const migrated = this.migratedInactiveLineCombinerCommand()

    if (migrated !== defaultInactiveLineCombinerCommand) {
      this.setSetting('inactive_line_combiner_command', migrated)
    }
  }
}

export function defaultDatabasePath(): string {
  if (process.env.TSRS_DB_PATH !== undefined && process.env.TSRS_DB_PATH.trim() !== '') {
    return process.env.TSRS_DB_PATH
  }

  return join(homedir(), 'Library', 'Application Support', 'Tri-State Relay Service', 'relay.db')
}

function appStoreUnavailableCommand(feature: string): string {
  return `# External ${feature} command execution is unavailable in the App Store-safe profile.`
}

function mapRelay(row: unknown): Relay {
  if (row === undefined || row === null || typeof row !== 'object') {
    throw new Error('expected relay row')
  }

  const value = row as Record<string, unknown>

  return {
    id: Number(value.id),
    line: String(value.line),
    message: String(value.message),
    type: String(value.type) as Relay['type'],
    priority: String(value.priority) as Relay['priority'],
    session: optionalString(value.session),
    app: optionalString(value.app),
    cwd: optionalString(value.cwd),
    url: optionalString(value.url),
    status: String(value.status) as Relay['status'],
    createdAt: String(value.created_at),
    updatedAt: String(value.updated_at),
  }
}

function mapSourceContext(row: unknown): SourceContext {
  if (row === undefined || row === null || typeof row !== 'object') {
    throw new Error('expected source context row')
  }

  const value = row as Record<string, unknown>
  const source: SourceContext = {
    id: Number(value.id),
    line: String(value.line),
  }

  const session = optionalString(value.session)
  const app = optionalString(value.app)
  const cwd = optionalString(value.cwd)
  const url = optionalString(value.url)

  if (session !== undefined) source.session = session
  if (app !== undefined) source.app = app
  if (cwd !== undefined) source.cwd = cwd
  if (url !== undefined) source.url = url

  return source
}

function optionalString(value: unknown): string | undefined {
  if (value === null || value === undefined) {
    return undefined
  }

  return String(value)
}

function lastItem<T>(items: T[]): T | undefined {
  return items.length === 0 ? undefined : items[items.length - 1]
}

function processorLockIsLive(
  value: string,
  now: Date,
  ttlMs: number,
  isOwnerAlive: (owner: string) => boolean,
): boolean {
  const lock = parseProcessorLock(value)

  if (lock === undefined) {
    return true
  }

  const acquiredAt = Date.parse(lock.acquiredAt)

  if (Number.isNaN(acquiredAt) || now.getTime() - acquiredAt > ttlMs) {
    return false
  }

  return isOwnerAlive(lock.owner)
}

function parseProcessorLock(value: string): { owner: string, acquiredAt: string } | undefined {
  try {
    const parsed = JSON.parse(value) as Record<string, unknown>

    if (typeof parsed.owner === 'string' && typeof parsed.acquiredAt === 'string') {
      return { owner: parsed.owner, acquiredAt: parsed.acquiredAt }
    }
  } catch {
    return undefined
  }

  return undefined
}

function processorOwnerIsAlive(owner: string): boolean {
  const match = /^processor:(\d+)$/.exec(owner)

  if (match === null) {
    return true
  }

  try {
    process.kill(Number(match[1]), 0)
    return true
  } catch {
    return false
  }
}

function escapeSql(value: string): string {
  return value.replaceAll("'", "''")
}

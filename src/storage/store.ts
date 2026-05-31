import { mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { homedir } from 'node:os'
import Database from 'better-sqlite3'

import { commandIsEnabled, defaultInactiveLineCombinerCommand, defaultSpeechCommand, resetBlankCommand } from '../core/command-template.ts'
import { normalizeVoicemail, priorities, type MessageStatus, type MessageType, type NewVoicemail, type NewVoicemailInput, type Priority, type Voicemail } from '../core/message.ts'

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

export class VoicemailStore {
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

  enqueue(input: NewVoicemailInput): Voicemail {
    const voicemail = normalizeVoicemail(input)
    return this.insertVoicemail(voicemail)
  }

  enqueueWithLinePolicy(input: NewVoicemailInput, combine?: InactiveLineCombinerFunction): Voicemail | undefined {
    const voicemail = normalizeVoicemail(input)
    const state = this.getState()

    if (state.activeLine === undefined || voicemail.line === state.activeLine) {
      return this.insertVoicemail(voicemail)
    }

    if (state.inactiveLineCombiner === 'none' || combine === undefined) {
      this.deleteQueuedForLine(voicemail.line)
      return this.insertVoicemail(voicemail)
    }

    const existing = this.queuedForLine(voicemail.line)
    const combined = combine({
      activeLine: state.activeLine,
      inactiveLine: voicemail.line,
      existingPendingMessage: lastItem(existing)?.message,
      incoming: [
        ...existing.map((item) => ({
          type: item.type,
          priority: item.priority,
          message: item.message,
        })),
        {
          type: voicemail.type,
          priority: voicemail.priority,
          message: voicemail.message,
        },
      ],
    })

    if (combined === undefined || combined.action === 'drop') {
      return lastItem(existing)
    }

    this.deleteQueuedForLine(voicemail.line)
    return this.insertVoicemail({
      ...voicemail,
      message: combined.message,
      type: combined.type,
      priority: combined.priority,
    })
  }

  private insertVoicemail(voicemail: NewVoicemail): Voicemail {
    const now = new Date().toISOString()
    const insert = this.database.prepare(`
      INSERT INTO voicemails (
        line, message, type, priority, session, app, cwd, url, status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?)
      RETURNING *
    `)

    return mapVoicemail(insert.get(
      voicemail.line,
      voicemail.message,
      voicemail.type,
      voicemail.priority,
      voicemail.session ?? null,
      voicemail.app ?? null,
      voicemail.cwd ?? null,
      voicemail.url ?? null,
      now,
      now,
    ))
  }

  private queuedForLine(line: string): Voicemail[] {
    const select = this.database.prepare(`
      SELECT *
      FROM voicemails
      WHERE line = ? AND status = 'queued'
      ORDER BY created_at ASC
    `)

    return select.all(line).map(mapVoicemail)
  }

  private deleteQueuedForLine(line: string): number {
    const result = this.database.prepare(`
      DELETE FROM voicemails
      WHERE line = ? AND status = 'queued'
    `).run(line)

    return Number(result.changes)
  }

  list(limit = 20): Voicemail[] {
    const select = this.database.prepare(`
      SELECT *
      FROM voicemails
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

    return select.all(limit).map(mapVoicemail)
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
      FROM voicemails
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
      FROM voicemails
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
      FROM voicemails
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
      FROM voicemails
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
      FROM voicemails
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

  latestSourceContext(): SourceContext | undefined {
    const row = this.database.prepare(`
      SELECT id, line, session, app, cwd, url
      FROM voicemails
      WHERE cwd IS NOT NULL OR url IS NOT NULL OR app IS NOT NULL OR session IS NOT NULL
      ORDER BY created_at DESC, id DESC
      LIMIT 1
    `).get()

    if (row === undefined) {
      return undefined
    }

    const value = row as Record<string, unknown>

    return {
      id: Number(value.id),
      line: String(value.line),
      session: optionalString(value.session),
      app: optionalString(value.app),
      cwd: optionalString(value.cwd),
      url: optionalString(value.url),
    }
  }

  clear(): number {
    const result = this.database.prepare(`
      DELETE FROM voicemails
      WHERE status IN ('queued', 'heard', 'handled', 'skipped', 'expired', 'failed')
    `).run()

    return Number(result.changes)
  }

  clearHeard(line?: string): number {
    if (line !== undefined) {
      const result = this.database.prepare(`
        DELETE FROM voicemails
        WHERE status = 'heard' AND line = ?
      `).run(line)

      return Number(result.changes)
    }

    const result = this.database.prepare(`
      DELETE FROM voicemails
      WHERE status = 'heard'
    `).run()

    return Number(result.changes)
  }

  clearQueued(line: string): number {
    const result = this.database.prepare(`
      DELETE FROM voicemails
      WHERE status = 'queued' AND line = ?
    `).run(line)

    return Number(result.changes)
  }

  skipNextQueued(line?: string): Voicemail | undefined {
    return this.markFirstMatchingStatus('queued', 'skipped', line)
  }

  markLatestHeardHandled(line?: string): Voicemail | undefined {
    return this.markLatestMatchingStatus('heard', 'handled', line)
  }

  replayLatestHeard(line?: string): Voicemail | undefined {
    return this.markLatestMatchingStatus('heard', 'queued', line)
  }

  getState(): QueueState {
    const mode = this.getSetting('mode') ?? 'focus'
    const muted = this.getSetting('muted') === 'true'
    const inactiveLineCombinerCommand = this.getSetting('inactive_line_combiner_command') ?? this.migratedInactiveLineCombinerCommand()
    const speechCommand = this.getSetting('speech_command') ?? defaultSpeechCommand
    const activeLine = this.getSetting('active_line')

    return {
      mode: mode === 'ready' ? 'ready' : 'focus',
      muted,
      inactiveLineCombiner: commandIsEnabled(inactiveLineCombinerCommand) ? 'custom' : 'none',
      inactiveLineCombinerCommand,
      speechCommand,
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

  setActiveLine(line: string): QueueState {
    const normalized = line.trim()

    if (normalized === '') {
      throw new Error('active line cannot be empty')
    }

    this.setSetting('active_line', normalized)
    return this.getState()
  }

  claimNextForSpeech(): Voicemail | undefined {
    const state = this.getState()

    if (state.muted || state.mode !== 'ready') {
      return undefined
    }

    const row = this.database.prepare(`
      UPDATE voicemails
      SET status = 'speaking', updated_at = ?
      WHERE id = (
        SELECT id
        FROM voicemails
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
    return mapVoicemail(row)
  }

  claimNextForLine(line: string): Voicemail | undefined {
    const state = this.getState()

    if (state.muted) {
      return undefined
    }

    const row = this.database.prepare(`
      UPDATE voicemails
      SET status = 'speaking', updated_at = ?
      WHERE id = (
        SELECT id
        FROM voicemails
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

    return mapVoicemail(row)
  }

  markStatus(id: number, status: MessageStatus): Voicemail {
    const row = this.database.prepare(`
      UPDATE voicemails
      SET status = ?, updated_at = ?
      WHERE id = ?
      RETURNING *
    `).get(status, new Date().toISOString(), id)

    if (row === undefined) {
      throw new Error(`voicemail ${id} not found`)
    }

    return mapVoicemail(row)
  }

  private markFirstMatchingStatus(from: MessageStatus, to: MessageStatus, line?: string): Voicemail | undefined {
    const row = this.database.prepare(`
      UPDATE voicemails
      SET status = ?, updated_at = ?
      WHERE id = (
        SELECT id
        FROM voicemails
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

    return row === undefined ? undefined : mapVoicemail(row)
  }

  private markLatestMatchingStatus(from: MessageStatus, to: MessageStatus, line?: string): Voicemail | undefined {
    const row = this.database.prepare(`
      UPDATE voicemails
      SET status = ?, updated_at = ?
      WHERE id = (
        SELECT id
        FROM voicemails
        WHERE status = ? AND (? IS NULL OR line = ?)
        ORDER BY updated_at DESC, id DESC
        LIMIT 1
      )
      RETURNING *
    `).get(to, new Date().toISOString(), from, line ?? null, line ?? null)

    return row === undefined ? undefined : mapVoicemail(row)
  }

  acquireProcessorLock(owner: string): boolean {
    const result = this.database.prepare(`
      INSERT OR IGNORE INTO settings (key, value)
      VALUES ('processor_lock', ?)
    `).run(owner)

    return Number(result.changes) === 1
  }

  releaseProcessorLock(owner: string): void {
    this.database.prepare(`
      DELETE FROM settings
      WHERE key = 'processor_lock' AND value = ?
    `).run(owner)
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
      CREATE TABLE IF NOT EXISTS voicemails (
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

  return join(homedir(), 'Library', 'Application Support', 'Tri-State Relay Service', 'voicemail.db')
}

function mapVoicemail(row: unknown): Voicemail {
  if (row === undefined || row === null || typeof row !== 'object') {
    throw new Error('expected voicemail row')
  }

  const value = row as Record<string, unknown>

  return {
    id: Number(value.id),
    line: String(value.line),
    message: String(value.message),
    type: String(value.type) as Voicemail['type'],
    priority: String(value.priority) as Voicemail['priority'],
    session: optionalString(value.session),
    app: optionalString(value.app),
    cwd: optionalString(value.cwd),
    url: optionalString(value.url),
    status: String(value.status) as Voicemail['status'],
    createdAt: String(value.created_at),
    updatedAt: String(value.updated_at),
  }
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

function escapeSql(value: string): string {
  return value.replaceAll("'", "''")
}
